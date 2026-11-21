import 'dart:math' as math;

import 'package:competitive_fitness_mobile/features/workouts/pose_rep_counter.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, PosePoint> frame(
  double angle, {
  ExerciseType exercise = ExerciseType.squat,
  double confidence = 0.95,
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
      'left_${joints[index]}': PosePoint(
        x: coordinates[index][0],
        y: coordinates[index][1],
        confidence: confidence,
      ),
  };
}

void main() {
  for (final exercise in ExerciseType.values) {
    test(
      '${exercise.wireName} counts a deep bend once and rearms above the top threshold',
      () {
        final counter = PoseRepCounter(exercise);
        final angles = [60, 60, 80, 160, 161, 60, 60];

        for (var index = 0; index < angles.length; index++) {
          counter.process(
            index * 100,
            frame(angles[index].toDouble(), exercise: exercise),
          );
          if (index < 5) expect(counter.reps, 1);
        }

        expect(counter.reps, 2);
      },
    );

    test(
      '${exercise.wireName} follows coordinates without a confidence cutoff',
      () {
        final counter = PoseRepCounter(exercise);

        final update = counter.process(
          0,
          frame(60, exercise: exercise, confidence: 0),
        );

        expect(counter.reps, 1);
        expect(update.feedback, isNull);
      },
    );

    test(
      '${exercise.wireName} ignores movement that misses the bottom threshold',
      () {
        final counter = PoseRepCounter(exercise);
        final angles = [175, 120, 80, 120, 160];

        for (var index = 0; index < angles.length; index++) {
          counter.process(
            index * 100,
            frame(angles[index].toDouble(), exercise: exercise),
          );
        }

        expect(counter.reps, 0);
      },
    );
  }

  test(
    'missing poses preserve the count cycle and timestamp order is enforced',
    () {
      final counter = PoseRepCounter(ExerciseType.squat);
      counter.process(0, frame(175));
      final missing = counter.process(200, {});
      expect(missing.feedback, isNotNull);

      expect(() => counter.process(200, frame(175)), throwsStateError);
      counter.process(300, frame(60));
      expect(counter.reps, 1);
      counter.process(400, {});
      counter.process(500, frame(60));
      expect(counter.reps, 1);
      counter.process(600, frame(175));
      counter.process(700, frame(60));
      expect(counter.reps, 2);
    },
  );
}
