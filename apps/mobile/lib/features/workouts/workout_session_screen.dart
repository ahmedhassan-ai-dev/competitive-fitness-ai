import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exercise_type.dart';
import '../../shared/ui.dart';
import 'workout_screens.dart';

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key, required this.exercise});
  final ExerciseType exercise;

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _reps = 0;
  int _seconds = 0;
  bool _paused = false;
  bool _allowExit = false;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
    } else {
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_paused) _togglePause();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit) return;
    _confirmingExit = true;
    if (!_paused) _togglePause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this practice?'),
        content: const Text(
          'Your mock reps will be discarded. The session is paused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep practicing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave practice'),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (leave == true && mounted) {
      setState(() => _allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _finish() {
    _timer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutSummaryScreen(
          exercise: widget.exercise,
          reps: _reps,
          elapsed: Duration(seconds: _seconds),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _confirmExit();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.exercise.label} session'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _confirmExit,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: PageBody(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Chip(
                avatar: Icon(Icons.science_outlined, size: 18),
                label: Text('Mock workout'),
              ),
              Chip(label: Text(_paused ? 'Paused' : 'In progress')),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF123D30),
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Icon(
                  Icons.accessibility_new,
                  size: 76,
                  color: Color(0xFFD2EF89),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your space to move',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Camera off · Demo mode',
                  style: TextStyle(color: Color(0xFFE0EBE4)),
                ),
              ],
            ),
          ),
          AdaptivePair(
            first: MetricCard(value: '$_reps', label: 'Mock reps'),
            second: MetricCard(
              value: formatElapsed(Duration(seconds: _seconds)),
              label: 'Elapsed time',
            ),
          ),
          const InfoCard(
            icon: Icons.tips_and_updates_outlined,
            title: 'Form feedback',
            message: 'No form assessment yet. Future feedback will appear here during your workout.',
          ),
          FilledButton.icon(
            onPressed: _paused ? null : () => setState(() => _reps++),
            icon: const Icon(Icons.add),
            label: const Text('Add mock rep'),
          ),
          OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            label: Text(_paused ? 'Resume' : 'Pause'),
          ),
          TextButton(onPressed: _finish, child: const Text('Finish workout')),
        ],
      ),
    ),
  );
}
