import 'package:flutter/material.dart';

import '../../models/exercise_type.dart';
import '../challenges/room_submission_card.dart';
import '../../services/fitness_api.dart';
import '../../shared/ui.dart';
import 'workout_session_screen.dart';

class ExerciseSelectionScreen extends StatelessWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose your exercise')),
    body: PageBody(
      children: [
        const SectionHeading(
          'One movement.\nYour full focus.',
          subtitle: 'Choose a practice workout to get started.',
        ),
        for (final exercise in ExerciseType.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (exercise) {
                      ExerciseType.squat => Icons.accessibility_new,
                      ExerciseType.pushUp => Icons.fitness_center,
                      ExerciseType.jumpingJack => Icons.directions_run,
                      ExerciseType.plank => Icons.timer_outlined,
                    },
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    exercise.label,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(exercise.description),
                  const SizedBox(height: 12),
                  Chip(label: Text(exercise.focus)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => openPage(
                      context,
                      WorkoutPreparationScreen(exercise: exercise),
                    ),
                    child: Text('Choose ${exercise.label}'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class WorkoutPreparationScreen extends StatelessWidget {
  const WorkoutPreparationScreen({super.key, required this.exercise, this.roomId});
  final ExerciseType exercise;
  final String? roomId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Get ready')),
    body: PageBody(
      children: [
        SectionHeading(
          '${exercise.label} practice',
          subtitle: 'Set yourself up for a comfortable session.',
        ),
        InfoCard(
          icon: Icons.accessibility_new,
          title: 'Find your position',
          message: exercise.preparation,
        ),
        const InfoCard(
          icon: Icons.space_bar,
          title: 'Make a little room',
          message: 'Use a clear, stable surface. Move within a comfortable range and stop if you feel pain.',
        ),
        const InfoCard(
          icon: Icons.touch_app_outlined,
          title: 'Camera-based practice',
          message: 'Pose detection runs on this device. Follow the setup illustration for your exercise. Results are estimates, not verified form scores.',
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => WorkoutSessionScreen(exercise: exercise, roomId: roomId),
            ),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start practice'),
        ),
      ],
    ),
  );
}

class WorkoutSummaryScreen extends StatelessWidget {
  const WorkoutSummaryScreen({
    super.key,
    required this.exercise,
    required this.reps,
    required this.elapsed,
    this.holdSeconds = 0,
    this.roomId,
  });
  final ExerciseType exercise;
  final int reps;
  final int holdSeconds;
  final Duration elapsed;
  final String? roomId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Workout summary'),
      automaticallyImplyLeading: false,
    ),
    body: PageBody(
      children: [
        const Icon(Icons.task_alt, size: 72, color: Color(0xFF176448)),
        SectionHeading(
          (exercise.isHold ? holdSeconds > 0 : reps > 0)
              ? 'You showed up.' : 'A start is still a start.',
          subtitle: '${exercise.label} practice complete.',
        ),
        AdaptivePair(
          first: MetricCard(
            value: exercise.isHold ? '$holdSeconds' : '$reps',
            label: exercise.isHold ? 'Valid hold seconds' : 'Detected reps',
          ),
          second: MetricCard(
            value: formatElapsed(elapsed),
            label: 'Active time',
          ),
        ),
        if (roomId != null)
          RoomSubmissionCard(roomId: roomId!, exercise: exercise,
            reps: reps, holdSeconds: holdSeconds, elapsed: elapsed,
            autoSubmit: true)
        else if (FitnessApi.instance.signedIn)
          RoomSubmissionPicker(exercise: exercise, reps: reps,
            holdSeconds: holdSeconds, elapsed: elapsed),
        const InfoCard(
          icon: Icons.info_outline,
          title: 'Practice, captured',
          message: 'Room totals change only after a successful submission. Scores are estimated and unverified.',
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('Back to home'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => WorkoutPreparationScreen(exercise: exercise, roomId: roomId),
            ),
          ),
          child: const Text('Practice again'),
        ),
      ],
    ),
  );
}
