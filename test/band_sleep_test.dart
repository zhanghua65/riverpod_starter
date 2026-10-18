import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/schedule/band_sleep.dart';

void main() {
  // Bed at 23:00 on Oct 10, up at 07:00 on Oct 11.
  final planned = AlarmChain(
    night: DateTime(2026, 10, 10),
    windDown: DateTime(2026, 10, 10, 22, 15),
    bedtime: DateTime(2026, 10, 10, 23),
    wakeUp: DateTime(2026, 10, 11, 7),
  );
  final morning = DateTime(2026, 10, 11, 9);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, day, hour, minute);

  SleepSession? pick(List<SleepSession> sessions, {DateTime? now}) =>
      BandSleep.pick(planned: planned, sessions: sessions, now: now ?? morning);

  test('a single night session is picked', () {
    final sleep = pick([SleepSession(at(10, 23, 40), at(11, 6, 50))])!;
    expect(sleep.start, at(10, 23, 40));
    expect(sleep.end, at(11, 6, 50));
  });

  test('sessions split by a short wake are joined', () {
    final sleep = pick([
      SleepSession(at(11, 3, 20), at(11, 7, 10)),
      SleepSession(at(10, 23, 30), at(11, 2, 50)),
    ])!;
    expect(sleep.start, at(10, 23, 30));
    expect(sleep.end, at(11, 7, 10));
  });

  test('an evening nap before the night is skipped', () {
    final sleep = pick([
      SleepSession(at(10, 20), at(10, 20, 40)),
      SleepSession(at(11, 0, 30), at(11, 7)),
    ])!;
    expect(sleep.start, at(11, 0, 30));
  });

  test('sleep starting after the planned wake-up is not last night', () {
    expect(pick([SleepSession(at(11, 7, 30), at(11, 11))]), isNull);
  });

  test('too short a night is not used', () {
    expect(pick([SleepSession(at(11, 4), at(11, 6, 30))]), isNull);
  });

  test('a session not finished by now is skipped', () {
    expect(
      pick([SleepSession(at(10, 23, 30), at(11, 7))], now: at(11, 6)),
      isNull,
    );
  });

  test('sessions outside the window are ignored', () {
    expect(pick([SleepSession(at(9, 23), at(10, 7))]), isNull);
  });
}
