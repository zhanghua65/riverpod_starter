import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';

void main() {
  final firstNight = DateTime(2026, 10, 17);

  List<AlarmChain> plan({
    ClockTime bed = const ClockTime(1, 30),
    ClockTime wake = const ClockTime(9, 30),
    ClockTime targetBed = const ClockTime(23, 0),
    ClockTime targetWake = const ClockTime(7, 0),
    int maxStepMinutes = 30,
  }) => SteppingPlan.build(
    currentBedtime: bed,
    currentWakeUp: wake,
    targetBedtime: targetBed,
    targetWakeUp: targetWake,
    firstNight: firstNight,
    maxStepMinutes: maxStepMinutes,
  );

  test('steps 30 minutes a night across midnight and ends on the target', () {
    final chains = plan();
    expect(chains, hasLength(5));
    expect(chains.map((c) => c.bedtime), [
      DateTime(2026, 10, 18, 1, 0),
      DateTime(2026, 10, 19, 0, 30),
      DateTime(2026, 10, 20, 0, 0),
      DateTime(2026, 10, 20, 23, 30),
      DateTime(2026, 10, 21, 23, 0),
    ]);
    expect(chains.map((c) => c.wakeUp), [
      DateTime(2026, 10, 18, 9, 0),
      DateTime(2026, 10, 19, 8, 30),
      DateTime(2026, 10, 20, 8, 0),
      DateTime(2026, 10, 21, 7, 30),
      DateTime(2026, 10, 22, 7, 0),
    ]);
  });

  test('wind-down rings 45 minutes before bedtime', () {
    final first = plan().first;
    expect(first.windDown, DateTime(2026, 10, 18, 0, 15));
  });

  test('alarm ids stay unique even when bedtimes cross midnight', () {
    final ids = plan().expand((c) => c.ids).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(plan().map((c) => c.night.day), [17, 18, 19, 20, 21]);
  });

  test('the larger of the two shifts sets the number of nights', () {
    final chains = plan(
      bed: const ClockTime(23, 30),
      wake: const ClockTime(9, 0),
    );
    // Wake-up moves 120 minutes, bedtime only 30.
    expect(chains, hasLength(4));
    expect(chains.map((c) => c.bedtime.minute), [20, 15, 5, 0]);
    expect(chains.last.wakeUp, DateTime(2026, 10, 21, 7, 0));
  });

  test('caps the plan at 7 nights with bigger steps', () {
    final chains = plan(
      bed: const ClockTime(4, 0),
      wake: const ClockTime(12, 0),
    );
    expect(chains, hasLength(7));
    expect(chains.last.bedtime, DateTime(2026, 10, 23, 23, 0));
  });

  test('a schedule already on target is a single night', () {
    final chains = plan(
      bed: const ClockTime(23, 0),
      wake: const ClockTime(7, 0),
    );
    expect(chains, hasLength(1));
    expect(chains.single.bedtime, DateTime(2026, 10, 17, 23, 0));
  });

  test('rejects a bedtime that is not before the wake-up', () {
    expect(() => plan(targetBed: const ClockTime(8, 0)), throwsArgumentError);
  });
}
