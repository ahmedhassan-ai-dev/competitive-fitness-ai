package com.example.competitive_fitness_mobile

import android.graphics.Bitmap
import android.graphics.PixelFormat
import androidx.camera.core.ImageProxy

/** Reuses conversion buffers on the ImageAnalysis thread to reduce GC spikes. */
internal class PoseRgbaFrameConverter {
    private var pixels = IntArray(0)
    private var bitmap: Bitmap? = null

    fun convert(image: ImageProxy): Bitmap {
        require(image.format == PixelFormat.RGBA_8888) {
            "Expected RGBA_8888 camera analysis; got ${image.format}"
        }
        val plane = image.planes.first()
        val width = image.width
        val height = image.height
        val count = width * height
        if (pixels.size != count) pixels = IntArray(count)
        copyRgbaToArgb(plane.buffer, width, height, plane.rowStride, plane.pixelStride, pixels)
        var result = bitmap
        if (result == null || result.isRecycled || result.width != width || result.height != height) {
            result?.recycle()
            result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap = result
        }
        val ready = checkNotNull(result)
        ready.setPixels(pixels, 0, width, 0, 0, width, height)
        return ready
    }

    fun release() {
        bitmap?.recycle()
        bitmap = null
        pixels = IntArray(0)
    }
}
