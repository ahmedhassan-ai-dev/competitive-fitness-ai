import 'dart:math' as math;

import 'pose_rep_counter.dart';

/// Experimental, on-device tracking for two NEW exercises. Does not affect
/// Squat/Push-up's established PoseRepCounter or transmit camera images.
class AdditionalExerciseUpdate {
  const AdditionalExerciseUpdate({required this.reps, required this.holdMs, this.feedback});
  final int reps;
  final int holdMs;
  final String? feedback;
}

abstract class AdditionalExerciseTracker {
  int get reps;
  int get holdMs;
  AdditionalExerciseUpdate process(int timestampMs, Map<String, PosePoint> landmarks);
  void interrupt();
}

// Frame-based classification deliberately requires an observed closed -> open
// -> closed cycle. Missing frames cannot be reconstructed by threshold changes.
class JumpingJackTracker implements AdditionalExerciseTracker {
  int _reps = 0;
  int? _lastMs;
  int? _openedAt;
  int? _lastGoodMs;
  bool _startedClosed = false;
  bool _wasOpen = false;

  @override
  int get reps => _reps;
  @override
  int get holdMs => 0;

  @override
  void interrupt() { _wasOpen = false; _startedClosed = false; _openedAt = null; _lastGoodMs = null; }

  @override
  AdditionalExerciseUpdate process(int timestampMs, Map<String, PosePoint> points) {
    if (_lastMs != null && timestampMs <= _lastMs!) return _result();
    _lastMs = timestampMs;
    if (_lastGoodMs != null && timestampMs - _lastGoodMs! > 750) interrupt();
    const keys = ['left_shoulder', 'right_shoulder', 'left_wrist', 'right_wrist', 'left_ankle', 'right_ankle'];
    final joints = [for (final name in keys) points[name]];
    if (joints.any((p) => p == null || !_valid(p))) {
      return _result('Face the camera; keep both hands and feet visible.');
    }
    _lastGoodMs = timestampMs;
    final ls = joints[0]!; final rs = joints[1]!;
    final lw = joints[2]!; final rw = joints[3]!;
    final la = joints[4]!; final ra = joints[5]!;
    final shoulderWidth = (ls.x - rs.x).abs();
    final bodyHeight = ((ls.y + rs.y) / 2 - (la.y + ra.y) / 2).abs();
    if (shoulderWidth < .055 || bodyHeight < .24) {
      return _result('Step back; keep your full body visible in the frame.');
    }
    final feetWidth = (la.x - ra.x).abs() / shoulderWidth;
    final wristsAbove = lw.y < ls.y - bodyHeight * .10 &&
        rw.y < rs.y - bodyHeight * .10;
    final wristsBelow = lw.y > ls.y + bodyHeight * .18 &&
        rw.y > rs.y + bodyHeight * .18;
    final open = feetWidth > 1.65 && wristsAbove;
    final closed = feetWidth < 1.15 && wristsBelow;
    if (!_startedClosed) {
      if (closed) _startedClosed = true;
    } else if (!_wasOpen && open) {
      _wasOpen = true;
      _openedAt = timestampMs;
    } else if (_wasOpen && closed) {
      // Require genuine movement separation; never count a single-frame impulse.
      if (_openedAt != null && timestampMs - _openedAt! >= 100) _reps++;
      _wasOpen = false;
      _openedAt = null;
    }
    return _result();
  }

  AdditionalExerciseUpdate _result([String? feedback]) =>
      AdditionalExerciseUpdate(reps: _reps, holdMs: 0, feedback: feedback);
}

/// Valid side-on plank time, not elapsed session/camera time. Gaps and pause do
/// not accrue hold credit. The stopwatch accumulates only observed valid spans.
class PlankTracker implements AdditionalExerciseTracker {
  int _holdMs = 0;
  int? _lastMs;
  int? _lastValidMs;
  @override
  int get reps => 0;
  @override
  int get holdMs => _holdMs;

  @override
  void interrupt() { _lastValidMs = null; }

  @override
  AdditionalExerciseUpdate process(int timestampMs, Map<String, PosePoint> points) {
    if (_lastMs != null && timestampMs <= _lastMs!) return _result();
    _lastMs = timestampMs;
    var validPose = false;
    for (final side in ['left', 'right']) {
      final shoulder = points['${side}_shoulder'];
      final hip = points['${side}_hip'];
      final ankle = points['${side}_ankle'];
      final elbow = points['${side}_elbow'];
      if (shoulder == null || hip == null || ankle == null || elbow == null ||
          !_valid(shoulder) || !_valid(hip) || !_valid(ankle) || !_valid(elbow)) continue;
      final span = math.sqrt(math.pow(shoulder.x - ankle.x, 2) +
          math.pow(shoulder.y - ankle.y, 2));
      if (span < .30) continue;
      final angle = _angle(shoulder, hip, ankle);
      if (angle == null) continue;
      final elbowOffset = (shoulder.x - elbow.x).abs();
      final shoulderHip = math.sqrt(math.pow(shoulder.x - hip.x, 2) +
          math.pow(shoulder.y - hip.y, 2));
      final hipAnkle = math.sqrt(math.pow(hip.x - ankle.x, 2) +
          math.pow(hip.y - ankle.y, 2));
      // 2D side view only. Do not award time when alignment cannot be judged.
      if (angle >= 156 && elbowOffset / span <= .22 &&
          shoulderHip / span < .70 && hipAnkle / span < .90) {
        validPose = true;
      }
    }
    if (!validPose) {
      _lastValidMs = null;
      return _result('Turn sideways; keep shoulders, hips and ankles in one line.');
    }
    if (_lastValidMs != null) {
      final delta = timestampMs - _lastValidMs!;
      if (delta > 0 && delta <= 350) _holdMs += delta;
    }
    _lastValidMs = timestampMs;
    return _result();
  }

  AdditionalExerciseUpdate _result([String? feedback]) =>
      AdditionalExerciseUpdate(reps: 0, holdMs: _holdMs, feedback: feedback);
}

bool _valid(PosePoint? p) => p != null && p.x.isFinite && p.y.isFinite &&
    p.confidence.isFinite && p.confidence >= .55 && p.confidence <= 1 &&
    p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1;

double? _angle(PosePoint a, PosePoint b, PosePoint c) {
  final ux = a.x - b.x; final uy = a.y - b.y;
  final vx = c.x - b.x; final vy = c.y - b.y;
  final length = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
  if (length < 1e-8) return null;
  return math.acos(((ux * vx + uy * vy) / length).clamp(-1.0, 1.0)) * 180 / math.pi;
}
