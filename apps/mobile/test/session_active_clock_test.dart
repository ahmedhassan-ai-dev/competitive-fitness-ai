import 'package:competitive_fitness_mobile/features/workouts/session_active_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock starts only when explicitly activated', () {
    var now = Duration.zero;
    final clock = SessionActiveClock(monotonicNow: () => now);
    now += const Duration(seconds: 10);
    expect(clock.elapsed, Duration.zero);
    clock.setActive(true);
    now += const Duration(seconds: 3);
    expect(clock.elapsed, const Duration(seconds: 3));
  });

  test('camera stop and resume do not count inactive time', () {
    var now = Duration.zero;
    final clock = SessionActiveClock(monotonicNow: () => now);
    clock.setActive(true);
    now += const Duration(milliseconds: 1500);
    clock.setActive(false);
    now += const Duration(seconds: 20);
    expect(clock.elapsed, const Duration(milliseconds: 1500));
    clock.setActive(true);
    now += const Duration(milliseconds: 700);
    expect(clock.elapsed, const Duration(milliseconds: 2200));
    clock.setActive(false);
    expect(clock.isActive, isFalse);
  });

  test('repeated activity notifications do not reset elapsed time', () {
    var now = Duration.zero;
    final clock = SessionActiveClock(monotonicNow: () => now);
    clock.setActive(true);
    now += const Duration(seconds: 2);
    clock.setActive(true);
    expect(clock.elapsed, const Duration(seconds: 2));
    clock.setActive(false);
    clock.setActive(false);
    now += const Duration(seconds: 9);
    expect(clock.elapsed, const Duration(seconds: 2));
  });
}
