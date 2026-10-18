import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_stage.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/core/services/schedule/rhythm_store.dart';

class RhythmState {
  const RhythmState({
    this.plan,
    this.log = const [],
    this.settings = const RhythmSettings(),
  });

  final PlanConfig? plan;

  /// Newest first.
  final List<SleepLogEntry> log;

  final RhythmSettings settings;
}

final rhythmStoreProvider = FutureProvider<RhythmStore>(
  (ref) async => RhythmStore(await SharedPreferences.getInstance()),
);

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
      RhythmState(plan: plan, log: log, settings: _store.loadSettings());

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

  Future<void> clearPlan() async {
    await _store.savePlan(null);
    await ref.read(alarmServiceProvider).stopAll();
    state = AsyncData(_stateOf(null, _store.loadLog()));
  }

  /// Records that the user went to bed on [night] at [at] and, if that was
  /// late, postpones the wake-up, books a nap capsule and re-plans.
  Future<Recovery> confirmBedtime(DateTime night, DateTime at) async {
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
      ),
    );

    final recovery = Recovery.after(
      planned: planned,
      actualBedtime: at,
      config: plan,
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
