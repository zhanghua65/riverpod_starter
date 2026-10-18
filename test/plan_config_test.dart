import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';

void main() {
  final config = PlanConfig(
    currentBedtime: const ClockTime(0, 0),
    currentWakeUp: const ClockTime(8, 0),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: DateTime(2026, 10, 17),
  );

  test('nights before the plan have no chain', () {
    expect(config.chainFor(DateTime(2026, 10, 16)), isNull);
  });

  test('transition nights come from the stepping plan', () {
    expect(config.transition, hasLength(2));
    expect(
      config.chainFor(DateTime(2026, 10, 17))!.bedtime,
      DateTime(2026, 10, 17, 23, 30),
    );
  });

  test('after the plan ends every night is on target', () {
    final chains = config.chainsFrom(DateTime(2026, 10, 16), 5);
    expect(chains.map((c) => c.night.day), [17, 18, 19, 20]);
    expect(chains[3].bedtime, DateTime(2026, 10, 20, 23, 0));
    expect(chains[3].wakeUp, DateTime(2026, 10, 21, 7, 0));
  });

  test('round-trips through json', () {
    final copy = PlanConfig.fromJson(config.toJson());
    expect(copy.currentBedtime, config.currentBedtime);
    expect(copy.targetWakeUp, config.targetWakeUp);
    expect(copy.firstNight, config.firstNight);
  });
}
