import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/recovery.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:riverpod_starter/app/core/services/schedule/work_schedule.dart';

void main() {
  const work = WorkSchedule(
    start: ClockTime(8, 30),
    morningMinutes: 70,
    lunchStart: ClockTime(12, 0),
    lunchEnd: ClockTime(13, 30),
  );

  test('the latest wake-up leaves time to get ready and commute', () {
    expect(work.latestWakeUp, const ClockTime(7, 20));
    expect(
      const WorkSchedule(
        start: ClockTime(0, 30),
        morningMinutes: 60,
      ).latestWakeUp,
      const ClockTime(23, 30),
    );
  });

  test('the nap goes after lunch and ends before the break does', () {
    expect(work.napTime, const ClockTime(12, 30));
    // A short break moves the nap up so it still ends in time.
    expect(
      const WorkSchedule(
        lunchStart: ClockTime(12, 0),
        lunchEnd: ClockTime(12, 40),
      ).napTime,
      const ClockTime(12, 15),
    );
    expect(
      const WorkSchedule(
        lunchStart: ClockTime(12, 0),
        lunchEnd: ClockTime(12, 20),
      ).napTime,
      const ClockTime(12, 0),
    );
  });

  test('workdays default to Monday to Friday', () {
    const d = WorkSchedule();
    expect(d.isWorkday(DateTime(2026, 10, 19)), isTrue); // Monday
    expect(d.isWorkday(DateTime(2026, 10, 18)), isFalse); // Sunday
  });

  test('round-trips through json and falls back on bad values', () {
    final custom = work.copyWith(workdays: {1, 3, 6});
    expect(WorkSchedule.fromJson(custom.toJson()), custom);
    expect(
      WorkSchedule.fromJson({
        'start': -5,
        'morningMinutes': 999,
        'workdays': 'x',
      }),
      const WorkSchedule(),
    );
  });

  group('recovery on a workday', () {
    final config = PlanConfig(
      currentBedtime: const ClockTime(23, 0),
      currentWakeUp: const ClockTime(7, 0),
      targetBedtime: const ClockTime(23, 0),
      targetWakeUp: const ClockTime(7, 0),
      firstNight: DateTime(2026, 10, 16),
    );

    AlarmChain night(int day) => AlarmChain(
      night: DateTime(2026, 10, day),
      windDown: DateTime(2026, 10, day, 22, 15),
      bedtime: DateTime(2026, 10, day, 23, 0),
      wakeUp: DateTime(2026, 10, day + 1, 7, 0),
    );

    Recovery after(int day) => Recovery.after(
      planned: night(day),
      actualBedtime: DateTime(2026, 10, day + 1, 1, 30),
      config: config,
      work: work,
    );

    test('the wake-up is postponed no later than work allows', () {
      // Sunday night, Monday morning: 07:30 would be late, 07:20 is not.
      final r = after(18);
      expect(r.wakeUp, DateTime(2026, 10, 19, 7, 20));
      expect(r.napAt, DateTime(2026, 10, 19, 12, 30));
    });

    test('on a day off the usual limits and nap time apply', () {
      // Friday night, Saturday morning.
      final r = after(16);
      expect(r.wakeUp, DateTime(2026, 10, 17, 7, 30));
      expect(r.napAt, DateTime(2026, 10, 17, 13, 0));
    });

    test('a planned wake-up later than work allows is kept', () {
      final r = Recovery.after(
        planned: night(18),
        actualBedtime: DateTime(2026, 10, 19, 1, 30),
        config: config,
        work: work.copyWith(start: const ClockTime(7, 30)),
      );
      expect(r.wakeUp, isNull);
    });
  });
}
