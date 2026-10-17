import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';

void main() {
  late FakeAlarmService alarms;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  PlanConfig onTarget(DateTime firstNight) => PlanConfig(
    currentBedtime: const ClockTime(23, 0),
    currentWakeUp: const ClockTime(7, 0),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: firstNight,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    alarms = FakeAlarmService();
    container = ProviderContainer(
      overrides: [alarmServiceProvider.overrideWithValue(alarms)],
    );
  });

  tearDown(() => container.dispose());

  RhythmController controller() =>
      container.read(rhythmControllerProvider.notifier);

  test('applying a plan registers the upcoming nights', () async {
    await container.read(rhythmControllerProvider.future);
    await controller().applyPlan(onTarget(tomorrow));

    final nights = {
      for (final id in alarms.alarms.keys) AlarmChain.nightOf(id),
    };
    expect(nights, hasLength(RhythmController.horizonNights - 1));
    expect(nights.reduce((a, b) => a.isBefore(b) ? a : b), tomorrow);
  });

  test('the plan survives a restart and is re-registered', () async {
    await container.read(rhythmControllerProvider.future);
    await controller().applyPlan(onTarget(tomorrow));
    alarms.alarms.clear();

    final restarted = ProviderContainer(
      overrides: [alarmServiceProvider.overrideWithValue(alarms)],
    );
    addTearDown(restarted.dispose);
    final state = await restarted.read(rhythmControllerProvider.future);
    expect(state.plan!.firstNight, tomorrow);
    expect(alarms.alarms, isNotEmpty);
  });

  test(
    'a late bedtime postpones the wake-up, books a nap and re-plans',
    () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(onTarget(tomorrow));

      final recovery = await controller().confirmBedtime(
        tomorrow,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1, 1, 30),
      );

      expect(recovery.isLate, isTrue);
      final wake =
          alarms.alarms[AlarmChain.idFor(tomorrow, AlarmStage.wakeUp)]!;
      expect(wake.dateTime.hour, 7);
      expect(wake.dateTime.minute, 30);
      final nap = alarms.alarms[AlarmChain.idFor(tomorrow, AlarmStage.nap)]!;
      expect(nap.dateTime.hour, 13);

      final state = container.read(rhythmControllerProvider).value!;
      expect(state.plan!.currentBedtime, const ClockTime(1, 30));
      expect(state.log.single.lateBy, const Duration(hours: 2, minutes: 30));
      // The next night now steps back from 01:30 instead of jumping to 23:00.
      final next = AlarmChain.idFor(
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1),
        AlarmStage.bedtime,
      );
      expect(alarms.alarms[next]!.dateTime.hour, 1);
      expect(alarms.alarms[next]!.dateTime.minute, 0);
    },
  );

  test('an on-time bedtime is logged without changing the plan', () async {
    await container.read(rhythmControllerProvider.future);
    final plan = onTarget(today);
    await controller().applyPlan(plan);

    final recovery = await controller().confirmBedtime(
      today,
      DateTime(now.year, now.month, now.day, 23, 5),
    );

    expect(recovery.isLate, isFalse);
    final state = container.read(rhythmControllerProvider).value!;
    expect(state.plan!.firstNight, today);
    expect(state.log, hasLength(1));
  });
}
