import 'package:flutter/material.dart';

import '../../models/exercise_type.dart';
import '../../services/fitness_api.dart';

/// A room-scoped session was explicitly started from that room, so the summary
/// attempts to submit it immediately. Failure remains visible with a retry.
/// Workouts started from Home use [RoomSubmissionPicker] for an explicit choice.
class RoomSubmissionCard extends StatefulWidget {
  const RoomSubmissionCard({super.key, required this.roomId, required this.exercise,
    required this.reps, required this.holdSeconds, required this.elapsed,
    this.autoSubmit = false, this.onSubmitted, this.showBackButton = true});
  final String roomId;
  final ExerciseType exercise;
  final int reps;
  final int holdSeconds;
  final Duration elapsed;
  final bool autoSubmit;
  final VoidCallback? onSubmitted;
  final bool showBackButton;

  @override
  State<RoomSubmissionCard> createState() => _RoomSubmissionCardState();
}

class _RoomSubmissionCardState extends State<RoomSubmissionCard> {
  String? _workoutId;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoSubmit &&
        (widget.exercise.isHold ? widget.holdSeconds > 0 : widget.reps > 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
  }

  Future<void> _submit() async {
    if (_sending || _sent) return;
    setState(() { _sending = true; _error = null; });
    try {
      final api = FitnessApi.instance;
      // Retry uses the exact same workout ID, so the room API can de-duplicate.
      if (_workoutId == null) {
        final workout = await api.saveWorkout(
          exercise: widget.exercise.wireName,
          reps: widget.reps,
          holdMs: widget.holdSeconds * 1000,
          activeMs: widget.elapsed.inMilliseconds,
        );
        _workoutId = workout['workout_id'] as String;
      }
      await api.submitWorkout(widget.roomId, _workoutId!);
      if (!mounted) return;
      setState(() => _sent = true);
      widget.onSubmitted?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasScore = widget.exercise.isHold
        ? widget.holdSeconds > 0 : widget.reps > 0;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(_sent ? Icons.check_circle_rounded : Icons.emoji_events_outlined,
              color: _sent ? colors.primary : colors.onSurface),
            const SizedBox(width: 10),
            Expanded(child: Text('Friends room result',
              style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 9),
          Text(_sent
            ? 'Added to the room. The leaderboard will refresh with your new total.'
            : _sending
              ? 'Saving your workout and sending it to the room…'
              : !hasScore
                ? 'No completed reps or valid hold time detected. Nothing was sent automatically.'
                : widget.autoSubmit
                  ? 'This session belongs to a room. We will send your score when you finish.'
                  : 'Send the detected score to this room. These are unverified device results.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Submission failed: $_error',
              style: TextStyle(color: colors.error)),
            const Text('Your score has not been confirmed in the room. You can retry.'),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sending || _sent ? null : _submit,
            icon: Icon(_sent ? Icons.check_circle_rounded
              : _sending ? Icons.sync_rounded : Icons.cloud_upload_outlined),
            label: Text(_sent ? 'Submitted to room'
              : _sending ? 'Submitting…'
              : _error != null ? 'Retry room submission' : 'Submit to room'),
          ),
          if (_sent && !widget.showBackButton)
            const Padding(padding: EdgeInsets.only(top: 8),
              child: Text('Open Challenges to see the updated leaderboard.')),
          if (_sent && widget.showBackButton) TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.leaderboard_outlined),
            label: const Text('Back to room leaderboard'),
          ),
        ]),
      ),
    );
  }
}

/// Optional route for workouts started on Home. Sessions are not silently
/// assigned to every room; one active room must be selected by the player.
class RoomSubmissionPicker extends StatefulWidget {
  const RoomSubmissionPicker({super.key, required this.exercise,
    required this.reps, required this.holdSeconds, required this.elapsed});
  final ExerciseType exercise;
  final int reps;
  final int holdSeconds;
  final Duration elapsed;

  @override
  State<RoomSubmissionPicker> createState() => _RoomSubmissionPickerState();
}

class _RoomSubmissionPickerState extends State<RoomSubmissionPicker> {
  late Future<List<Map<String, dynamic>>> _rooms;
  String? _selectedRoom;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _rooms = FitnessApi.instance.listRooms();

  void _retry() {
    setState(() => _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rooms,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Card(child: Padding(padding: EdgeInsets.all(18),
            child: Row(children: [
              SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Checking your active rooms…')),
            ])));
        }
        if (snapshot.hasError) {
          return Card(child: Padding(padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Could not load your rooms.'),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _retry, child: const Text('Retry')),
            ])));
        }
        final rooms = snapshot.data!
          .where((room) => room['status'] == 'active').toList();
        if (rooms.isEmpty) {
          return const Card(child: Padding(padding: EdgeInsets.all(18),
            child: Text('No active friends room. Start a room with your friends to add scores to a leaderboard.')));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Share to a friends room',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('This workout was started from Home. Choose one active room to receive the result.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedRoom,
            decoration: const InputDecoration(
              labelText: 'Active room', prefixIcon: Icon(Icons.groups_outlined)),
            hint: const Text('Choose room'),
            items: [for (final room in rooms)
              DropdownMenuItem<String>(
                value: room['room_id'] as String,
                child: Text(room['title'] as String,
                  overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: _submitted ? null : (roomId) {
              setState(() => _selectedRoom = roomId);
            },
          ),
          if (_selectedRoom != null) ...[
            const SizedBox(height: 12),
            RoomSubmissionCard(
              key: ValueKey(_selectedRoom),
              roomId: _selectedRoom!, exercise: widget.exercise,
              reps: widget.reps, holdSeconds: widget.holdSeconds,
              elapsed: widget.elapsed,
              showBackButton: false,
              onSubmitted: () => setState(() => _submitted = true),
            ),
          ],
        ]);
      },
    );
  }
}
