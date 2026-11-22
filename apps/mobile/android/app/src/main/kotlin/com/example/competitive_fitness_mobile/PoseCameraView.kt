package com.example.competitive_fitness_mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.camera.view.TransformExperimental
import androidx.camera.view.transform.CoordinateTransform
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal class PoseCameraViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return PoseCameraView(context, viewId, messenger)
    }
}

@androidx.annotation.OptIn(markerClass = [TransformExperimental::class])
private class PoseCameraView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView {
    private val activity = context.requireActivity()
    private val root = FrameLayout(context)
    private val previewView = PreviewView(context).also {
        it.scaleType = PreviewView.ScaleType.FILL_CENTER
        it.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        root.addView(
            it,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
    private val poseOverlay = PoseOverlayView(context).also {
        root.addView(
            it,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun Context.requireActivity(): Activity {
        var current = this
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return current as? Activity
            ?: throw IllegalStateException("Pose camera view requires an Activity context.")
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val modelExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile private var eventSink: EventChannel.EventSink? = null
    private var landmarker: PoseLandmarker? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var disposed = false
    private var modelReady = false
    private var modelError: String? = null
    // Rear camera is the default; camera switch remains available.
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    @Volatile private var cameraGeneration = 0
    private var pendingLayoutListener: View.OnLayoutChangeListener? = null
    // The landmarks are detected on an upright bitmap. CameraX owns preview
    // cropping, rotation, and selfie mirroring; do not mirror the overlay again.
    private val sourceTransformFactory = ImageProxyTransformFactory().apply {
        setUsingRotationDegrees(true)
        setUsingCropRect(false)
    }

    private val eventChannel = EventChannel(messenger, "$EVENT_CHANNEL_PREFIX/$viewId")
    private val cameraControlChannel =
        MethodChannel(messenger, "$CONTROL_CHANNEL_PREFIX/$viewId")

    init {
        cameraControlChannel.setMethodCallHandler { call, reply ->
            if (call.method != "switchCamera") {
                reply.notImplemented()
                return@setMethodCallHandler
            }
            val provider = cameraProvider
            if (disposed || !modelReady || eventSink == null || imageAnalysis == null ||
                provider == null
            ) {
                reply.error("camera_not_ready", "Start live tracking before switching cameras.", null)
                return@setMethodCallHandler
            }
            val nextLens = if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                CameraSelector.LENS_FACING_BACK
            } else {
                CameraSelector.LENS_FACING_FRONT
            }
            try {
                if (!provider.hasCamera(selectorFor(nextLens))) {
                    reply.error("camera_unavailable", "This device has no camera on that side.", null)
                    return@setMethodCallHandler
                }
                stopCamera()
                lensFacing = nextLens
                startCamera(reply)
            } catch (error: Exception) {
                reply.error("camera_switch_error", error.message ?: "Camera switch failed.", null)
            }
        }
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    modelError?.let {
                        events.error("pose_model_error", it, null)
                        return
                    }
                    if (modelReady) startCamera() else events.success(status("downloading_model"))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopCamera()
                }
            },
        )
        modelExecutor.execute {
            try {
                val modelFile = ensureModelFile(context)
                val bytes = modelFile.readBytes()
                val modelBuffer = ByteBuffer.allocateDirect(bytes.size).apply {
                    put(bytes)
                    flip()
                }
                val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(
                        BaseOptions.builder()
                            .setModelAssetBuffer(modelBuffer)
                            .build(),
                    )
                    .setRunningMode(RunningMode.VIDEO)
                    .setNumPoses(1)
                    .setMinPoseDetectionConfidence(0.5f)
                    .setMinTrackingConfidence(0.5f)
                    .build()
                val createdLandmarker = PoseLandmarker.createFromOptions(context, options)
                mainHandler.post {
                    if (disposed) {
                        createdLandmarker.close()
                    } else {
                        landmarker = createdLandmarker
                        modelReady = true
                        eventSink?.success(status("ready"))
                        if (eventSink != null) startCamera()
                    }
                }
            } catch (error: Exception) {
                val message = error.message ?: "Could not load pose model."
                mainHandler.post {
                    modelError = message
                    eventSink?.error("pose_model_error", message, null)
                }
            }
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        eventChannel.setStreamHandler(null)
        cameraControlChannel.setMethodCallHandler(null)
        stopCamera()
        landmarker?.close()
        landmarker = null
        modelExecutor.shutdownNow()
        analysisExecutor.shutdownNow()
    }

    private fun selectorFor(facing: Int): CameraSelector =
        if (facing == CameraSelector.LENS_FACING_FRONT) {
            CameraSelector.DEFAULT_FRONT_CAMERA
        } else {
            CameraSelector.DEFAULT_BACK_CAMERA
        }

    // A single Android platform view stays alive across switches, preserving
    // the MediaPipe model and the Dart workout session / rep count.
    private fun startCamera(reply: MethodChannel.Result? = null) {
        if (disposed || eventSink == null || !modelReady || imageAnalysis != null) {
            reply?.error("camera_not_ready", "Camera tracking is unavailable.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            val message = "Camera permission was not granted."
            if (reply != null) {
                reply.error("camera_permission_missing", message, null)
            } else {
                eventSink?.error("camera_permission_missing", message, null)
            }
            return
        }

        val generation = cameraGeneration
        val providerFuture = ProcessCameraProvider.getInstance(activity)
        providerFuture.addListener(
            {
                if (disposed || eventSink == null || generation != cameraGeneration) {
                    reply?.error("camera_cancelled", "Camera startup was cancelled.", null)
                    return@addListener
                }
                try {
                    val provider = providerFuture.get()
                    // Older / unusual Android devices may lack a selfie camera.
                    // Fall back to the available camera at startup.
                    if (!provider.hasCamera(selectorFor(lensFacing))) {
                        lensFacing = when {
                            provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ->
                                CameraSelector.LENS_FACING_BACK
                            provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ->
                                CameraSelector.LENS_FACING_FRONT
                            else -> throw IllegalStateException("No usable camera was found.")
                        }
                    }
                    val viewPort = previewView.viewPort
                    if (viewPort == null) {
                        // PlatformView's stream can be subscribed before Android lays out
                        // PreviewView. Defer binding instead of guessing a crop geometry.
                        eventSink?.success(status("waiting_for_preview"))
                        pendingLayoutListener?.let(previewView::removeOnLayoutChangeListener)
                        val listener = object : View.OnLayoutChangeListener {
                            override fun onLayoutChange(
                                view: View, left: Int, top: Int, right: Int, bottom: Int,
                                oldLeft: Int, oldTop: Int, oldRight: Int, oldBottom: Int,
                            ) {
                                if (previewView.viewPort != null) {
                                    previewView.removeOnLayoutChangeListener(this)
                                    pendingLayoutListener = null
                                    if (!disposed && generation == cameraGeneration) {
                                        startCamera(reply)
                                    }
                                }
                            }
                        }
                        pendingLayoutListener = listener
                        previewView.addOnLayoutChangeListener(listener)
                        return@addListener
                    }
                    val preview = Preview.Builder()
                        .setTargetResolution(Size(640, 480))
                        .build()
                        .also { it.setSurfaceProvider(previewView.surfaceProvider) }
                    val analysis = ImageAnalysis.Builder()
                        .setTargetResolution(Size(640, 480))
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .build()
                    // Each camera generation owns its own metrics window.
                    val perfMonitor = PosePerformanceMonitor()
                    analysis.setAnalyzer(analysisExecutor) { image ->
                        try {
                            if (!disposed && generation == cameraGeneration) {
                                processImage(image, generation, perfMonitor)
                            }
                        } catch (error: Exception) {
                            val message = error.message ?: "Pose inference failed."
                            mainHandler.post {
                                if (!disposed && generation == cameraGeneration) {
                                    eventSink?.error("pose_inference_error", message, null)
                                    imageAnalysis?.clearAnalyzer()
                                }
                            }
                        } finally {
                            image.close()
                        }
                    }
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        activity as LifecycleOwner,
                        selectorFor(lensFacing),
                        UseCaseGroup.Builder()
                            .addUseCase(preview)
                            .addUseCase(analysis)
                            .setViewPort(viewPort)
                            .build(),
                    )
                    cameraProvider = provider
                    imageAnalysis = analysis
                    eventSink?.success(
                        mapOf(
                            "type" to "lens",
                            "facing" to if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                                "front"
                            } else {
                                "back"
                            },
                        ),
                    )
                    eventSink?.success(status("tracking"))
                    reply?.success(
                        if (lensFacing == CameraSelector.LENS_FACING_FRONT) "front" else "back",
                    )
                } catch (error: Exception) {
                    val message = error.message ?: "Could not start camera."
                    if (reply != null) {
                        reply.error("camera_start_error", message, null)
                    } else {
                        eventSink?.error("camera_start_error", message, null)
                    }
                }
            },
            ContextCompat.getMainExecutor(activity),
        )
    }

    private fun processImage(
        image: androidx.camera.core.ImageProxy,
        generation: Int,
        perfMonitor: PosePerformanceMonitor,
    ) {
        val startNs = SystemClock.elapsedRealtimeNanos()
        // Extract this while ImageProxy is valid. It remains safe after close().
        val sourceTransform: OutputTransform = sourceTransformFactory.getOutputTransform(image)
        val plane = image.planes.first()
        val source = plane.buffer.duplicate()
        val bytes = ByteArray(source.remaining())
        source.get(bytes)
        val pixels = IntArray(image.width * image.height)
        for (y in 0 until image.height) {
            for (x in 0 until image.width) {
                val offset = y * plane.rowStride + x * plane.pixelStride
                val red = bytes[offset].toInt() and 0xff
                val green = bytes[offset + 1].toInt() and 0xff
                val blue = bytes[offset + 2].toInt() and 0xff
                pixels[y * image.width + x] =
                    (0xff shl 24) or (red shl 16) or (green shl 8) or blue
            }
        }
        val bitmap = Bitmap.createBitmap(pixels, image.width, image.height, Bitmap.Config.ARGB_8888)
        val rotation = image.imageInfo.rotationDegrees
        val orientedBitmap = if (rotation == 0) {
            bitmap
        } else {
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                .also { bitmap.recycle() }
        }
        val mpImage = BitmapImageBuilder(orientedBitmap).build()
        val preparedNs = SystemClock.elapsedRealtimeNanos()
        val imageWidth = orientedBitmap.width
        val imageHeight = orientedBitmap.height
        try {
            // RunningMode.VIDEO requires a monotonic timestamp for each frame.
            val timestamp = SystemClock.elapsedRealtime()
            val result = checkNotNull(landmarker).detectForVideo(mpImage, timestamp)
            val inferredNs = SystemClock.elapsedRealtimeNanos()
            val pose = result.landmarks().firstOrNull().orEmpty()
            val landmarks = listOf(
                "left_shoulder" to point(pose, 11, imageWidth, imageHeight),
                "right_shoulder" to point(pose, 12, imageWidth, imageHeight),
                "left_elbow" to point(pose, 13, imageWidth, imageHeight),
                "right_elbow" to point(pose, 14, imageWidth, imageHeight),
                "left_wrist" to point(pose, 15, imageWidth, imageHeight),
                "right_wrist" to point(pose, 16, imageWidth, imageHeight),
                "left_hip" to point(pose, 23, imageWidth, imageHeight),
                "right_hip" to point(pose, 24, imageWidth, imageHeight),
                "left_knee" to point(pose, 25, imageWidth, imageHeight),
                "right_knee" to point(pose, 26, imageWidth, imageHeight),
                "left_ankle" to point(pose, 27, imageWidth, imageHeight),
                "right_ankle" to point(pose, 28, imageWidth, imageHeight),
            ).mapNotNull { (name, value) -> value?.let { name to it } }.toMap()
            val event = mapOf(
                "type" to "pose",
                "timestampMs" to timestamp,
                "landmarks" to landmarks,
            )
            val reported = perfMonitor.record(
                endNs = inferredNs,
                prepMs = (preparedNs - startNs) / 1_000_000.0,
                inferenceMs = (inferredNs - preparedNs) / 1_000_000.0,
                poseFound = pose.isNotEmpty(),
            )
            mainHandler.post {
                if (!disposed && generation == cameraGeneration) {
                    val targetTransform = previewView.outputTransform
                    if (targetTransform == null) {
                        poseOverlay.clear()
                    } else {
                        try {
                            val matrix = Matrix()
                            CoordinateTransform(sourceTransform, targetTransform).transform(matrix)
                            poseOverlay.setLandmarks(landmarks, imageWidth, imageHeight, matrix)
                        } catch (_: IllegalArgumentException) {
                            // A stale/mismatched preview transform is worse than no overlay.
                            poseOverlay.clear()
                        }
                    }
                    eventSink?.success(event)
                    if (reported != null) eventSink?.success(reported)
                }
            }
        } finally {
            mpImage.close()
            orientedBitmap.recycle()
        }
    }

    private fun point(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>,
        index: Int,
        width: Int,
        height: Int,
    ): Map<String, Double>? {
        val landmark = landmarks.getOrNull(index) ?: return null
        val commonScale = maxOf(width, height).toDouble()
        // Use one pixel scale for both axes so image aspect ratio cannot skew joint angles.
        val x = landmark.x().toDouble() * width / commonScale
        val y = landmark.y().toDouble() * height / commonScale
        val visibility = landmark.visibility().orElse(landmark.presence().orElse(0f))
        val presence = landmark.presence().orElse(visibility)
        val confidence = minOf(
            visibility.toDouble(),
            presence.toDouble(),
        )
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) return null
        return mapOf("x" to x, "y" to y, "confidence" to confidence)
    }

    private fun stopCamera() {
        cameraGeneration++
        pendingLayoutListener?.let(previewView::removeOnLayoutChangeListener)
        pendingLayoutListener = null
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        cameraProvider?.unbindAll()
        cameraProvider = null
        poseOverlay.clear()
    }

    private fun status(value: String) = mapOf("type" to "status", "status" to value)

    private fun ensureModelFile(context: Context): File {
        val modelFile = File(context.cacheDir, MODEL_FILE)
        if (modelFile.isFile && sha256(modelFile) == MODEL_SHA256) return modelFile
        modelFile.delete()

        val temporaryFile = File(context.cacheDir, "$MODEL_FILE.download")
        val connection = URL(MODEL_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
            connection.connect()
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException(
                    "MediaPipe model download returned HTTP ${connection.responseCode}.",
                )
            }
            if (connection.contentLengthLong > MAX_MODEL_BYTES) {
                throw IllegalStateException("MediaPipe model download exceeded the size limit.")
            }
            connection.inputStream.use { input ->
                FileOutputStream(temporaryFile).use { output ->
                    val buffer = ByteArray(16 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_MODEL_BYTES) {
                            throw IllegalStateException(
                                "MediaPipe model download exceeded the size limit.",
                            )
                        }
                        output.write(buffer, 0, read)
                    }
                }

            }
            if (sha256(temporaryFile) != MODEL_SHA256) {
                throw IllegalStateException("Downloaded MediaPipe model failed SHA-256 verification.")
            }
            if (!temporaryFile.renameTo(modelFile)) {
                throw IllegalStateException("Could not save the verified MediaPipe model.")
            }
            return modelFile
        } finally {
            connection.disconnect()
            temporaryFile.delete()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private companion object {
        const val EVENT_CHANNEL_PREFIX = "competitive_fitness/pose"
        const val CONTROL_CHANNEL_PREFIX = "competitive_fitness/pose_camera_control"
        const val MODEL_FILE = "pose_landmarker_lite.task"
        const val MODEL_URL =
            "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
        const val MODEL_SHA256 = "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a"
        const val MAX_MODEL_BYTES = 20L * 1024 * 1024
    }
}

private class PoseOverlayView(context: Context) : View(context) {
    private data class Point(val x: Float, val y: Float, val confidence: Float)

    private var points = emptyMap<String, Point>()
    private val minimumConfidence = 0.5f
    private val bones = listOf(
        "left_shoulder" to "right_shoulder",
        "left_shoulder" to "left_elbow",
        "left_elbow" to "left_wrist",
        "right_shoulder" to "right_elbow",
        "right_elbow" to "right_wrist",
        "left_shoulder" to "left_hip",
        "right_shoulder" to "right_hip",
        "left_hip" to "right_hip",
        "left_hip" to "left_knee",
        "left_knee" to "left_ankle",
        "right_hip" to "right_knee",
        "right_knee" to "right_ankle",
    )
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(210, 239, 137)
        strokeWidth = 3f * resources.displayMetrics.density
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val jointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val jointRadius = 4f * resources.displayMetrics.density

    fun setLandmarks(
        landmarks: Map<String, Map<String, Double>>,
        imageWidth: Int,
        imageHeight: Int,
        imageToPreview: Matrix,
    ) {
        // Dart gets aspect-safe joint coordinates for calculating angles;
        // convert those back to the upright image's pixel coordinate system
        // before applying CameraX's exact image->PreviewView transformation.
        val commonScale = maxOf(imageWidth, imageHeight).toFloat()
        points = landmarks.mapNotNull { (name, value) ->
            val x = value["x"]?.toFloat()
            val y = value["y"]?.toFloat()
            val confidence = value["confidence"]?.toFloat()
            if (x != null && y != null && confidence != null &&
                x.isFinite() && y.isFinite() && confidence.isFinite()
            ) {
                val coords = floatArrayOf(x * commonScale, y * commonScale)
                imageToPreview.mapPoints(coords)
                name to Point(coords[0], coords[1], confidence)
            } else {
                null
            }
        }.toMap()
        invalidate()
    }

    fun clear() {
        points = emptyMap()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // Coordinates are already view pixels, including crop, rotation, mirroring.
        for ((startName, endName) in bones) {
            val start = points[startName]
            val end = points[endName]
            if (start != null && end != null &&
                start.confidence >= minimumConfidence &&
                end.confidence >= minimumConfidence
            ) {
                canvas.drawLine(
                    start.x,
                    start.y,
                    end.x,
                    end.y,
                    linePaint,
                )
            }
        }
        points.values
            .filter { it.confidence >= minimumConfidence }
            .forEach { canvas.drawCircle(it.x, it.y, jointRadius, jointPaint) }
    }
}
