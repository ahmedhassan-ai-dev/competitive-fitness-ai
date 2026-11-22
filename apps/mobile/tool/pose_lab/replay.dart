// Run inside apps/mobile: dart run tool/pose_lab/replay.dart \
//   --input /path/frames.jsonl --exercise pushup --output /path/result.json
// Uses the ACTUAL production PoseRepCounter instead of reimplementing the
// Flutter decision logic in Python. Does not open camera or record video.
import 'dart:convert';
import 'dart:io';

import 'package:competitive_fitness_mobile/features/workouts/pose_rep_counter.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';

Future<void> main(List<String> args) async {
  try {
    final opts = <String, String>{};
    for (var i = 0; i < args.length; i += 2) {
      if (i + 1 >= args.length || !args[i].startsWith('--')) {
        throw const FormatException('Expected --input FILE --exercise squat|pushup --output FILE');
      }
      opts[args[i].substring(2)] = args[i + 1];
    }
    final input = opts['input'];
    final output = opts['output'];
    final exerciseName = opts['exercise'];
    if (input == null || output == null || exerciseName == null) {
      throw const FormatException('Missing --input, --exercise or --output');
    }
    final exercise = switch (exerciseName.toLowerCase()) {
      'squat' => ExerciseType.squat,
      'pushup' || 'push_up' || 'push-up' => ExerciseType.pushUp,
      _ => throw FormatException('Unsupported exercise: $exerciseName'),
    };
    final counter = PoseRepCounter(exercise);
    var frames = 0;
    var missing = 0;
    final repTimes = <int>[];
    int? previousTimestamp;
    await for (final line in File(input)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = jsonDecode(line);
      if (event is! Map || event['timestamp_ms'] is! num ||
          event['landmarks'] is! Map) {
        throw FormatException('Invalid frame at line ${frames + 1}');
      }
      final timestamp = (event['timestamp_ms'] as num).toInt();
      if (previousTimestamp != null && timestamp <= previousTimestamp) {
        throw FormatException('Non-monotonic replay timestamp: $timestamp');
      }
      previousTimestamp = timestamp;
      final points = <String, PosePoint>{};
      for (final e in (event['landmarks'] as Map).entries) {
        if (e.key is! String || e.value is! Map) continue;
        final p = e.value as Map;
        if (p['x'] is num && p['y'] is num && p['confidence'] is num) {
          points[e.key as String] = PosePoint(
            x: (p['x'] as num).toDouble(),
            y: (p['y'] as num).toDouble(),
            confidence: (p['confidence'] as num).toDouble(),
          );
        }
      }
      if (points.isEmpty) missing++;
      final before = counter.reps;
      final result = counter.process(timestamp, points);
      if (result.reps > before) repTimes.add(timestamp);
      frames++;
    }
    final report = {
      'exercise': exerciseName,
      'predicted_reps': counter.reps,
      'rep_timestamps_ms': repTimes,
      'frames': frames,
      'frames_without_landmarks': missing,
      'engine': 'production_dart_PoseRepCounter',
    };
    File(output).parent.createSync(recursive: true);
    File(output).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln('Predicted ${counter.reps} $exerciseName reps ($frames frames) -> $output');
  } on Object catch (error) {
    stderr.writeln('Pose replay failed: $error');
    exitCode = 2;
  }
}
