import 'package:flutter/material.dart';

import '../../models/exercise_type.dart';
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
                    exercise == ExerciseType.squat
                        ? Icons.accessibility_new
                        : Icons.fitness_center,
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
  const WorkoutPreparationScreen({super.key, required this.exercise});
  final ExerciseType exercise;

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
          title: 'You control this demo',
          message: 'Tap Add mock rep to simulate a repetition. The camera stays off and form is not assessed.',
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => WorkoutSessionScreen(exercise: exercise),
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
  });
  final ExerciseType exercise;
  final int reps;
  final Duration elapsed;

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
          reps > 0 ? 'You showed up.' : 'A start is still a start.',
          subtitle: '${exercise.label} practice complete.',
        ),
        AdaptivePair(
          first: MetricCard(value: '$reps', label: 'Mock reps'),
          second: MetricCard(
            value: formatElapsed(elapsed),
            label: 'Active time',
          ),
        ),
        const InfoCard(
          icon: Icons.info_outline,
          title: 'Practice, captured',
          message: 'This summary is local and temporary. Mock reps are not validated or submitted as a challenge score. Form assessment is not available.',
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('Back to home'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => WorkoutPreparationScreen(exercise: exercise),
            ),
          ),
          child: const Text('Practice again'),
        ),
      ],
    ),
  );
}
