package com.example.competitive_fitness_mobile

import java.util.ArrayDeque
import kotlin.math.round

/** Lightweight analyzer-thread-only, sliding-window diagnostics. No images or poses stored. */
internal class PosePerformanceMonitor(
    private val windowSize: Int = 60,
    private val reportIntervalNs: Long = 1_500_000_000L,
) {
    private data class Sample(
        val endNs: Long,
        val prepMs: Double,
        val inferenceMs: Double,
        val poseFound: Boolean,
    )

    private val window = ArrayDeque<Sample>()
    private var lastReportNs = 0L

    fun record(
        endNs: Long,
        prepMs: Double,
        inferenceMs: Double,
        poseFound: Boolean,
    ): Map<String, Any>? {
        if (prepMs < 0 || inferenceMs < 0 || !prepMs.isFinite() || !inferenceMs.isFinite()) {
            return null
        }
        window.addLast(Sample(endNs, prepMs, inferenceMs, poseFound))
        if (window.size > windowSize) window.removeFirst()
        if (window.size < 2) return null
        if (lastReportNs != 0L && endNs - lastReportNs < reportIntervalNs) return null
        val spanNs = window.last.endNs - window.first.endNs
        if (spanNs <= 0L) return null
        lastReportNs = endNs
        val samples = window.toList()
        val sortedTimes = samples.map { it.prepMs + it.inferenceMs }.sorted()
        val p95Index = kotlin.math.ceil(sortedTimes.size * 0.95).toInt().minus(1)
            .coerceIn(0, sortedTimes.size - 1)
        fun rounded(value: Double): Double = round(value * 10) / 10.0
        return mapOf(
            "type" to "diagnostics",
            // Processed analysis throughput, NOT camera sensor frame rate.
            "processedFps" to rounded((samples.size - 1) * 1e9 / spanNs),
            "preprocessMs" to rounded(samples.map { it.prepMs }.average()),
            "inferenceMs" to rounded(samples.map { it.inferenceMs }.average()),
            "pipelineP95Ms" to rounded(sortedTimes[p95Index]),
            "poseRatePercent" to rounded(
                100.0 * samples.count { it.poseFound } / samples.size,
            ),
            "sampleCount" to samples.size,
        )
    }
}
