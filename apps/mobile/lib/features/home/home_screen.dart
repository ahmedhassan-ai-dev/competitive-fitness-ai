import 'package:flutter/material.dart';

import '../../services/fitness_api.dart';
import '../../shared/ui.dart';
import '../../shared/fitarena_brand.dart';
import '../auth/auth_screens.dart';
import '../challenges/challenge_screens.dart';
import '../workouts/workout_screens.dart';

/// One consistent branded header, rather than an AppBar that repeats tab names.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  void _logout() {
    FitnessApi.instance.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = FitnessApi.instance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 20,
        automaticallyImplyLeading: false,
        title: const FitArenaBrandHeader(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Tooltip(
                message: api.signedIn ? 'Signed in' : 'Demo mode',
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(api.signedIn
                    ? (api.username?.isNotEmpty == true
                        ? api.username![0].toUpperCase() : 'U')
                    : 'D',
                    style: TextStyle(fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer)),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: api.signedIn ? 'Log out' : 'Leave demo',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          PageBody(children: [
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(api.signedIn ? 'WELCOME BACK' : 'PRACTICE MODE',
                    style: TextStyle(fontSize: 11, letterSpacing: 2,
                      fontWeight: FontWeight.w800, color: scheme.primary)),
                  const SizedBox(height: 6),
                  Text(api.signedIn ? 'Ready to make progress?' : 'Move at your own pace.',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800)),
                ],
              )),
            ]),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF123B30), Color(0xFF23604B)],
                ),
              ),
              child: Stack(children: [
                Positioned(
                  top: -64, right: -62,
                  child: Container(
                    height: 210, width: 210,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x44D2EF89), width: 23)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.fitness_center_rounded,
                        size: 34, color: Color(0xFFD2EF89)),
                      const SizedBox(height: 18),
                      Text('Every rep\nadds up.',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w900,
                          height: 1.13)),
                      const SizedBox(height: 10),
                      const Text('Track your session. Challenge your friends.\nOwn your progress.',
                        style: TextStyle(color: Color(0xFFE0F0E5), height: 1.5)),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD2EF89),
                          foregroundColor: const Color(0xFF123B30)),
                        onPressed: () => openPage(context, const ExerciseSelectionScreen()),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start workout'),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            Row(children: [
              Expanded(child: _HomeQuickCard(
                icon: Icons.fitness_center_rounded, value: '4',
                label: 'Exercises')),
              const SizedBox(width: 12),
              Expanded(child: _HomeQuickCard(
                icon: Icons.groups_rounded, value: '2–12',
                label: 'Players / room')),
            ]),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.emoji_events_rounded, color: scheme.primary)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Compete with your crew',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(api.signedIn
                        ? 'Join a live room and share your workout results.'
                        : 'Log in to create rooms and compare results.',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                  IconButton(
                    tooltip: 'Explore challenges',
                    onPressed: () => setState(() => _tab = 1),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ]),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _tab = 1),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Explore challenges'),
            ),
          ]),
          const ChallengesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded), label: 'Challenges'),
        ],
      ),
    );
  }
}

class _HomeQuickCard extends StatelessWidget {
  const _HomeQuickCard({required this.icon, required this.value,
    required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    ),
  );
}
