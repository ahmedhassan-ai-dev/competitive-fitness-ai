package com.example.competitive_fitness_mobile

import kotlin.math.PI
import kotlin.math.abs

/**
 * Adaptive low-pass filter for VISUAL overlay points only. Raw landmark
 * coordinates still reach the rep counter without filter-induced latency.
 * State is confined to one ImageAnalysis analyzer thread and one lens session.
 */
internal class PoseLandmarkSmoother(
    private val minimumConfidence: Double = 0.50,
    private val maxGapMs: Long = 350,
) {
    private data class Sample(
        var x: Double,
        var y: Double,
        var lastRawX: Double,
        var lastRawY: Double,
        var dx: Double,
        var dy: Double,
        var timestampMs: Long,
    )

    private val history = mutableMapOf<String, Sample>()

    fun filter(
        landmarks: Map<String, Map<String, Double>>,
        timestampMs: Long,
    ): Map<String, Map<String, Double>> {
        if (landmarks.isEmpty()) {
            history.clear()
            return landmarks
        }
        history.keys.retainAll(landmarks.keys)
        return landmarks.mapValues { (name, point) ->
            val x = point["x"] ?: return@mapValues point
            val y = point["y"] ?: return@mapValues point
            val confidence = point["confidence"] ?: return@mapValues point
            if (!x.isFinite() || !y.isFinite() || !confidence.isFinite() ||
                confidence < minimumConfidence
            ) {
                history.remove(name)
                return@mapValues point
            }
            val previous = history[name]
            val deltaMs = if (previous == null) 0L else timestampMs - previous.timestampMs
            if (previous == null || deltaMs <= 0 || deltaMs > maxGapMs) {
                history[name] = Sample(x, y, x, y, 0.0, 0.0, timestampMs)
                return@mapValues point
            }
            val dt = deltaMs / 1000.0
            // One Euro: low cutoff at rest, higher cutoff for quick movement.
            val derivativeAlpha = alpha(dt, 1.0)
            val derivativeX = (x - previous.lastRawX) / dt
            val derivativeY = (y - previous.lastRawY) / dt
            previous.dx += derivativeAlpha * (derivativeX - previous.dx)
            previous.dy += derivativeAlpha * (derivativeY - previous.dy)
            val filteredX = previous.x + alpha(dt, 2.0 + 1.0 * abs(previous.dx)) *
                (x - previous.x)
            val filteredY = previous.y + alpha(dt, 2.0 + 1.0 * abs(previous.dy)) *
                (y - previous.y)
            previous.x = filteredX
            previous.y = filteredY
            previous.lastRawX = x
            previous.lastRawY = y
            previous.timestampMs = timestampMs
            point + mapOf("x" to filteredX, "y" to filteredY)
        }
    }

    fun reset() = history.clear()

    private fun alpha(dtSeconds: Double, cutoffHz: Double): Double {
        val tau = 1.0 / (2.0 * PI * cutoffHz)
        return dtSeconds / (tau + dtSeconds)
    }
}
