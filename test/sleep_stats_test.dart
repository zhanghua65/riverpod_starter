import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_store.dart';
import 'package:riverpod_starter/app/core/services/schedule/sleep_stats.dart';

SleepLogEntry night(int day, int lateMinutes, {int? sleepMinutes}) {
  final planned = DateTime(2026, 10, day, 23);
  final actual = planned.add(Duration(minutes: lateMinutes));
  final entry = SleepLogEntry(
    night: DateTime(2026, 10, day),
    plannedBedtime: planned,
    actualBedtime: actual,
  );
  return sleepMinutes == null
      ? entry
      : entry.withWakeUp(actual.add(Duration(minutes: sleepMinutes)));
}

void main() {
  test('an empty log has no averages', () {
    final stats = SleepStats.of(const []);
    expect(stats.nights, 0);
    expect(stats.averageSleep, isNull);
    expect(stats.averageLateBy, isNull);
    expect(stats.onTimeRate, 0);
  });

  test('averages use only the nights they apply to', () {
    final stats = SleepStats.of([
      night(12, 0, sleepMinutes: 480),
      night(11, 40, sleepMinutes: 420),
      night(10, -10),
    ]);
    expect(stats.nights, 3);
    expect(stats.sleepNights, 2);
    expect(stats.averageSleep, const Duration(minutes: 450));
    // 0 + 40 - 10 = 30 minutes over 3 nights.
    expect(stats.averageLateBy, const Duration(minutes: 10));
    expect(stats.onTimeNights, 2);
  });

  test('weeks run Monday to Sunday, newest first', () {
    // 2026-10-18 is a Sunday, 10-19 the next Monday.
    final weeks = WeekStats.of([
      night(19, 0, sleepMinutes: 420),
      night(18, 30, sleepMinutes: 480),
      night(12, 0, sleepMinutes: 360),
    ]);
    expect(weeks.map((w) => w.monday), [
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 12),
    ]);
    expect(weeks[0].stats.nights, 1);
    expect(weeks[1].stats.nights, 2);
    expect(weeks[1].stats.averageSleep, const Duration(minutes: 420));
  });
}
