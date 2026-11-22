import 'package:competitive_fitness_mobile/features/auth/auth_screens.dart';
import 'package:competitive_fitness_mobile/features/challenges/room_screens.dart';
import 'package:competitive_fitness_mobile/shared/fitarena_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome uses the FitArena brand instead of the old title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    expect(find.text('FitArena'), findsOneWidget);
    expect(find.text('COMPETITIVE / FITNESS'), findsNothing);
    expect(find.byType(FitArenaMark), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leader gets a trophy only after scoring points', (tester) async {
    final room = <String, dynamic>{
      'room_id': '00000000-0000-4000-8000-000000000001',
      'title': 'Weekend Battle',
      'invite_code': 'ABCD123456',
      'owner_id': '00000000-0000-4000-8000-000000000002',
      'status': 'active',
      'members': <Map<String, dynamic>>[
        {
          'user_id': '00000000-0000-4000-8000-000000000003',
          'display_name': 'Player 1',
          'overall_rank': 1,
          'total_points': 5,
          'exercises': <Map<String, dynamic>>[],
        },
        {
          'user_id': '00000000-0000-4000-8000-000000000004',
          'display_name': 'Player 2',
          'overall_rank': 2,
          'total_points': 3,
          'exercises': <Map<String, dynamic>>[],
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      home: RoomDetailsScreen(roomId: room['room_id'] as String, initialRoom: room),
    ));
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.text('ROOM LEADER · #1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no crown is awarded before the first workout', (tester) async {
    final room = <String, dynamic>{
      'room_id': '00000000-0000-4000-8000-000000000011',
      'title': 'No scores yet',
      'invite_code': 'ABCDE01234',
      'owner_id': '00000000-0000-4000-8000-000000000012',
      'status': 'waiting',
      'members': <Map<String, dynamic>>[
        {
          'user_id': '00000000-0000-4000-8000-000000000013',
          'display_name': 'Player 1',
          'overall_rank': 1,
          'total_points': 0,
          'exercises': <Map<String, dynamic>>[],
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      home: RoomDetailsScreen(roomId: room['room_id'] as String, initialRoom: room),
    ));
    expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
    expect(find.text('ROOM LEADER · #1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
