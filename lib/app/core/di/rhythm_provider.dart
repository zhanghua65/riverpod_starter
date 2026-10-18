import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/ai/rhythm_advisor.dart';
import '/app/core/services/alarm/alarm_stage.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/screen_bedtime.dart';
import '/app/core/services/usage/screen_usage.dart';
import '/app/core/services/schedule/work_schedule.dart';

class RhythmState {
  const RhythmState({
    this.plan,
    this.log = const [],
    this.settings = const RhythmSettings(),
    this.work,
  });

  final PlanConfig? plan;

  /// Newest first.
  final List<SleepLogEntry> log;

  final RhythmSettings settings;

  /// Null until the user enters a work schedule.
  final WorkSchedule? work;
}

final rhythmStoreProvider = FutureProvider<RhythmStore>(
  (ref) async => RhythmStore(await SharedPreferences.getInstance()),
);

final screenUsageProvider = Provider<ScreenUsage>((ref) => ScreenUsage());

/// A bedtime recorded from the screen-off time, and what it changed.
class ScreenRecord {
  const ScreenRecord({
    required this.night,
    required this.bedtime,
    required this.recovery,
  });

  final DateTime night;
  final DateTime bedtime;
  final Recovery recovery;
}

final rhythmControllerProvider =
    AsyncNotifierProvider<RhythmController, RhythmState>(RhythmController.new);

/// Owns the saved plan and keeps the registered alarms in step with it.
class RhythmController extends AsyncNotifier<RhythmState> {
  /// Nights registered ahead. The plugin has no recurring alarms, so the
  /// window is topped up every time the app starts.
  static const horizonNights = 8;

  static const snoozeBedtime = Duration(minutes: 15);

  late RhythmStore _store;

  @override
  Future<RhythmState> build() async {
    _store = await ref.watch(rhythmStoreProvider.future);
    final plan = _store.loadPlan();
    if (plan != null) await _sync(plan);
    return _stateOf(plan, _store.loadLog());
  }

  RhythmState _stateOf(PlanConfig? plan, List<SleepLogEntry> log) =>
      RhythmState(
        plan: plan,
        log: log,
        settings: _store.loadSettings(),
        work: _store.loadWork(),
      );

  /// Saves [plan] and replaces every registered alarm with it.
  Future<bool> applyPlan(PlanConfig plan) async {
    await _store.savePlan(plan);
    await ref.read(alarmServiceProvider).stopAll();
    final ok = await _sync(plan);
    state = AsyncData(_stateOf(plan, _store.loadLog()));
    return ok;
  }

  /// Saves [settings]. A running plan is rebuilt with them and its alarms
  /// are registered again.
  Future<void> updateSettings(RhythmSettings settings) async {
    await _store.saveSettings(settings);
    final plan = (await future).plan;
    if (plan == null) {
      state = AsyncData(_stateOf(null, _store.loadLog()));
      return;
    }
    await applyPlan(plan.withSettings(settings));
  }

  /// Saves [work]; null removes it. Used from the next late night on.
  Future<void> updateWork(WorkSchedule? work) async {
    await _store.saveWork(work);
    final current = await future;
    state = AsyncData(_stateOf(current.plan, current.log));
  }

  /// Applies an accepted weekly review: new settings and, when it proposes
  /// them, new targets reached step by step from tonight.
  Future<void> applyReview(ReviewSuggestion review) async {
    final current = await future;
    final settings = review.applyTo(current.settings);
    await _store.saveSettings(settings);
    final plan = current.plan;
    if (plan == null) {
      state = AsyncData(_stateOf(null, current.log));
      return;
    }
    final now = DateTime.now();
    final bed = review.targetBedtime;
    final wake = review.targetWakeUp;
    final next = bed != null && wake != null
        ? plan.retarget(
            night: DateTime(now.year, now.month, now.day),
            targetBedtime: bed,
            targetWakeUp: wake,
            settings: settings,
          )
        : plan.withSettings(settings);
    await _replace(next, current.log);
  }

  /// Adds the one-off nights of an accepted [adjustment], replacing earlier
  /// ones for the same nights. Past overrides are dropped.
  Future<void> applyAdjustment(TemporaryAdjustment adjustment) async {
    final current = await future;
    final plan = current.plan;
    if (plan == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _replace(
      plan.withOverrides({
        for (final e in plan.overrides.entries)
          if (!e.key.isBefore(today)) e.key: e.value,
        ...adjustment.nights,
      }),
      current.log,
    );
  }

  /// Puts [night] back on the plan.
  Future<void> removeOverride(DateTime night) async {
    final current = await future;
    final plan = current.plan;
    if (plan == null) return;
    await _replace(
      plan.withOverrides({
        for (final e in plan.overrides.entries)
          if (e.key != night) e.key: e.value,
      }),
      current.log,
    );
  }

  /// Saves [plan] and re-registers its nights in place. Unlike [applyPlan]
  /// nothing is stopped first, which keeps this morning's postponed wake-up
  /// and today's nap capsule.
  Future<void> _replace(PlanConfig plan, List<SleepLogEntry> log) async {
    await _store.savePlan(plan);
    await _sync(plan);
    state = AsyncData(_stateOf(plan, log));
  }

  Future<void> clearPlan() async {
    await _store.savePlan(null);
    await ref.read(alarmServiceProvider).stopAll();
    state = AsyncData(_stateOf(null, _store.loadLog()));
  }

  /// Records last night's bedtime from when the screen went off, if the
  /// user has not recorded it, last night's wake-up has passed and usage
  /// access is granted. Null when nothing was recorded.
  ///
  /// By then the wake-up has rung, so a late night still books the nap
  /// capsule and re-plans but no longer postpones the wake-up.
  Future<ScreenRecord?> recordFromScreen() async {
    final current = await future;
    final plan = current.plan;
    if (plan == null) return null;
    final now = DateTime.now();
    final night = DateTime(now.year, now.month, now.day - 1);
    final planned = plan.chainFor(night);
    if (planned == null || now.isBefore(planned.wakeUp)) return null;
    if (current.log.any((e) => e.night == night)) return null;

    final events = await ref
        .read(screenUsageProvider)
        .events(
          ScreenBedtime.windowStart(planned),
          ScreenBedtime.windowEnd(planned),
        );
    if (events == null) return null;
    final at = ScreenBedtime.infer(planned: planned, events: events, now: now);
    if (at == null) return null;
    // Checked again: the user may have recorded it meanwhile.
    if ((await future).log.any((e) => e.night == night)) return null;
    final recovery = await confirmBedtime(
      night,
      at,
      source: BedtimeSource.screen,
    );
    return ScreenRecord(night: night, bedtime: at, recovery: recovery);
  }

  /// Records that the user went to bed on [night] at [at] and, if that was
  /// late, postpones the wake-up, books a nap capsule and re-plans.
  Future<Recovery> confirmBedtime(
    DateTime night,
    DateTime at, {
    BedtimeSource source = BedtimeSource.manual,
  }) async {
    final current = await future;
    final plan = current.plan;
    final planned = plan?.chainFor(night);
    if (plan == null || planned == null) {
      return const Recovery(lateBy: Duration.zero);
    }

    final log = await _store.addLog(
      SleepLogEntry(
        night: planned.night,
        plannedBedtime: planned.bedtime,
        actualBedtime: at,
        source: source,
      ),
    );

    final recovery = Recovery.after(
      planned: planned,
      actualBedtime: at,
      config: plan,
      work: current.work,
    );
    final replan = recovery.replan;
    if (replan == null) {
      state = AsyncData(_stateOf(plan, log));
      return recovery;
    }

    final alarms = ref.read(alarmServiceProvider);
    final now = DateTime.now();
    final wakeUp = recovery.wakeUp;
    if (wakeUp != null && wakeUp.isAfter(now)) {
      await alarms.schedule(
        AlarmChain.settingsAt(planned.night, AlarmStage.wakeUp, wakeUp),
      );
    }
    final napAt = recovery.napAt;
    if (napAt != null && napAt.isAfter(now)) {
      await alarms.schedule(
        AlarmChain.settingsAt(planned.night, AlarmStage.nap, napAt),
      );
    }
    await _store.savePlan(replan);
    await _sync(replan);
    state = AsyncData(_stateOf(replan, log));
    return recovery;
  }

  /// Rings the bedtime alarm of [night] again after [snoozeBedtime].
  Future<void> snooze(DateTime night) => ref
      .read(alarmServiceProvider)
      .schedule(
        AlarmChain.settingsAt(
          night,
          AlarmStage.bedtime,
          DateTime.now().add(snoozeBedtime),
        ),
      );

  /// Starts the nap capsule: rings [Recovery.napLength] from now.
  Future<void> startNap(DateTime night) => ref
      .read(alarmServiceProvider)
      .schedule(
        AlarmChain.settingsAt(
          night,
          AlarmStage.napWake,
          DateTime.now().add(Recovery.napLength),
        ),
      );

  /// Registers the next [horizonNights] of [plan]. Starts from last night so
  /// a wake-up still ahead this morning is kept; past stages are skipped.
  /// Nights before the plan's first night are left alone, which keeps a
  /// wake-up postponed by [confirmBedtime].
  Future<bool> _sync(PlanConfig plan) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - 1);
    final alarms = ref.read(alarmServiceProvider);
    var ok = true;
    for (final chain in plan.chainsFrom(from, horizonNights + 1)) {
      ok = await alarms.scheduleChain(chain) && ok;
    }
    return ok;
  }
}

final onboardingProvider = AsyncNotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

/// Whether the first-use guide has been completed.
class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await ref.watch(rhythmStoreProvider.future)).onboardingDone;

  Future<void> setDone(bool done) async {
    await (await ref.read(rhythmStoreProvider.future)).setOnboardingDone(done);
    state = AsyncData(done);
  }
}

final vendorTipProvider = AsyncNotifierProvider<VendorTipController, bool>(
  VendorTipController.new,
);

/// Whether the user said the phone's background limits are set up.
class VendorTipController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await ref.watch(rhythmStoreProvider.future)).vendorTipDone;

  Future<void> setDone(bool done) async {
    await (await ref.read(rhythmStoreProvider.future)).setVendorTipDone(done);
    state = AsyncData(done);
  }
}
