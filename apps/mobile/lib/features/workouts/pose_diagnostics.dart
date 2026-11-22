/// Rolling on-device CameraX/MediaPipe analysis diagnostics.
/// Processed FPS is not preview FPS; P95 covers preprocessing + inference only.
class PoseDiagnostics {
  const PoseDiagnostics({
    required this.processedFps,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.pipelineP95Ms,
    required this.poseRatePercent,
    required this.sampleCount,
  });

  final double processedFps;
  final double preprocessMs;
  final double inferenceMs;
  final double pipelineP95Ms;
  final double poseRatePercent;
  final int sampleCount;

  static PoseDiagnostics? fromEvent(Map<dynamic, dynamic> event) {
    if (event['type'] != 'diagnostics') return null;
    double? field(String name) {
      final value = event[name];
      if (value is! num || !value.isFinite) return null;
      return value.toDouble();
    }

    final fps = field('processedFps');
    final prep = field('preprocessMs');
    final inference = field('inferenceMs');
    final p95 = field('pipelineP95Ms');
    final pose = field('poseRatePercent');
    final count = event['sampleCount'];
    if (fps == null || prep == null || inference == null || p95 == null ||
        pose == null || count is! int || count < 2 || fps < 0 ||
        prep < 0 || inference < 0 || p95 < 0 || pose < 0 || pose > 100) {
      return null;
    }
    return PoseDiagnostics(
      processedFps: fps,
      preprocessMs: prep,
      inferenceMs: inference,
      pipelineP95Ms: p95,
      poseRatePercent: pose,
      sampleCount: count,
    );
  }
}
