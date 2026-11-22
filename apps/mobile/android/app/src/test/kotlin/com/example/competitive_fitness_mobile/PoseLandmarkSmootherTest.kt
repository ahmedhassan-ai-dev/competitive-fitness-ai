package com.example.competitive_fitness_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PoseLandmarkSmootherTest {
    private fun pose(x: Double, confidence: Double = 0.95) =
        mapOf("elbow" to mapOf("x" to x, "y" to 0.5, "confidence" to confidence))

    @Test fun `static jitter is reduced`() {
        val filter = PoseLandmarkSmoother()
        filter.filter(pose(0.5), 100)
        val value = filter.filter(pose(0.52), 133)["elbow"]!!["x"]!!
        assertTrue(value > 0.5 && value < 0.52)
    }

    @Test fun `fast movement is followed without freezing`() {
        val filter = PoseLandmarkSmoother()
        filter.filter(pose(0.1), 100)
        val first = filter.filter(pose(0.45), 133)["elbow"]!!["x"]!!
        val second = filter.filter(pose(0.8), 166)["elbow"]!!["x"]!!
        assertTrue(first > 0.1)
        assertTrue(second > first)
        assertTrue(second <= 0.8)
    }

    @Test fun `long frame gaps reset filter`() {
        val filter = PoseLandmarkSmoother()
        filter.filter(pose(0.15), 100)
        val value = filter.filter(pose(0.75), 1000)["elbow"]!!["x"]!!
        assertEquals(0.75, value, 0.00001)
    }

    @Test fun `unreliable frame does not smear the next valid point`() {
        val filter = PoseLandmarkSmoother()
        filter.filter(pose(0.15), 100)
        filter.filter(pose(0.95, 0.1), 133)
        val value = filter.filter(pose(0.8), 166)["elbow"]!!["x"]!!
        assertEquals(0.8, value, 0.00001)
    }
}
