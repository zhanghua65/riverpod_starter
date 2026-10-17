import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/recovery.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';

void main() {
  final config = PlanConfig(
    currentBedtime: const ClockTime(23, 0),
    currentWakeUp: const ClockTime(7, 0),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: DateTime(2026, 10, 17),
  );
  final planned = AlarmChain(
    night: DateTime(2026, 10, 17),
    windDown: DateTime(2026, 10, 17, 22, 15),
    bedtime: DateTime(2026, 10, 17, 23, 0),
    wakeUp: DateTime(2026, 10, 18, 7, 0),
  );

  Recovery after(DateTime actual) =>
      Recovery.after(planned: planned, actualBedtime: actual, config: config);

  test('within the grace period nothing changes', () {
    final r = after(DateTime(2026, 10, 17, 23, 10));
    expect(r.isLate, isFalse);
    expect(r.wakeUp, isNull);
    expect(r.napAt, isNull);
  });

  test('a little late keeps the wake-up when sleep is still enough', () {
    final r = after(DateTime(2026, 10, 17, 23, 30));
    expect(r.isLate, isTrue);
    expect(r.lateBy, const Duration(minutes: 30));
    expect(r.wakeUp, isNull);
    expect(r.napAt, DateTime(2026, 10, 18, 13, 0));
  });

  test('very late postpones the wake-up by at most an hour', () {
    expect(
      after(DateTime(2026, 10, 18, 1, 30)).wakeUp,
      DateTime(2026, 10, 18, 7, 30),
    );
    expect(
      after(DateTime(2026, 10, 18, 3, 0)).wakeUp,
      DateTime(2026, 10, 18, 8, 0),
    );
  });

  test('re-plans from the actual night toward the same targets', () {
    final replan = after(DateTime(2026, 10, 18, 1, 30)).replan!;
    expect(replan.firstNight, DateTime(2026, 10, 18));
    expect(replan.currentBedtime, const ClockTime(1, 30));
    expect(replan.currentWakeUp, const ClockTime(7, 30));
    expect(replan.targetBedtime, config.targetBedtime);
    // 150 minutes to make up at 30 minutes a night.
    expect(replan.transition, hasLength(5));
    expect(replan.transition.first.bedtime, DateTime(2026, 10, 19, 1, 0));
  });
}
