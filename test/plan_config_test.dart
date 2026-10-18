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

  group('one-off nights', () {
    final withTrain = config.withOverrides({
      DateTime(2026, 10, 21): const NightOverride(
        bedtime: ClockTime(22, 0),
        wakeUp: ClockTime(5, 30),
      ),
    });

    test('replace the plan for that night only', () {
      final chain = withTrain.chainFor(DateTime(2026, 10, 21))!;
      expect(chain.bedtime, DateTime(2026, 10, 21, 22, 0));
      expect(chain.wakeUp, DateTime(2026, 10, 22, 5, 30));
      expect(
        chain.windDown,
        DateTime(2026, 10, 21, 22, 0).subtract(config.settings.windDownLead),
      );
      expect(
        withTrain.chainFor(DateTime(2026, 10, 22))!.bedtime,
        DateTime(2026, 10, 22, 23, 0),
      );
      expect(
        withTrain.plannedChainFor(DateTime(2026, 10, 21))!.bedtime,
        DateTime(2026, 10, 21, 23, 0),
      );
    });

    test('are ignored before the plan starts', () {
      final early = config.withOverrides({
        DateTime(2026, 10, 16): const NightOverride(
          bedtime: ClockTime(22, 0),
          wakeUp: ClockTime(6, 0),
        ),
      });
      expect(early.chainFor(DateTime(2026, 10, 16)), isNull);
    });

    test('survive json, settings changes and re-plans', () {
      final copy = PlanConfig.fromJson(withTrain.toJson());
      expect(copy.overrides, withTrain.overrides);
      expect(withTrain.withSettings(config.settings).overrides, hasLength(1));
      expect(
        withTrain
            .restartFrom(
              night: DateTime(2026, 10, 18),
              bedtime: const ClockTime(1, 0),
              wakeUp: const ClockTime(8, 0),
            )
            .overrides,
        hasLength(1),
      );
    });

    test('older saved plans load without any', () {
      final json = config.toJson()..remove('overrides');
      expect(PlanConfig.fromJson(json).overrides, isEmpty);
    });
  });

  test('retarget restarts from that night toward the new targets', () {
    final next = config.retarget(
      night: DateTime(2026, 10, 17),
      targetBedtime: const ClockTime(22, 30),
      targetWakeUp: const ClockTime(6, 30),
    );
    expect(next.firstNight, DateTime(2026, 10, 17));
    expect(next.currentBedtime, const ClockTime(23, 30));
    expect(next.targetBedtime, const ClockTime(22, 30));
    expect(next.transition.last.bedtime.hour, 22);

    // Before the plan starts nothing but the targets changes.
    final early = config.retarget(
      night: DateTime(2026, 10, 10),
      targetBedtime: const ClockTime(22, 30),
      targetWakeUp: const ClockTime(6, 30),
    );
    expect(early.firstNight, config.firstNight);
    expect(early.currentBedtime, config.currentBedtime);
  });
}
