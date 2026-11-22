package com.example.competitive_fitness_mobile

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** CameraX RGBA_8888 bytes are R, G, B, A (ImageAnalysis API contract). */
internal fun copyRgbaToArgb(
    data: ByteBuffer,
    width: Int,
    height: Int,
    rowStride: Int,
    pixelStride: Int,
    output: IntArray,
) {
    require(width > 0 && height > 0 && pixelStride >= 4)
    require(rowStride >= (width - 1) * pixelStride + 4)
    require(output.size >= width * height)
    val source = data.duplicate()
    val start = source.position()
    require(source.limit() - start >=
        (height - 1) * rowStride + (width - 1) * pixelStride + 4)
    if (pixelStride == 4 && rowStride == width * 4) {
        // Bulk read packed little-endian RGBA as AABBGGRR integers.
        source.position(start)
        val packed = source.slice().order(ByteOrder.LITTLE_ENDIAN).asIntBuffer()
        for (i in 0 until width * height) {
            val rgba = packed.get(i)
            output[i] = (rgba and 0xff000000.toInt()) or
                ((rgba and 0xff) shl 16) or
                (rgba and 0x0000ff00) or
                ((rgba ushr 16) and 0xff)
        }
        return
    }
    var out = 0
    for (row in 0 until height) {
        var offset = start + row * rowStride
        for (column in 0 until width) {
            val r = source.get(offset).toInt() and 0xff
            val g = source.get(offset + 1).toInt() and 0xff
            val b = source.get(offset + 2).toInt() and 0xff
            val a = source.get(offset + 3).toInt() and 0xff
            output[out++] = (a shl 24) or (r shl 16) or (g shl 8) or b
            offset += pixelStride
        }
    }
}
