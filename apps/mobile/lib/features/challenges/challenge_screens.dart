import 'package:flutter/material.dart';

import '../../data/mock_challenges.dart';
import '../../shared/ui.dart';

enum ChallengePreview { samples, empty, error }

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  late Future<List<Challenge>> _challenges;

  @override
  void initState() {
    super.initState();
    _challenges = _load(ChallengePreview.samples);
  }

  Future<List<Challenge>> _load(ChallengePreview preview) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return switch (preview) {
      ChallengePreview.samples => mockChallenges,
      ChallengePreview.empty => const [],
      ChallengePreview.error => throw StateError('Simulated load failure'),
    };
  }

  void _reload(ChallengePreview preview) {
    final next = _load(preview);
    setState(() {
      _challenges = next;
    });
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      const SectionHeading(
        'Better with a rival.',
        subtitle: 'Sample matchups. Find your next motivation.',
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Chip(
            avatar: Icon(Icons.science_outlined, size: 18),
            label: Text('Demo challenges'),
          ),
          PopupMenuButton<ChallengePreview>(
            tooltip: 'Preview list states',
            onSelected: _reload,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: ChallengePreview.samples,
                child: Text('Sample challenges'),
              ),
              PopupMenuItem(
                value: ChallengePreview.empty,
                child: Text('No challenges'),
              ),
              PopupMenuItem(
                value: ChallengePreview.error,
                child: Text('Load error'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Preview states ▾'),
            ),
          ),
        ],
      ),
      FutureBuilder<List<Challenge>>(
        future: _challenges,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Column(
              children: [
                CircularProgressIndicator(semanticsLabel: 'Loading challenges'),
                SizedBox(height: 16),
                Text('Loading challenges…'),
              ],
            );
          }
          if (snapshot.hasError) {
            return StateMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load challenges',
              message: 'This is a simulated error. Try loading the sample list again.',
              action: FilledButton(
                onPressed: () => _reload(ChallengePreview.samples),
                child: const Text('Try again'),
              ),
            );
          }
          final challenges = snapshot.data!;
          if (challenges.isEmpty) {
            return StateMessage(
              icon: Icons.emoji_events_outlined,
              title: 'A fresh starting line',
              message: 'No challenges yet. Explore a sample matchup to see how it works.',
              action: OutlinedButton(
                onPressed: () => _reload(ChallengePreview.samples),
                child: const Text('Show sample challenges'),
              ),
            );
          }
          return Column(
            children: [
              for (final challenge in challenges) ...[
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => openPage(
                      context,
                      ChallengeDetailsScreen(challenge: challenge),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text(challenge.exercise.label)),
                              Chip(label: Text(_statusLabel(challenge.status))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            challenge.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            challenge.participants
                                    .map((p) => p.displayName)
                                    .join(' vs ') +
                                (challenge.status == ChallengeStatus.waiting
                                    ? ' · Waiting for a rival'
                                    : ' · View matchup →'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    ],
  );
}

String _statusLabel(ChallengeStatus status) => switch (status) {
  ChallengeStatus.waiting => 'Waiting',
  ChallengeStatus.active => 'Active',
  ChallengeStatus.completed => 'Completed',
};

class ChallengeDetailsScreen extends StatelessWidget {
  const ChallengeDetailsScreen({super.key, required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Challenge details')),
    body: PageBody(
      children: [
        SectionHeading(
          challenge.title,
          subtitle:
              '${challenge.exercise.label} · ${_statusLabel(challenge.status)} · 1v1',
        ),
        const InfoCard(
          icon: Icons.science_outlined,
          title: 'Sample scoreboard',
          message: 'These are fixed demo scores. Practice reps do not change challenge totals.',
        ),
        for (final participant in challenge.participants)
          MetricCard(
            value: '${participant.acceptedReps}',
            label: '${participant.displayName} · accepted reps',
          ),
        if (challenge.status == ChallengeStatus.waiting)
          const StateMessage(
            icon: Icons.person_add_alt,
            title: 'Waiting for a rival',
            message: 'An opponent has not joined this sample room. Invites and joining will be available after integration.',
          ),
        if (challenge.status == ChallengeStatus.completed)
          StateMessage(
            icon: Icons.handshake_outlined,
            title: _result(),
            message: 'One accepted rep equals one point. Form feedback does not affect points.',
          ),
        if (challenge.status == ChallengeStatus.active)
          const InfoCard(
            icon: Icons.shield_outlined,
            title: 'Every accepted rep counts',
            message: 'The server will validate reps and publish scores. Live updates are not connected in this demo.',
          ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to challenges'),
        ),
      ],
    ),
  );

  String _result() {
    final first = challenge.participants[0];
    final second = challenge.participants[1];
    if (first.acceptedReps == second.acceptedReps) return 'A well-earned draw';
    return '${first.acceptedReps > second.acceptedReps ? first.displayName : second.displayName} wins';
  }
}
