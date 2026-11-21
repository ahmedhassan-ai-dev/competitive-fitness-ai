package com.example.competitive_fitness_mobile

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cameraPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERA_PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestCameraPermission") {
                result.notImplemented()
            } else if (
                ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
            } else if (cameraPermissionResult != null) {
                result.error("permission_in_progress", "Camera permission is already requested.", null)
            } else {
                cameraPermissionResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.CAMERA),
                    CAMERA_PERMISSION_REQUEST,
                )
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory(
            POSE_CAMERA_VIEW,
            PoseCameraViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            cameraPermissionResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            cameraPermissionResult = null
        }
    }

    private companion object {
        const val CAMERA_PERMISSION_CHANNEL = "competitive_fitness/camera_permission"
        const val CAMERA_PERMISSION_REQUEST = 9401
        const val POSE_CAMERA_VIEW = "competitive_fitness/pose_camera"
    }
}
