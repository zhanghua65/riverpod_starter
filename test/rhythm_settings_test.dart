import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/recovery.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_settings.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_recall_notifier.dart';

void main() {
  PlanConfig config(RhythmSettings settings) => PlanConfig(
    currentBedtime: const ClockTime(1, 30),
    currentWakeUp: const ClockTime(9, 30),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: DateTime(2026, 10, 17),
    settings: settings,
  );

  test('settings round-trip through json and fall back when invalid', () {
    const s = RhythmSettings(
      maxStepMinutes: 20,
      maxDays: 10,
      windDownLeadMinutes: 35,
      napTime: ClockTime(14, 30),
    );
    expect(RhythmSettings.fromJson(s.toJson()), s);
    expect(
      RhythmSettings.fromJson({'maxStepMinutes': 500, 'napTime': -1}),
      const RhythmSettings(),
    );
  });

  test('reminders default to on and survive old saved data', () {
    expect(const RhythmSettings().recallEnabled, isTrue);
    expect(RhythmSettings.fromJson(const {}).recallEnabled, isTrue);
    const off = RhythmSettings(recallEnabled: false);
    expect(RhythmSettings.fromJson(off.toJson()).recallEnabled, isFalse);
    expect(RhythmSettings.fromJson({'recallEnabled': 'no'}).recallEnabled, isTrue);
  });

  test('a smaller step needs more nights', () {
    expect(config(const RhythmSettings()).transition, hasLength(5));
    expect(
      config(const RhythmSettings(maxStepMinutes: 20)).transition,
      hasLength(7),
    );
    expect(
      config(const RhythmSettings(maxStepMinutes: 20, maxDays: 10)).transition,
      hasLength(8),
    );
  });

  test('wind-down lead applies to transition and target nights', () {
    final c = config(const RhythmSettings(windDownLeadMinutes: 30));
    final last = c.transition.last;
    expect(last.bedtime.difference(last.windDown), const Duration(minutes: 30));
    final after = c.chainFor(DateTime(2026, 10, 30))!;
    expect(
      after.bedtime.difference(after.windDown),
      const Duration(minutes: 30),
    );
  });

  test('the plan keeps its settings through json and re-planning', () {
    final c = config(const RhythmSettings(napTime: ClockTime(15, 0)));
    expect(PlanConfig.fromJson(c.toJson()).settings, c.settings);
    final again = c.restartFrom(
      night: DateTime(2026, 10, 18),
      bedtime: const ClockTime(0, 30),
      wakeUp: const ClockTime(7, 30),
    );
    expect(again.settings, c.settings);
  });

  test('the nap capsule follows the configured time', () {
    final c = config(const RhythmSettings(napTime: ClockTime(15, 0)));
    final planned = c.chainFor(DateTime(2026, 10, 17))!;
    final recovery = Recovery.after(
      planned: planned,
      actualBedtime: planned.bedtime.add(const Duration(hours: 1)),
      config: c,
    );
    expect(recovery.napAt!.hour, 15);
  });

  test('changing settings rebuilds the running plan and its alarms', () async {
    SharedPreferences.setMockInitialValues({});
    final alarms = FakeAlarmService();
    final container = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(rhythmControllerProvider.notifier);
    await container.read(rhythmControllerProvider.future);

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await notifier.applyPlan(config(const RhythmSettings()).restartFrom(
      night: tomorrow,
      bedtime: const ClockTime(23, 0),
      wakeUp: const ClockTime(7, 0),
    ));

    await notifier.updateSettings(
      const RhythmSettings(windDownLeadMinutes: 30),
    );

    final state = container.read(rhythmControllerProvider).value!;
    expect(state.settings.windDownLeadMinutes, 30);
    expect(state.plan!.settings.windDownLeadMinutes, 30);
    final id = alarms.alarms.keys.firstWhere(
      (id) => AlarmChain.stageOf(id) == AlarmStage.windDown,
    );
    final night = AlarmChain.nightOf(id);
    final bedtime = alarms.alarms[AlarmChain.idFor(night, AlarmStage.bedtime)]!;
    expect(
      bedtime.dateTime.difference(alarms.alarms[id]!.dateTime),
      const Duration(minutes: 30),
    );
  });

  test('settings can be saved before any plan exists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(FakeAlarmService()),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(rhythmControllerProvider.future);
    await container
        .read(rhythmControllerProvider.notifier)
        .updateSettings(const RhythmSettings(maxDays: 5));
    final state = container.read(rhythmControllerProvider).value!;
    expect(state.plan, isNull);
    expect(state.settings.maxDays, 5);
  });
}
