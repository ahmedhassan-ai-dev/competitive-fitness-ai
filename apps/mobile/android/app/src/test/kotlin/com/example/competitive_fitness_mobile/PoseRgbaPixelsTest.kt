package com.example.competitive_fitness_mobile

import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer

class PoseRgbaPixelsTest {
    @Test fun `packed RGBA is converted to ARGB without channel swaps`() {
        val source = ByteBuffer.wrap(byteArrayOf(
            0x11, 0x22, 0x33, 0xff.toByte(),
            0x80.toByte(), 0x40, 0x20, 0xff.toByte(),
        ))
        val output = IntArray(2)
        copyRgbaToArgb(source, 2, 1, 8, 4, output)
        assertEquals(0xff112233.toInt(), output[0])
        assertEquals(0xff804020.toInt(), output[1])
    }

    @Test fun `row padding and nonzero buffer position are supported`() {
        val source = ByteBuffer.wrap(byteArrayOf(
            0x00, 0x00,
            0xff.toByte(), 0x00, 0x00, 0xff.toByte(), 0x7f, 0x7f,
            0x00, 0xff.toByte(), 0x00, 0xff.toByte(),
        ))
        source.position(2)
        val output = IntArray(2)
        copyRgbaToArgb(source, 1, 2, 6, 4, output)
        assertEquals(0xffff0000.toInt(), output[0])
        assertEquals(0xff00ff00.toInt(), output[1])
    }
}
