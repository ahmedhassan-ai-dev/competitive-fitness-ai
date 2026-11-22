import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/exercise_type.dart';
import '../../services/fitness_api.dart';
import '../../shared/ui.dart';
import '../workouts/workout_screens.dart';

/// Multiplayer lobby for signed-in users. Scores refresh every four seconds;
/// no live video/landmarks leave the device.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late Future<List<Map<String, dynamic>>> _rooms;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() { _rooms = FitnessApi.instance.listRooms(); });

  Future<void> _createOrJoin({required bool create}) async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(create ? 'Create a friends room' : 'Join a friends room'),
        content: TextField(
          controller: controller,
          maxLength: create ? 70 : 10,
          autofocus: true,
          textCapitalization: create ? TextCapitalization.sentences : TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: create ? 'Room name' : 'Invite code',
            hintText: create ? 'Weekend fitness battle' : 'ABCD234567',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(create ? 'Create' : 'Join')),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.isEmpty || !mounted) return;
    try {
      final result = create
          ? await FitnessApi.instance.createRoom(input)
          : await FitnessApi.instance.joinRoom(input);
      if (!mounted) return;
      // The create/join response already contains a complete room snapshot.
      // Show it immediately instead of flashing a full-screen error while the
      // first follow-up GET is in flight.
      await openPage(context, RoomDetailsScreen(
        roomId: result['room_id'] as String, initialRoom: result));
      if (mounted) _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
    const SectionHeading('Train together. Climb together.',
      subtitle: 'Create a private room, invite friends and climb the friendly leaderboard.'),
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF153E30), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.groups_rounded, size: 42, color: Color(0xFFD2EF89)),
        const SizedBox(height: 10),
        const Text('Your crew. Your challenge.', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('2–12 players per room · 4 exercises · live refresh', style: TextStyle(color: Color(0xFFD5E8D8))),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () => _createOrJoin(create: true),
          icon: const Icon(Icons.add), label: const Text('Create room')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
          onPressed: () => _createOrJoin(create: false),
          icon: const Icon(Icons.key_outlined), label: const Text('Join with code')),
      ]),
    ),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('My rooms', style: Theme.of(context).textTheme.titleLarge),
      IconButton(tooltip: 'Refresh rooms', onPressed: _reload, icon: const Icon(Icons.refresh)),
    ]),
    FutureBuilder<List<Map<String, dynamic>>>(future: _rooms, builder: (context, snapshot) {
      if (!snapshot.hasData && !snapshot.hasError) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return StateMessage(icon: Icons.wifi_off_rounded, title: 'Could not load rooms',
          message: '${snapshot.error}', action: FilledButton(onPressed: _reload, child: const Text('Retry')));
      }
      if (snapshot.data!.isEmpty) {
        return const StateMessage(icon: Icons.groups_outlined, title: 'No rooms yet',
          message: 'Create a room and share its invite code with your friends.');
      }
      return Column(children: [
        for (final room in snapshot.data!) ...[
          Card(child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            title: Text(room['title'] as String),
            subtitle: Text('${room['member_count']} players · ${room['status']} · ${room['invite_code']}'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            onTap: () async {
              await openPage(context, RoomDetailsScreen(roomId: room['room_id'] as String));
              if (mounted) _reload();
            },
          )),
          const SizedBox(height: 10),
        ],
      ]);
    }),
    const InfoCard(icon: Icons.shield_outlined, title: 'Friendly competition',
      message: 'Results come from phone pose detection. They are unverified and not suitable for prize competitions yet.'),
  ]);
}

class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({super.key, required this.roomId, this.initialRoom});
  final String roomId;
  final Map<String, dynamic>? initialRoom;

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  Timer? _poll;
  Map<String, dynamic>? _room;
  String? _error;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _loading = widget.initialRoom == null;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final data = await FitnessApi.instance.room(widget.roomId);
      if (mounted) setState(() { _room = data; _error = null; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    } finally {
      _busy = false;
    }
  }

  Future<void> _changeStatus({required bool start}) async {
    if (_busy) return;
    _busy = true;
    try {
      final data = start ? await FitnessApi.instance.startRoom(widget.roomId)
          : await FitnessApi.instance.finishRoom(widget.roomId);
      if (mounted) setState(() { _room = data; _error = null; });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(title: const Text('Friends room'), actions: [
        IconButton(tooltip: 'Refresh leaderboard', onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: PageBody(children: [
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null && room == null) StateMessage(
          icon: Icons.wifi_off, title: 'Could not open room',
          message: _error!, action: FilledButton(onPressed: _load, child: const Text('Retry'))),
        if (_error != null && room != null) Card(
          child: Padding(padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('Connection interrupted. Showing the latest available scores.')),
              IconButton(tooltip: 'Retry leaderboard', onPressed: _load,
                icon: const Icon(Icons.refresh_rounded)),
            ]))),
        if (room != null) ...[
          SectionHeading(room['title'] as String, subtitle: 'Status: ${room['status']} · Updates every 4 seconds'),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('INVITE CODE', style: TextStyle(fontSize: 12, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              SelectableText(room['invite_code'] as String,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3)),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () async {
                await Clipboard.setData(ClipboardData(text: room['invite_code'] as String));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied')));
              }, icon: const Icon(Icons.copy), label: const Text('Copy invite code')),
            ]))),
          if (room['owner_id'] == FitnessApi.instance.userId && room['status'] == 'waiting')
            FilledButton.icon(onPressed: () => _changeStatus(start: true),
              icon: const Icon(Icons.play_arrow), label: const Text('Start room (2+ players)')),
          if (room['owner_id'] == FitnessApi.instance.userId && room['status'] == 'active')
            OutlinedButton.icon(onPressed: () => _changeStatus(start: false),
              icon: const Icon(Icons.flag_outlined), label: const Text('Finish competition')),
          if (room['status'] == 'active') ...[
            Text('Submit a workout', style: Theme.of(context).textTheme.titleLarge),
            const Text('Choose an exercise here. When you finish, your detected score is sent to this room automatically, with a retry option if it fails.'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final exercise in ExerciseType.values)
                ActionChip(
                  avatar: Icon(exercise.isHold ? Icons.timer_outlined : Icons.fitness_center_outlined, size: 18),
                  label: Text(exercise.label),
                  onPressed: () async {
                    await openPage(context, WorkoutPreparationScreen(exercise: exercise, roomId: widget.roomId));
                    if (mounted) _load();
                  },
                ),
            ]),
          ],
          Text('Overall standings', style: Theme.of(context).textTheme.titleLarge),
          const Text('Points from exercise placements, not added reps + seconds.'),
          ..._memberCards(context, room),
          const InfoCard(icon: Icons.info_outline, title: 'Unverified friendly scores',
            message: 'Scores are reported by each phone and refreshed after a workout is submitted. No live-video uploads or anti-cheat validation yet.'),
        ],
      ]),
    );
  }

  // An empty room must not crown a player just because their rank defaults to 1.
  bool _isLeader(Map member) =>
      member['overall_rank'] == 1 &&
      (member['total_points'] is num) &&
      (member['total_points'] as num) > 0;

  List<Widget> _memberCards(BuildContext context, Map<String, dynamic> room) {
    final members = (room['members'] as List).cast<Map>();
    return [
      for (final member in members) ...[
        Card(
          color: _isLeader(member) ? const Color(0xFFFFF5DB) : null,
          shape: _isLeader(member)
              ? RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFE6BC55), width: 1.5),
                  borderRadius: BorderRadius.circular(22),
                )
              : null,
          child: Padding(padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: _isLeader(member) ? const Color(0xFFF6CA65) : null,
                foregroundColor: _isLeader(member) ? const Color(0xFF513600) : null,
                child: _isLeader(member)
                    ? const Icon(Icons.emoji_events_rounded, size: 22)
                    : Text('#${member['overall_rank']}'),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member['display_name'] as String,
                  style: Theme.of(context).textTheme.titleMedium),
                if (_isLeader(member))
                  const Text('ROOM LEADER · #1',
                    style: TextStyle(color: Color(0xFF8E5E06),
                      fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.9)),
                Text('${member['total_points']} placement points'),
              ])),
              if (member['user_id'] == FitnessApi.instance.userId) const Chip(label: Text('You')),
            ]),
            const Divider(height: 24),
            ...((member['exercises'] as List).cast<Map>().map((score) {
              final type = ExerciseType.values.where((e) => e.wireName == score['exercise']).first;
              final raw = score['total'] as int;
              final value = type.isHold ? '${(raw / 1000).toStringAsFixed(1)} sec' : '$raw reps';
              return Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(type.label)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(score['rank'] == null ? '–' : '#${score['rank']}'),
                ]));
            })),
          ]))),
          const SizedBox(height: 10),
      ],
    ];
  }
}
