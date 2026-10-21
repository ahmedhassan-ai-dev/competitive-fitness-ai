import 'package:competitive_fitness_mobile/data/mock_challenges.dart';
import 'package:competitive_fitness_mobile/features/challenges/challenge_screens.dart';
import 'package:competitive_fitness_mobile/features/workouts/workout_session_screen.dart';
import 'package:competitive_fitness_mobile/main.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> press(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enterDemo(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await press(tester, 'Explore demo');
}

void main() {
  testWidgets('welcome, login validation, password visibility and demo entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await press(tester, 'Log in');
    await press(tester, 'Continue to demo');
    expect(
      find.text('Use 3–32 letters, numbers, or underscores.'),
      findsOneWidget,
    );
    expect(find.text('Use 12–128 characters.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'demo_user');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'made-up-password',
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    final submit = find.text('Continue to demo');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Your training hub'), findsOneWidget);
    await tester.tap(find.byTooltip('Leave demo'));
    await tester.pumpAndSettle();
    expect(find.text('Your next rep.\nYour next level.'), findsOneWidget);
  });

  testWidgets('register checks confirmation and enters local demo', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await press(tester, 'Create account');
    await tester.enterText(find.byType(TextFormField).at(0), 'demo_user');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'made-up-password',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'different');
    await press(tester, 'Create demo account');
    expect(find.text('Passwords must match.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'made-up-password',
    );
    await press(tester, 'Create demo account');
    expect(find.text('Your training hub'), findsOneWidget);
  });

  for (final exercise in ExerciseType.values) {
    testWidgets(
      '${exercise.label} journey counts, pauses, summarizes and returns home',
      (tester) async {
        await enterDemo(tester);
        await press(tester, 'Start workout');
        await press(tester, 'Choose ${exercise.label}');
        expect(find.text('${exercise.label} practice'), findsOneWidget);
        await press(tester, 'Start practice');
        expect(find.text('${exercise.label} session'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('00:03'), findsOneWidget);
        await press(tester, 'Add mock rep');
        await press(tester, 'Add mock rep');
        await press(tester, 'Pause');
        expect(find.text('2'), findsOneWidget);
        final elapsed = tester
            .widget<Text>(find.textContaining(RegExp(r'^\d+:\d\d$')))
            .data;
        await tester.pump(const Duration(seconds: 5));
        expect(find.text(elapsed!), findsOneWidget);
        final add = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add mock rep'),
        );
        expect(add.onPressed, isNull);
        await press(tester, 'Resume');
        await press(tester, 'Add mock rep');
        await press(tester, 'Finish workout');
        expect(find.text('Workout summary'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        await press(tester, 'Practice again');
        await press(tester, 'Start practice');
        expect(find.text('0'), findsOneWidget);
        await press(tester, 'Finish workout');
        await press(tester, 'Back to home');
        expect(find.text('Your training hub'), findsOneWidget);
        expect(find.byType(WorkoutSessionScreen), findsNothing);
      },
    );
  }

  testWidgets(
    'system back confirms discard and keeps canceled practice paused',
    (tester) async {
      await enterDemo(tester);
      await press(tester, 'Start workout');
      await press(tester, 'Choose Squat');
      await press(tester, 'Start practice');
      await press(tester, 'Add mock rep');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave this practice?'), findsOneWidget);
      await press(tester, 'Keep practicing');
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await press(tester, 'Leave practice');
      expect(find.text('Choose your exercise'), findsOneWidget);
      expect(find.byType(WorkoutSessionScreen), findsNothing);
    },
  );

  testWidgets('backgrounding pauses timer and reps until explicit resume', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WorkoutSessionScreen(exercise: ExerciseType.squat),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('00:02'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await press(tester, 'Resume');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:03'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('challenge loading, details and sample scores remain read only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ChallengesScreen())),
    );
    expect(find.text('Loading challenges…'), findsOneWidget);
    await tester.pumpAndSettle();
    await press(tester, 'The squat showdown');
    expect(find.text('Challenge details'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('You · accepted reps'), findsOneWidget);
    await press(tester, 'Back to challenges');
    await press(tester, 'Push your limits');
    expect(find.text('Waiting for a rival'), findsOneWidget);
    await press(tester, 'Back to challenges');
    await press(tester, 'Stronger together');
    expect(find.text('A well-earned draw'), findsOneWidget);
  });

  testWidgets('challenge empty/error previews recover through actions', (
    tester,
  ) async {
    await enterDemo(tester);
    await press(tester, 'Explore challenges');
    await press(tester, 'Preview states ▾');
    await press(tester, 'No challenges');
    expect(find.text('A fresh starting line'), findsOneWidget);
    await press(tester, 'Show sample challenges');
    expect(find.text('The squat showdown'), findsOneWidget);
    await press(tester, 'Preview states ▾');
    await press(tester, 'Load error');
    expect(find.text('Could not load challenges'), findsOneWidget);
    await press(tester, 'Try again');
    expect(find.text('The squat showdown'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Make today count.'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320×568 workout and challenge navigation at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await enterDemo(tester);
        await press(tester, 'Start workout');
        await press(tester, 'Choose Push-up');
        await press(tester, 'Start practice');
        await press(tester, 'Add mock rep');
        await press(tester, 'Finish workout');
        await press(tester, 'Back to home');
        await press(tester, 'Explore challenges');
        await press(tester, 'The squat showdown');
        await press(tester, 'Back to challenges');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('registration remains usable with a keyboard on Small_Phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MyApp());
    await press(tester, 'Create account');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    for (final (index, value) in [
      (0, 'demo_user'),
      (1, 'made-up-password'),
      (2, 'made-up-password'),
    ]) {
      final field = find.byType(TextFormField).at(index);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }
    await press(tester, 'Create demo account');
    expect(find.text('Your training hub'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('exercise wire names and mock challenge states match v1', () {
    expect(ExerciseType.values.map((exercise) => exercise.wireName), [
      'squat',
      'push_up',
    ]);
    for (final challenge in mockChallenges) {
      expect(challenge.participants.length, inInclusiveRange(1, 2));
      if (challenge.status == ChallengeStatus.waiting) {
        expect(
          challenge.participants.every((p) => p.acceptedReps == 0),
          isTrue,
        );
      } else {
        expect(challenge.participants.length, 2);
      }
    }
  });
}
