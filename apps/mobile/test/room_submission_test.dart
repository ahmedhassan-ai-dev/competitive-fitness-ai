import 'package:competitive_fitness_mobile/features/challenges/room_submission_card.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('room submit does not invent success without a configured server', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: RoomSubmissionCard(roomId: '00000000-0000-4000-8000-000000000001',
        exercise: ExerciseType.pushUp, reps: 8, holdSeconds: 0,
        elapsed: Duration(seconds: 12)),
    ))));
    expect(find.text('Submit to room'), findsOneWidget);
    await tester.tap(find.text('Submit to room'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Server address missing'), findsOneWidget);
    expect(find.text('Submitted to room'), findsNothing);
  });

  testWidgets('room-scoped workout tries upload and reports failure, not false success', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: RoomSubmissionCard(roomId: '00000000-0000-4000-8000-000000000001',
      exercise: ExerciseType.pushUp, reps: 5, holdSeconds: 0,
      elapsed: Duration(seconds: 20), autoSubmit: true),
  ))));
  await tester.pumpAndSettle();
  expect(find.textContaining('Submission failed:'), findsOneWidget);
  expect(find.text('Retry room submission'), findsOneWidget);
  expect(find.text('Submitted to room'), findsNothing);
  });
}
