import 'package:competitive_fitness_mobile/features/workouts/additional_exercise_tracker.dart';
import 'package:competitive_fitness_mobile/features/workouts/pose_rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';

PosePoint point(double x, double y, [double confidence = .95]) =>
    PosePoint(x: x, y: y, confidence: confidence);

Map<String, PosePoint> jumpingJack({required bool open}) => {
  'left_shoulder': point(.43, .33),
  'right_shoulder': point(.57, .33),
  'left_wrist': point(.28, open ? .13 : .65),
  'right_wrist': point(.72, open ? .13 : .65),
  'left_ankle': point(open ? .28 : .47, .90),
  'right_ankle': point(open ? .72 : .53, .90),
};

Map<String, PosePoint> plank({bool valid = true}) => {
  'left_shoulder': point(.20, .48),
  'left_elbow': point(.22, .68),
  'left_hip': point(.48, valid ? .49 : .75),
  'left_ankle': point(.84, .50),
};

void main() {
  test('jumping jack only counts closed-open-closed, never at open', () {
    final tracker = JumpingJackTracker();
    tracker.process(0, jumpingJack(open: false));
    tracker.process(150, jumpingJack(open: true));
    expect(tracker.reps, 0);
    tracker.process(300, jumpingJack(open: false));
    expect(tracker.reps, 1);
    tracker.process(450, jumpingJack(open: false));
    expect(tracker.reps, 1);
  });

  test('missing frames and camera interruption do not fabricate jumping jacks', () {
    final tracker = JumpingJackTracker();
    tracker.process(0, jumpingJack(open: false));
    tracker.process(200, jumpingJack(open: true));
    tracker.interrupt();
    tracker.process(400, jumpingJack(open: false));
    expect(tracker.reps, 0);
    tracker.process(500, jumpingJack(open: true));
    tracker.process(650, jumpingJack(open: false));
    expect(tracker.reps, 1);
    tracker.process(650, jumpingJack(open: true));
    expect(tracker.reps, 1);
  });

  test('plank accumulates only observed valid pose intervals', () {
    final tracker = PlankTracker();
    tracker.process(0, plank());
    tracker.process(150, plank());
    tracker.process(300, plank());
    expect(tracker.holdMs, 300);
    tracker.process(500, plank(valid: false));
    tracker.process(650, plank());
    expect(tracker.holdMs, 300);
    tracker.process(850, plank());
    expect(tracker.holdMs, 500);
    tracker.interrupt();
    tracker.process(1150, plank());
    expect(tracker.holdMs, 500);
  });

  test('plank stops on missing body and large gaps', () {
    final tracker = PlankTracker();
    tracker.process(0, plank());
    tracker.process(200, {});
    tracker.process(500, plank());
    tracker.process(1000, plank());
    expect(tracker.holdMs, 0);
    tracker.process(1200, plank());
    expect(tracker.holdMs, 200);
  });
}
