import 'dart:math' as math;

import '../../models/exercise_type.dart';

/// Coordinates use a common scale for X and Y (provided by the Android bridge).
/// Confidence is the minimum of pose visibility and presence for a joint.
class PosePoint {
  const PosePoint({required this.x, required this.y, required this.confidence});

  final double x;
  final double y;
  final double confidence;
}

/// The additional diagnostics are optional; existing UI callers still use reps
/// and feedback, so FEATURE-001A and FEATURE-001B0 remain source compatible.
class PoseRepUpdate {
  const PoseRepUpdate({
    required this.reps,
    this.feedback,
    this.phase,
    this.jointAngle,
    this.trackedSide,
  });

  final int reps;
  final String? feedback;
  final String? phase;
  final double? jointAngle;
  final String? trackedSide;
}

/// Explicit squat profile; avoids silently treating all variations as identical.
/// This is a counting profile, not an automatic form classifier.
enum SquatStyle {
  standard('Standard'),
  wide('Wide / sumo'),
  narrow('Narrow');

  const SquatStyle(this.label);
  final String label;
}

enum _RepPhase { awaitingTop, ready, atBottom }

class _Reading {
  const _Reading(this.side, this.angle, this.confidence,
      this.hipY, this.ankleY);

  final String side;
  final double angle;
  final double confidence;
  final double? hipY;
  final double? ankleY;
}

/// Counts a complete up -> down -> up cycle, not merely a deep knee/elbow bend.
/// The knee/elbow thresholds are first-pass heuristics; calibrate them using
/// labeled recordings from the target device before claiming production accuracy.
class PoseRepCounter {
  PoseRepCounter(this.exercise, {this.squatStyle = SquatStyle.standard});

  final ExerciseType exercise;
  final SquatStyle squatStyle;

  // A squat knee often does not reach 70 degrees, especially head-on.
  // Push-ups use a different elbow range. Hysteresis is the gap between the
  // top and bottom thresholds, not a per-frame debouncing assumption.
  double get _topAngle => exercise == ExerciseType.squat ? 155 : 150;
  double get _bottomAngle => exercise == ExerciseType.squat ? 115 : 105;
  // Fast push-ups still need an observed top -> bottom -> top sequence.
  // Shortening this gate never fabricates an unseen bottom frame.
  int get _minimumCycleMs => exercise == ExerciseType.squat ? 280 : 140;
  int get _minimumBottomToTopMs => exercise == ExerciseType.squat ? 75 : 40;

  static const double _minimumConfidence = 0.40;
  static const int _maxTrackingGapMs = 850;

  int _reps = 0;
  int? _lastTimestampMs;
  int? _lastValidTimestampMs;
  int? _cycleStartMs;
  int? _bottomMs;
  String? _side;
  double? _filteredAngle;
  double? _standingHipMinusAnkle;
  double? _standingLegSpan;
  double? _standingKneeAngle;
  _RepPhase _phase = _RepPhase.awaitingTop;

  int get reps => _reps;

  PoseRepUpdate process(int timestampMs, Map<String, PosePoint> landmarks) {
    // CameraX can deliver duplicate or out-of-order frames at a lens switch;
    // dropping them must not crash, reset or increment a workout.
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      return _update();
    }
    _lastTimestampMs = timestampMs;

    final reading = _bestReading(landmarks);
    if (reading == null) {
      _expirePartialCycle(timestampMs);
      return _update(
        feedback: 'Keep your joints visible; face the camera or turn slightly.',
        angle: null,
      );
    }

    final previousValidMs = _lastValidTimestampMs;
    if (previousValidMs != null &&
        timestampMs - previousValidMs > _maxTrackingGapMs) {
      _clearPartialCycle();
    }

    if (_side != null && reading.side != _side &&
        _filteredAngle != null &&
        (reading.angle - _filteredAngle!).abs() > 40) {
      // Different sides can disagree due to perspective. Never manufacture a
      // completed rep from a sudden, incompatible side switch.
      _clearPartialCycle();
    }
    final sideChanged = _side != reading.side;
    if (sideChanged && _side != null) {
      // Never compare hip depth across two different camera-projected legs.
      _standingHipMinusAnkle = null;
      _standingLegSpan = null;
      _standingKneeAngle = null;
    }
    _side = reading.side;

    final angle = _smooth(
      reading.angle,
      previousValidMs == null ? null : timestampMs - previousValidMs,
      reset: sideChanged || previousValidMs == null ||
          timestampMs - previousValidMs > _maxTrackingGapMs,
      confidence: reading.confidence,
    );
    _lastValidTimestampMs = timestampMs;

    if (_phase == _RepPhase.awaitingTop) {
      if (angle >= _topAngle) {
        _phase = _RepPhase.ready;
        _cycleStartMs = timestampMs;
        _calibrateStanding(reading, angle);
      }
    } else if (_phase == _RepPhase.ready) {
      if (angle >= _topAngle) {
        // Recalibrate at the top when the phone or person shifts slightly.
        _calibrateStanding(reading, angle);
      }
      if (_atBottom(reading, angle)) {
        _phase = _RepPhase.atBottom;
        _bottomMs = timestampMs;
      }
    } else if (_phase == _RepPhase.atBottom && angle >= _topAngle) {
      if (_cycleStartMs != null &&
          _bottomMs != null &&
          timestampMs - _cycleStartMs! >= _minimumCycleMs &&
          timestampMs - _bottomMs! >= _minimumBottomToTopMs) {
        _reps++;
      }
      // A completed (or implausibly quick) cycle returns to the top.
      // Holding that top position never adds extra repetitions.
      _phase = _RepPhase.ready;
      _cycleStartMs = timestampMs;
      _bottomMs = null;
      _calibrateStanding(reading, angle);
    }
    return _update(angle: angle);
  }

  // A squat from the front or in a wide stance can have a large projected
  // knee angle even after a significant hip descent. Use relative hip-ankle
  // displacement as an EXTRA cue, never as a substitute for knee flexion.
  // Standard deep squats still use the original angle gate unchanged.
  bool _atBottom(_Reading reading, double angle) {
    if (angle <= _bottomAngle) return true;
    if (exercise != ExerciseType.squat) return false;
    final legSpan = _standingLegSpan;
    final standingDelta = _standingHipMinusAnkle;
    final topKnee = _standingKneeAngle;
    if (legSpan == null || standingDelta == null || topKnee == null ||
        reading.hipY == null || reading.ankleY == null) {
      return false;
    }
    if (legSpan < 0.12 || topKnee - angle < 25) return false;
    final descent = ((reading.hipY! - reading.ankleY!) - standingDelta) / legSpan;
    final maxKneeAngle = switch (squatStyle) {
      SquatStyle.standard => 135.0,
      SquatStyle.wide => 145.0,
      SquatStyle.narrow => 138.0,
    };
    final minDescent = switch (squatStyle) {
      SquatStyle.standard => 0.25,
      SquatStyle.wide => 0.20,
      SquatStyle.narrow => 0.22,
    };
    return angle <= maxKneeAngle && descent >= minDescent;
  }

  void _calibrateStanding(_Reading reading, double angle) {
    if (exercise != ExerciseType.squat || reading.hipY == null ||
        reading.ankleY == null) return;
    final span = reading.ankleY! - reading.hipY!;
    if (span < 0.12) return;
    _standingHipMinusAnkle = reading.hipY! - reading.ankleY!;
    _standingLegSpan = span;
    _standingKneeAngle = angle;
  }

  PoseRepUpdate _update({String? feedback, double? angle}) => PoseRepUpdate(
        reps: _reps,
        feedback: feedback,
        phase: switch (_phase) {
          _RepPhase.awaitingTop => 'Find start position',
          _RepPhase.ready => 'Lower down',
          _RepPhase.atBottom => 'Return to top',
        },
        jointAngle: angle,
        trackedSide: _side,
      );

  void _expirePartialCycle(int timestampMs) {
    if (_lastValidTimestampMs != null &&
        timestampMs - _lastValidTimestampMs! > _maxTrackingGapMs) {
      _clearPartialCycle();
    }
  }

  void _clearPartialCycle() {
    _phase = _RepPhase.awaitingTop;
    _cycleStartMs = null;
    _bottomMs = null;
    _filteredAngle = null;
    _standingHipMinusAnkle = null;
    _standingLegSpan = null;
    _standingKneeAngle = null;
  }

  double _smooth(double raw, int? dtMs,
      {required bool reset, required double confidence}) {
    final previous = _filteredAngle;
    if (reset || previous == null || dtMs == null || dtMs <= 0) {
      _filteredAngle = raw;
      return raw;
    }
    // Adaptive EMA: preserve rapid motion (short time constant), suppress
    // small frame-to-frame jitter while the user is holding a pose.
    final movement = (raw - previous).abs();
    // A high-confidence, large motion can be visible for only one frame.
    // Filtering that frame too heavily erases the bottom phase of fast reps.
    // Keep smoothing during small or uncertain changes.
    final tauMs = movement >= 25 && confidence >= 0.65
        ? 0.0
        : movement >= 15 ? 18.0 : 85.0;
    final alpha = (dtMs / (dtMs + tauMs)).clamp(0.0, 1.0).toDouble();
    final filtered = previous + alpha * (raw - previous);
    _filteredAngle = filtered;
    return filtered;
  }

  _Reading? _bestReading(Map<String, PosePoint> landmarks) {
    final joints = exercise == ExerciseType.squat
        ? const ['hip', 'knee', 'ankle']
        : const ['shoulder', 'elbow', 'wrist'];
    final candidates = <_Reading>[];
    for (final side in const ['left', 'right']) {
      final points = [for (final joint in joints) landmarks['${side}_$joint']];
      if (points.any((point) => point == null || !_isValid(point))) continue;
      final a = points[0]!;
      final b = points[1]!;
      final c = points[2]!;
      final angle = _angle(a, b, c);
      if (angle == null) continue;
      final confidence = math.min(a.confidence,
          math.min(b.confidence, c.confidence));
      candidates.add(_Reading(
        side, angle, confidence,
        exercise == ExerciseType.squat ? a.y : null,
        exercise == ExerciseType.squat ? c.y : null,
      ));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = candidates.first;
    // Hold the same side while it remains sufficiently reliable. A small
    // confidence fluctuation should not jump between arms/legs mid-rep.
    for (final candidate in candidates) {
      if (candidate.side == _side &&
          candidate.confidence + 0.20 >= selected.confidence) {
        return candidate;
      }
    }
    return selected;
  }

  bool _isValid(PosePoint point) =>
      point.x.isFinite &&
      point.y.isFinite &&
      point.confidence.isFinite &&
      point.x >= 0 &&
      point.x <= 1 &&
      point.y >= 0 &&
      point.y <= 1 &&
      point.confidence >= _minimumConfidence &&
      point.confidence <= 1;

  double? _angle(PosePoint a, PosePoint b, PosePoint c) {
    final abX = a.x - b.x;
    final abY = a.y - b.y;
    final cbX = c.x - b.x;
    final cbY = c.y - b.y;
    final denominator =
        math.sqrt(abX * abX + abY * abY) *
        math.sqrt(cbX * cbX + cbY * cbY);
    if (denominator <= 1e-12) return null;
    final cosine = ((abX * cbX + abY * cbY) / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}
