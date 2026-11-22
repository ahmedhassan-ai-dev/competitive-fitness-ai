import 'package:competitive_fitness_mobile/features/workouts/pose_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a valid native metrics event', () {
    final metrics = PoseDiagnostics.fromEvent({
      'type': 'diagnostics',
      'processedFps': 15.6,
      'preprocessMs': 11.2,
      'inferenceMs': 42,
      'pipelineP95Ms': 77.5,
      'poseRatePercent': 90,
      'sampleCount': 60,
    });
    expect(metrics, isNotNull);
    expect(metrics!.processedFps, 15.6);
    expect(metrics.inferenceMs, 42);
    expect(metrics.sampleCount, 60);
  });

  test('rejects invalid, missing and out of range measurements', () {
    expect(PoseDiagnostics.fromEvent({'type': 'pose'}), isNull);
    expect(PoseDiagnostics.fromEvent({'type': 'diagnostics'}), isNull);
    expect(PoseDiagnostics.fromEvent({
      'type': 'diagnostics',
      'processedFps': double.nan,
      'preprocessMs': 10,
      'inferenceMs': 40,
      'pipelineP95Ms': 80,
      'poseRatePercent': 99,
      'sampleCount': 60,
    }), isNull);
    expect(PoseDiagnostics.fromEvent({
      'type': 'diagnostics',
      'processedFps': 15,
      'preprocessMs': 10,
      'inferenceMs': 40,
      'pipelineP95Ms': 80,
      'poseRatePercent': 105,
      'sampleCount': 60,
    }), isNull);
  });
}
