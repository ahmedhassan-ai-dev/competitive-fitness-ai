import 'package:competitive_fitness_mobile/features/home/home_screen.dart';
import 'package:competitive_fitness_mobile/features/challenges/room_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home uses branded navigation without old dynamic app bar text', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('FitArena'), findsOneWidget);
    expect(find.text('Your training hub'), findsNothing);
    expect(find.text('Every rep\nadds up.'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore challenges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore challenges'));
    await tester.pump();
    expect(find.text('Your training hub'), findsNothing);
  });

  testWidgets('a newly created room can render its API snapshot before refresh', (tester) async {
    final room = <String, dynamic>{
      'room_id': '00000000-0000-4000-8000-000000000001',
      'title': 'Weekend Battle',
      'invite_code': 'ABCDE23456',
      'owner_id': '00000000-0000-4000-8000-000000000002',
      'status': 'waiting',
      'members': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(MaterialApp(home: RoomDetailsScreen(
      roomId: room['room_id'] as String, initialRoom: room,
    )));
    expect(find.text('Weekend Battle'), findsOneWidget);
    expect(find.text('ABCDE23456'), findsOneWidget);
    // No server configured in this test: the room should remain visible.
    await tester.pump();
    expect(find.text('Weekend Battle'), findsOneWidget);
    expect(find.text('Could not open room'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
