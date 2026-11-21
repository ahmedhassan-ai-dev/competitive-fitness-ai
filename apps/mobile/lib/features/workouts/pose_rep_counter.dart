import 'dart:math' as math;

import '../../models/exercise_type.dart';

class PosePoint {
  const PosePoint({required this.x, required this.y, required this.confidence});

  final double x;
  final double y;
  final double confidence;
}

class PoseRepUpdate {
  const PoseRepUpdate({required this.reps, this.feedback});

  final int reps;
  final String? feedback;
}

class PoseRepCounter {
  PoseRepCounter(this.exercise);

  final ExerciseType exercise;
  int _reps = 0;
  int? _lastTimestampMs;
  String? _side;
  bool _armed = true;

  int get reps => _reps;

  PoseRepUpdate process(int timestampMs, Map<String, PosePoint> landmarks) {
    final previousTimestamp = _lastTimestampMs;
    if (previousTimestamp != null && timestampMs <= previousTimestamp) {
      throw StateError('Pose timestamps must strictly increase.');
    }
    _lastTimestampMs = timestampMs;

    final joints = _requiredJoints();
    final side = _side ?? _selectSide(landmarks, joints);
    if (side == null) {
      return PoseRepUpdate(
        reps: _reps,
        feedback: 'Show the full side of your body to the camera.',
      );
    }
    _side ??= side;
    final points = [for (final joint in joints) landmarks['${_side}_$joint']];
    if (points.any((point) => point == null || !_inBounds(point))) {
      return PoseRepUpdate(
        reps: _reps,
        feedback:
            'Keep the required joints visible and move into the camera frame.',
      );
    }

    final a = points[0]!;
    final b = points[1]!;
    final c = points[2]!;
    final angle = _angle(a, b, c);
    if (angle == null) {
      return PoseRepUpdate(
        reps: _reps,
        feedback: 'Move so the required joints are clearly separated.',
      );
    }

    if (angle < 70 && _armed) {
      _reps++;
      _armed = false;
      return PoseRepUpdate(reps: _reps);
    }
    if (angle > 160) _armed = true;
    return PoseRepUpdate(reps: _reps);
  }

  List<String> _requiredJoints() => exercise == ExerciseType.squat
      ? const ['hip', 'knee', 'ankle']
      : const ['shoulder', 'elbow', 'wrist'];

  String? _selectSide(Map<String, PosePoint> landmarks, List<String> joints) {
    String? selectedSide;
    var selectedConfidence = -1.0;
    for (final side in const ['left', 'right']) {
      final points = [for (final joint in joints) landmarks['${side}_$joint']];
      if (points.any((point) => point == null || !_inBounds(point))) continue;
      final confidence = points
          .map((point) => point!.confidence)
          .reduce((first, second) => first < second ? first : second);
      if (confidence > selectedConfidence) {
        selectedSide = side;
        selectedConfidence = confidence;
      }
    }
    return selectedSide;
  }

  bool _inBounds(PosePoint point) =>
      point.x.isFinite &&
      point.y.isFinite &&
      point.confidence.isFinite &&
      point.x >= 0 &&
      point.x <= 1 &&
      point.y >= 0 &&
      point.y <= 1 &&
      point.confidence >= 0 &&
      point.confidence <= 1;

  double? _angle(PosePoint a, PosePoint b, PosePoint c) {
    final abX = a.x - b.x;
    final abY = a.y - b.y;
    final cbX = c.x - b.x;
    final cbY = c.y - b.y;
    final denominator =
        math.sqrt(abX * abX + abY * abY) * math.sqrt(cbX * cbX + cbY * cbY);
    if (denominator <= 1e-12) return null;
    final cosine = ((abX * cbX + abY * cbY) / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}
