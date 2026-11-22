import 'package:competitive_fitness_mobile/features/workouts/workout_session_screen.dart';
import 'package:competitive_fitness_mobile/models/exercise_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('setup is exercise-specific and camera stays off until start',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.squat),
    ));
    expect(find.text('Begin tracking'), findsOneWidget);
    expect(find.text('Recommended: front or slight diagonal view'), findsOneWidget);
    expect(find.byType(AndroidView), findsNothing);
    expect(find.byKey(const Key('squat-style-standard')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('squat-style-wide')));
    await tester.tap(find.byKey(const Key('squat-style-wide')));
    await tester.pump();
    final choice = tester.widget<ChoiceChip>(find.byKey(const Key('squat-style-wide')));
    expect(choice.selected, isTrue);
    expect(find.byKey(const Key('placement-illustration')), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.pushUp),
    ));
    expect(find.text('Recommended: side or slight diagonal view'), findsOneWidget);
  });

  testWidgets('rear camera guidance, safe controls, and rep UI', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.pushUp),
    ));
    expect(find.text('Push-up session'), findsOneWidget);
    expect(find.text('Begin tracking'), findsOneWidget);
    expect(find.byKey(const Key('placement-illustration')), findsOneWidget);
    await tester.ensureVisible(find.text('Begin tracking'));
    await tester.tap(find.text('Begin tracking'));
    await tester.pump();
    expect(find.text('Back camera'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('REPS'), findsOneWidget);
    expect(
      find.text('Enable camera').evaluate().isNotEmpty ||
          find.text('Requesting permission…').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.textContaining('shoulders, elbows and wrists'), findsOneWidget);
    expect(find.byTooltip('Switch camera'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Switch camera')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics can be toggled without starting camera', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.pushUp),
    ));
    await tester.ensureVisible(find.text('Begin tracking'));
    await tester.tap(find.text('Begin tracking'));
    await tester.pump();
    expect(find.byTooltip('Show diagnostics'), findsOneWidget);
    expect(find.textContaining('Diagnostics: waiting'), findsNothing);
    await tester.tap(find.byTooltip('Show diagnostics'));
    await tester.pump();
    expect(find.textContaining('Diagnostics: waiting'), findsOneWidget);
    expect(find.byTooltip('Hide diagnostics'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide diagnostics'));
    await tester.pump();
    expect(find.textContaining('Diagnostics: waiting'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission denial cannot activate camera switch', (tester) async {
    const permission = MethodChannel('competitive_fitness/camera_permission');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      permission,
      (call) async => false,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(permission, null));

    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.squat),
    ));
    await tester.ensureVisible(find.text('Begin tracking'));
    await tester.tap(find.text('Begin tracking'));
    await tester.pump();
    final enable = find.text('Enable camera');
    await tester.ensureVisible(enable);
    await tester.tap(enable);
    await tester.pump();

    expect(find.text('Camera permission was not granted.'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Switch camera')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px large-text workout remains scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MaterialApp(
      home: WorkoutSessionScreen(exercise: ExerciseType.squat),
    ));
    final begin = find.text('Begin tracking');
    await tester.ensureVisible(begin);
    await tester.tap(begin);
    await tester.pump();
    final finish = find.text('Finish workout');
    await tester.ensureVisible(finish);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.text('Workout summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jumping jack and plank get distinct setup guidance', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: WorkoutSessionScreen(exercise: ExerciseType.jumpingJack),
  ));
  expect(find.text('Recommended: full-body front view'), findsOneWidget);
  await tester.pumpWidget(const MaterialApp(
    home: WorkoutSessionScreen(exercise: ExerciseType.plank),
  ));
  expect(find.text('Recommended: side view at body height'), findsOneWidget);
});
}
