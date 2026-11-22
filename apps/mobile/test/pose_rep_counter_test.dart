import 'dart:math' as math;

import 'package:competitive_fitness_mobile/features/workouts/pose_rep_counter.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, PosePoint> frame(
  double angle, {
  ExerciseType exercise = ExerciseType.squat,
  double confidence = 0.95,
  String side = 'left',
}) {
  final radians = angle * math.pi / 180;
  final joints = exercise == ExerciseType.squat
      ? ['hip', 'knee', 'ankle']
      : ['shoulder', 'elbow', 'wrist'];
  final coordinates = <List<double>>[
    [0.8, 0.5],
    [0.5, 0.5],
    [0.5 + 0.3 * math.cos(radians), 0.5 + 0.3 * math.sin(radians)],
  ];
  return {
    for (var index = 0; index < joints.length; index++)
      '${side}_${joints[index]}': PosePoint(
        x: coordinates[index][0],
        y: coordinates[index][1],
        confidence: confidence,
      ),
  };
}

void feed(
  PoseRepCounter counter,
  List<int> times,
  List<double> angles, {
  ExerciseType exercise = ExerciseType.squat,
}) {
  expect(times.length, angles.length);
  for (var i = 0; i < times.length; i++) {
    counter.process(times[i], frame(angles[i], exercise: exercise));
  }
}

void main() {
  test('squat counts ONLY on completion of top -> bottom -> top', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    feed(counter, [0, 100, 200, 300], [170, 144, 112, 105]);
    expect(counter.reps, 0, reason: 'Reaching the bottom is not a full rep');
    feed(counter, [400, 500, 600], [125, 154, 170]);
    expect(counter.reps, 1);
  });

  test('push-up uses its own elbow thresholds', () {
    final counter = PoseRepCounter(ExerciseType.pushUp);
    feed(counter, [0, 100, 200, 300, 400, 500],
        [171, 136, 96, 93, 138, 171], exercise: ExerciseType.pushUp);
    expect(counter.reps, 1);
  });

  test('two full squat cycles count twice, not twice at the bottom', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    feed(counter,
        [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100],
        [170, 145, 108, 107, 145, 170, 165, 145, 105, 106, 144, 170]);
    expect(counter.reps, 2);
  });

  test('shallow squat and standing still are not counted', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    feed(counter, [0, 100, 200, 300, 400, 500],
        [171, 145, 134, 140, 163, 169]);
    expect(counter.reps, 0);
    feed(counter, [600, 700, 800], [168, 169, 170]);
    expect(counter.reps, 0);
  });

  test('unreliable joints do not arm or complete a rep', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170));
    final low = counter.process(100, frame(100, confidence: 0.15));
    expect(low.feedback, isNotNull);
    counter.process(200, frame(170));
    expect(counter.reps, 0);
  });

  test('brief occlusion does not discard a confirmed descent', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170));
    counter.process(100, frame(104));
    final lost = counter.process(180, {});
    expect(lost.feedback, isNotNull);
    counter.process(340, frame(168));
    expect(counter.reps, 1);
  });

  test('long occlusion resets a partial movement but not total reps', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170));
    counter.process(100, frame(105));
    counter.process(1200, {});
    counter.process(1350, frame(170));
    expect(counter.reps, 0);
  });

  test('switches to visible side without losing a compatible movement', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170, side: 'left'));
    counter.process(100, frame(106, side: 'left'));
    final changed = counter.process(200, frame(107, side: 'right'));
    expect(changed.trackedSide, 'right');
    counter.process(350, frame(169, side: 'right'));
    expect(counter.reps, 1);
  });

  test('a side-switch angle discontinuity cannot fabricate a rep', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170, side: 'left'));
    counter.process(100, frame(100, side: 'left'));
    counter.process(350, frame(170, side: 'right'));
    expect(counter.reps, 0);
  });

  test('duplicate or out-of-order frames are dropped without throwing', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170));
    counter.process(100, frame(100));
    expect(counter.process(100, frame(170)).reps, 0);
    expect(counter.process(50, frame(170)).reps, 0);
    counter.process(350, frame(170));
    expect(counter.reps, 1);
  });

  test('very fast implausible cycle is not accepted', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    counter.process(0, frame(170));
    counter.process(50, frame(90));
    counter.process(160, frame(170));
    expect(counter.reps, 0);
  });

  test('first frame at the bottom does not immediately count', () {
    final counter = PoseRepCounter(ExerciseType.pushUp);
    counter.process(0, frame(85, exercise: ExerciseType.pushUp));
    counter.process(500, frame(168, exercise: ExerciseType.pushUp));
    expect(counter.reps, 0);
  });

  test('confidence jitter retains the active side', () {
    final counter = PoseRepCounter(ExerciseType.squat);
    final left = frame(170, side: 'left', confidence: 0.75);
    final right = frame(170, side: 'right', confidence: 0.80);
    counter.process(0, {...left, ...right});
    expect(counter.process(100, {
      ...frame(170, side: 'left', confidence: 0.81),
      ...frame(170, side: 'right', confidence: 0.78),
    }).trackedSide, 'right');
  });
  test('fast full push-up can count when each phase was actually observed', () {
    final c = PoseRepCounter(ExerciseType.pushUp);
    feed(c, [0, 65, 165], [171, 90, 171], exercise: ExerciseType.pushUp);
    expect(c.reps, 1);
    feed(c, [210, 270, 380], [166, 92, 170], exercise: ExerciseType.pushUp);
    expect(c.reps, 2);
  });

  test('implausibly fast impulse and jitter cannot count push-up', () {
    final tooFast = PoseRepCounter(ExerciseType.pushUp);
    feed(tooFast, [0, 20, 75], [170, 90, 170], exercise: ExerciseType.pushUp);
    expect(tooFast.reps, 0);
    final partial = PoseRepCounter(ExerciseType.pushUp);
    feed(partial, [0, 80, 160, 270], [170, 140, 128, 168],
        exercise: ExerciseType.pushUp);
    expect(partial.reps, 0);
  });

  test('wide squat supports significant hip drop with higher knee angle', () {
    final wide = PoseRepCounter(ExerciseType.squat, squatStyle: SquatStyle.wide);
    wide.process(0, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    wide.process(200, frontSquat(hipY: .63, kneeX: .57, kneeY: .77));
    wide.process(450, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    expect(wide.reps, 1);
  });

  test('standard profile avoids counting same ambiguous wide-stance bend', () {
    final standard = PoseRepCounter(ExerciseType.squat);
    standard.process(0, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    standard.process(200, frontSquat(hipY: .63, kneeX: .57, kneeY: .77));
    standard.process(450, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    expect(standard.reps, 0);
  });

  test('wide stance without meaningful hip drop cannot create reps', () {
    final wide = PoseRepCounter(ExerciseType.squat, squatStyle: SquatStyle.wide);
    wide.process(0, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    wide.process(160, frontSquat(hipY: .42, kneeX: .62, kneeY: .70));
    wide.process(400, frontSquat(hipY: .42, kneeX: .50, kneeY: .67));
    expect(wide.reps, 0);
  });
}

Map<String, PosePoint> frontSquat({
  required double hipY,
  required double kneeX,
  required double kneeY,
}) => {
  'left_hip': PosePoint(x: .45, y: hipY, confidence: .95),
  'left_knee': PosePoint(x: kneeX, y: kneeY, confidence: .95),
  'left_ankle': const PosePoint(x: .58, y: .94, confidence: .95),
};

// Added by FEATURE-001B3: guard against regressions in rapid cadence and
// frontal squat movement. Synthetic poses are NOT a real-world accuracy score.
