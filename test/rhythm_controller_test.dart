import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/recall_plan.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_settings.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_store.dart';
import 'package:riverpod_starter/app/core/services/schedule/screen_bedtime.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_recall_notifier.dart';
import 'fake_screen_usage.dart';

void main() {
  late FakeAlarmService alarms;
  late FakeScreenUsage screen;
  late FakeRecallNotifier recall;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final yesterday = DateTime(now.year, now.month, now.day - 1);

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
    screen = FakeScreenUsage();
    recall = FakeRecallNotifier();
    container = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(recall),
        screenUsageProvider.overrideWithValue(screen),
      ],
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

  group('recall notices', () {
    test('applying a plan books notices around the last alarm', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(onTarget(tomorrow));

      final lastRing = alarms.alarms.values
          .map((a) => a.dateTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(recall.booked.map((n) => n.id), [
        RecallPlan.warnId,
        RecallPlan.lapseId,
      ]);
      expect(
        recall.booked.last.at,
        lastRing.add(RecallPlan.lapseDelay),
      );
      expect(recall.booked.first.at.isBefore(lastRing), isTrue);
    });

    test('clearing the plan cancels them', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(onTarget(tomorrow));
      await controller().clearPlan();

      expect(recall.booked, isEmpty);
    });

    test('turning them off cancels them', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(onTarget(tomorrow));
      await controller().updateSettings(
        const RhythmSettings(recallEnabled: false),
      );

      expect(recall.booked, isEmpty);

      await controller().updateSettings(const RhythmSettings());
      expect(recall.booked, hasLength(2));
    });

    test('coming back to the front registers again after a while', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(onTarget(tomorrow));
      final calls = recall.replaceCalls;

      // Just synced: nothing to do.
      await controller().refreshAlarms();
      expect(recall.replaceCalls, calls);
    });

    test('resuming without a plan does nothing', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().refreshAlarms();

      expect(recall.replaceCalls, 0);
    });
  });

  test('a restart leaves alarms that are already registered alone', () async {
    await container.read(rhythmControllerProvider.future);
    await controller().applyPlan(onTarget(tomorrow));
    final registered = Map.of(alarms.alarms);
    final calls = alarms.scheduleCalls;

    final restarted = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
      ],
    );
    addTearDown(restarted.dispose);
    await restarted.read(rhythmControllerProvider.future);

    expect(alarms.scheduleCalls, calls);
    expect(alarms.alarms, registered);
  });

  test('the plan survives a restart and is re-registered', () async {
    await container.read(rhythmControllerProvider.future);
    await controller().applyPlan(onTarget(tomorrow));
    alarms.alarms.clear();

    final restarted = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
      ],
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

  group('recording last night from the screen', () {
    // Yesterday 16:00 to today 00:00, so last night's wake-up has always
    // passed whenever the test runs.
    PlanConfig afternoon() => PlanConfig(
      currentBedtime: const ClockTime(16, 0),
      currentWakeUp: const ClockTime(0, 0),
      targetBedtime: const ClockTime(16, 0),
      targetWakeUp: const ClockTime(0, 0),
      firstNight: DateTime(yesterday.year, yesterday.month, yesterday.day - 1),
    );
    DateTime yesterdayAt(int hour, int minute) =>
        DateTime(yesterday.year, yesterday.month, yesterday.day, hour, minute);

    test('a late screen-off is logged and re-plans', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      screen.screenEvents = [
        ScreenEvent(yesterdayAt(15, 0), on: true),
        ScreenEvent(yesterdayAt(17, 30), on: false),
      ];

      final record = await controller().recordFromScreen();

      expect(record!.night, yesterday);
      expect(record.bedtime, yesterdayAt(17, 30));
      expect(record.recovery!.isLate, isTrue);
      final state = container.read(rhythmControllerProvider).value!;
      expect(state.log.single.source, BedtimeSource.screen);
      expect(state.log.single.actualBedtime, yesterdayAt(17, 30));
      expect(state.plan!.currentBedtime, const ClockTime(17, 30));
    });

    test('a night the user already recorded keeps its bedtime', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      await controller().confirmBedtime(yesterday, yesterdayAt(16, 5));
      // Still asleep: no wake-up to add either.
      screen.screenEvents = [ScreenEvent(yesterdayAt(17, 30), on: false)];

      expect(await controller().recordFromScreen(), isNull);
      final state = container.read(rhythmControllerProvider).value!;
      expect(state.log.single.source, BedtimeSource.manual);
    });

    // Today 00:00 to now, enough to count as getting up after 00:10.
    final morningUse = now.hour > 0 || now.minute >= 20;
    DateTime todayAt(int hour, int minute) =>
        DateTime(now.year, now.month, now.day, hour, minute);

    test('the morning screen use is logged as the wake-up', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      screen.screenEvents = [
        ScreenEvent(yesterdayAt(15, 0), on: true),
        ScreenEvent(yesterdayAt(16, 0), on: false),
        ScreenEvent(todayAt(0, 5), on: true),
      ];

      final record = await controller().recordFromScreen();

      expect(record!.bedtime, yesterdayAt(16, 0));
      expect(record.recovery!.isLate, isFalse);
      expect(record.wakeUp, todayAt(0, 5));
      final entry = container.read(rhythmControllerProvider).value!.log.single;
      expect(entry.actualWakeUp, todayAt(0, 5));
    }, skip: !morningUse);

    test('a late night re-planned before the wake-up still gets it', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      screen.screenEvents = [
        ScreenEvent(yesterdayAt(15, 0), on: true),
        ScreenEvent(yesterdayAt(17, 30), on: false),
      ];
      // Late: re-plans from tonight, which drops last night from the plan.
      await controller().recordFromScreen();

      screen.screenEvents = [
        ...screen.screenEvents!,
        ScreenEvent(todayAt(0, 5), on: true),
      ];
      final record = await controller().recordFromScreen();

      expect(record!.wakeUp, todayAt(0, 5));
    }, skip: !morningUse);

    test('a manually recorded night gets its wake-up filled in', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      await controller().confirmBedtime(yesterday, yesterdayAt(16, 5));
      screen.screenEvents = [
        ScreenEvent(yesterdayAt(16, 10), on: false),
        ScreenEvent(todayAt(0, 5), on: true),
      ];

      final record = await controller().recordFromScreen();

      expect(record!.bedtime, isNull);
      expect(record.recovery, isNull);
      expect(record.wakeUp, todayAt(0, 5));
      final entry = container.read(rhythmControllerProvider).value!.log.single;
      expect(entry.source, BedtimeSource.manual);
      expect(entry.actualBedtime, yesterdayAt(16, 5));
      expect(entry.actualWakeUp, todayAt(0, 5));

      // Nothing more to fill in.
      expect(await controller().recordFromScreen(), isNull);
    }, skip: !morningUse);

    test(
      'the user can correct both times and auto-recording keeps them',
      () async {
        await container.read(rhythmControllerProvider.future);
        await controller().applyPlan(afternoon());
        screen.screenEvents = [
          ScreenEvent(yesterdayAt(15, 0), on: true),
          ScreenEvent(yesterdayAt(17, 30), on: false),
        ];
        await controller().recordFromScreen();

        await controller().editEntry(
          yesterday,
          bedtime: const ClockTime(16, 20),
        );
        var entry = container.read(rhythmControllerProvider).value!.log.single;
        expect(entry.actualBedtime, yesterdayAt(16, 20));
        expect(entry.source, BedtimeSource.manual);
        expect(entry.actualWakeUp, isNull);

        await controller().editEntry(yesterday, wakeUp: const ClockTime(7, 10));
        entry = container.read(rhythmControllerProvider).value!.log.single;
        expect(
          entry.actualWakeUp,
          DateTime(now.year, now.month, now.day, 7, 10),
        );
        expect(entry.wakeUpSource, BedtimeSource.manual);

        // Screen data never overwrites what the user entered.
        screen.screenEvents = [
          ScreenEvent(yesterdayAt(18, 0), on: false),
          ScreenEvent(DateTime(now.year, now.month, now.day, 0, 5), on: true),
        ];
        expect(await controller().recordFromScreen(), isNull);
        entry = container.read(rhythmControllerProvider).value!.log.single;
        expect(entry.actualBedtime, yesterdayAt(16, 20));
        expect(
          entry.actualWakeUp,
          DateTime(now.year, now.month, now.day, 7, 10),
        );
      },
    );

    test('a wake-up before the bedtime is refused', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());
      await controller().confirmBedtime(yesterday, yesterdayAt(16, 5));

      // Wake-up 06:00 the next morning; a bedtime of 08:00 (read as after
      // midnight) would come after it.
      await controller().editEntry(yesterday, wakeUp: const ClockTime(6, 0));
      expect(
        controller().editEntry(yesterday, bedtime: const ClockTime(8, 0)),
        throwsArgumentError,
      );
    });

    test('nothing happens without usage access', () async {
      await container.read(rhythmControllerProvider.future);
      await controller().applyPlan(afternoon());

      expect(await controller().recordFromScreen(), isNull);
      expect(container.read(rhythmControllerProvider).value!.log, isEmpty);
    });

    test('nothing happens before last night\'s wake-up', () async {
      await container.read(rhythmControllerProvider.future);
      // Last night's wake-up is today at 23:59, still ahead.
      await controller().applyPlan(
        PlanConfig(
          currentBedtime: const ClockTime(22, 0),
          currentWakeUp: const ClockTime(23, 59),
          targetBedtime: const ClockTime(22, 0),
          targetWakeUp: const ClockTime(23, 59),
          firstNight: yesterday,
        ),
      );
      screen.screenEvents = [ScreenEvent(yesterdayAt(22, 30), on: false)];

      expect(await controller().recordFromScreen(), isNull);
    }, skip: now.hour == 23 && now.minute == 59);
  });
}
