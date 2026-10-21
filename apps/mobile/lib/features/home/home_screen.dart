import 'package:flutter/material.dart';

import '../../shared/ui.dart';
import '../auth/auth_screens.dart';
import '../challenges/challenge_screens.dart';
import '../workouts/workout_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_tab == 0 ? 'Your training hub' : 'Challenges'),
      actions: [
        IconButton(
          tooltip: 'Leave demo',
          icon: const Icon(Icons.logout),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
              (_) => false,
            );
          },
        ),
      ],
    ),
    body: IndexedStack(
      index: _tab,
      children: [
        PageBody(
          children: [
            const SectionHeading(
              'Make today count.',
              subtitle: 'A little movement. A stronger you.',
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.fitness_center, size: 40),
                  const SizedBox(height: 20),
                  Text(
                    'Show up.\nGet stronger.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pick a movement and try a practice session at your own pace.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        openPage(context, const ExerciseSelectionScreen()),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Start workout'),
                  ),
                ],
              ),
            ),
            const AdaptivePair(
              first: MetricCard(value: '2', label: 'Exercises to explore'),
              second: MetricCard(value: '1v1', label: 'Challenge format'),
            ),
            const InfoCard(
              icon: Icons.history_rounded,
              title: 'Your journey starts here',
              message: 'Complete a practice session to see a workout summary. History is not saved in this demo.',
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _tab = 1),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Explore challenges'),
            ),
          ],
        ),
        const ChallengesScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (value) => setState(() => _tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.emoji_events_outlined),
          selectedIcon: Icon(Icons.emoji_events),
          label: 'Challenges',
        ),
      ],
    ),
  );
}
