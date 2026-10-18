import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/ai/rhythm_advisor.dart';
import '/app/core/services/alarm/alarm_stage.dart';
import '/app/core/services/schedule/band_sleep.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/core/services/schedule/screen_bedtime.dart';
import '/app/core/services/usage/health_sleep.dart';
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

final healthSleepProvider = Provider<HealthSleep>((ref) => HealthSleep());

/// What was recorded for a night from the band's sleep or the screen's
/// on/off history.
class ScreenRecord {
  const ScreenRecord({
    required this.night,
    this.bedtime,
    this.recovery,
    this.wakeUp,
    this.fromBand = false,
  });

  final DateTime night;

  /// Bedtime taken from the band or the screen-off time; null when it was
  /// recorded already.
  final DateTime? bedtime;

  /// What recording [bedtime] changed; null with it.
  final Recovery? recovery;

  /// When the user got up, from the band or the first long screen use in
  /// the morning.
  final DateTime? wakeUp;

  /// True when the times came from the band's sleep in Health Connect.
  final bool fromBand;
}

final rhythmControllerProvider =
    AsyncNotifierProvider<RhythmController, RhythmState>(RhythmController.new);

/// Owns the saved plan and keeps the registered alarms in step with it.
class RhythmController extends AsyncNotifier<RhythmState> {
  /// Nights registered ahead. The plugin has no recurring alarms, so the
  /// window is topped up every time the app starts.
  static const horizonNights = 8;

  static const snoozeBedtime = Duration(minutes: 15);

  /// Throttled screen checks (app resumes) run at most this often: reading
  /// usage stats walks every app event of the night.
  static const screenCheckGap = Duration(minutes: 10);

  DateTime? _lastScreenCheck;

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

  /// Fills in last night once its wake-up has passed. The band's sleep in
  /// Health Connect comes first: it fills in or replaces times taken from
  /// the screen, but never ones the user entered. Without band data, falls
  /// back to the screen's on/off history (needs usage access): the bedtime
  /// from when the screen went off, if the user has not recorded it, and
  /// the wake-up from the first [ScreenBedtime.wakeUse] of screen use in
  /// the morning. Null when nothing new was recorded.
  ///
  /// By then the wake-up has rung, so a late night still books the nap
  /// capsule and re-plans but no longer postpones the wake-up. Band times
  /// that replace screen times only change the record: the screen-off
  /// bedtime already re-planned.
  Future<ScreenRecord?> recordFromScreen({bool throttled = false}) async {
    final now = DateTime.now();
    final last = _lastScreenCheck;
    if (throttled && last != null && now.difference(last) < screenCheckGap) {
      return null;
    }
    _lastScreenCheck = now;
    final current = await future;
    final plan = current.plan;
    if (plan == null) return null;
    final night = DateTime(now.year, now.month, now.day - 1);
    final logged = _entryFor(current.log, night);
    final planned = _plannedChain(plan, night, logged);
    if (planned == null || now.isBefore(planned.wakeUp)) return null;
    if (_bandMayImprove(logged)) {
      final sessions = await ref
          .read(healthSleepProvider)
          .sessions(
            ScreenBedtime.windowStart(planned),
            ScreenBedtime.windowEnd(planned),
          );
      final sleep = sessions == null
          ? null
          : BandSleep.pick(planned: planned, sessions: sessions, now: now);
      if (sleep != null) return _recordFromBand(night, sleep);
    }
    if (logged?.actualWakeUp != null) return null;

    final events = await ref
        .read(screenUsageProvider)
        .events(
          ScreenBedtime.windowStart(planned),
          ScreenBedtime.windowEnd(planned),
        );
    if (events == null) return null;

    // Read again: the user may have recorded the night meanwhile.
    final entry = _entryFor((await future).log, night);
    if (entry?.actualWakeUp != null) return null;
    DateTime? inferred;
    Recovery? recovery;
    var bedtime = entry?.actualBedtime;
    if (bedtime == null) {
      inferred = ScreenBedtime.infer(
        planned: planned,
        events: events,
        now: now,
      );
      if (inferred == null) return null;
      bedtime = inferred;
      recovery = await confirmBedtime(
        night,
        inferred,
        source: BedtimeSource.screen,
      );
    }

    final wakeUp = ScreenBedtime.inferWakeUp(
      planned: planned,
      events: events,
      bedtime: bedtime,
      now: now,
    );
    if (wakeUp != null) {
      final log = await _store.setWakeUp(night, wakeUp);
      state = AsyncData(_stateOf((await future).plan, log));
    }
    if (inferred == null && wakeUp == null) return null;
    return ScreenRecord(
      night: night,
      bedtime: inferred,
      recovery: recovery,
      wakeUp: wakeUp,
    );
  }

  /// What [plan] had for [night]. A late night re-plans from the next night
  /// on, which drops [night] from the plan; then its logged planned bedtime
  /// stands in, with the next night's wind-down lead and sleep length.
  static AlarmChain? _plannedChain(
    PlanConfig plan,
    DateTime night,
    SleepLogEntry? logged,
  ) {
    final chain = plan.chainFor(night);
    if (chain != null || logged == null) return chain;
    final next = plan.chainFor(
      DateTime(night.year, night.month, night.day + 1),
    );
    if (next == null) return null;
    final bed = logged.plannedBedtime;
    return AlarmChain(
      night: night,
      windDown: bed.subtract(next.bedtime.difference(next.windDown)),
      bedtime: bed,
      wakeUp: bed.add(next.wakeUp.difference(next.bedtime)),
    );
  }

  /// True while [entry] has a time the band could fill in or replace: one
  /// missing or taken from the screen.
  static bool _bandMayImprove(SleepLogEntry? entry) =>
      entry == null ||
      entry.source == BedtimeSource.screen ||
      entry.actualWakeUp == null ||
      entry.wakeUpSource == BedtimeSource.screen;

  /// Records [sleep] for [night]. A night with no entry goes through
  /// [confirmBedtime] like any other bedtime; screen times are replaced in
  /// the record only. Null when nothing changed.
  Future<ScreenRecord?> _recordFromBand(
    DateTime night,
    SleepSession sleep,
  ) async {
    var entry = _entryFor((await future).log, night);
    DateTime? bedtime;
    Recovery? recovery;
    if (entry == null) {
      recovery = await confirmBedtime(
        night,
        sleep.start,
        source: BedtimeSource.band,
      );
      bedtime = sleep.start;
    } else if (entry.source == BedtimeSource.screen) {
      bedtime = sleep.start;
    }
    entry = _entryFor((await future).log, night);
    if (entry == null) return null;
    final wakeUp =
        (entry.actualWakeUp == null ||
                entry.wakeUpSource == BedtimeSource.screen) &&
            sleep.end.isAfter(bedtime ?? entry.actualBedtime)
        ? sleep.end
        : null;
    // Recovery set means confirmBedtime already saved the band bedtime.
    final replaceBedtime = recovery == null ? bedtime : null;
    if (replaceBedtime != null || wakeUp != null) {
      final log = await _store.setBandTimes(
        night,
        bedtime: replaceBedtime,
        wakeUp: wakeUp,
      );
      state = AsyncData(_stateOf((await future).plan, log));
    }
    if (bedtime == null && wakeUp == null) return null;
    return ScreenRecord(
      night: night,
      bedtime: bedtime,
      recovery: recovery,
      wakeUp: wakeUp,
      fromBand: true,
    );
  }

  /// Corrects the logged bedtime and/or wake-up of [night] with clock times
  /// the user picked. A bedtime before noon is read as after midnight; the
  /// wake-up is on the morning after [night].
  ///
  /// Only the record changes: alarms and the plan stay as they are, and a
  /// corrected night is never overwritten by [recordFromScreen] again.
  /// Throws [ArgumentError] when the wake-up would not be after the bedtime.
  Future<void> editEntry(
    DateTime night, {
    ClockTime? bedtime,
    ClockTime? wakeUp,
  }) async {
    final entry = _entryFor((await future).log, night);
    if (entry == null) return;
    final bed = bedtime == null ? null : bedtimeOn(night, bedtime);
    final woke = wakeUp == null ? null : wakeUpAfter(night, wakeUp);
    final newBed = bed ?? entry.actualBedtime;
    final newWake = woke ?? entry.actualWakeUp;
    if (newWake != null && !newWake.isAfter(newBed)) {
      throw ArgumentError('wake-up $newWake is not after bedtime $newBed');
    }
    final log = await _store.editLog(night, bedtime: bed, wakeUp: woke);
    state = AsyncData(_stateOf((await future).plan, log));
  }

  static DateTime bedtimeOn(DateTime night, ClockTime t) => DateTime(
    night.year,
    night.month,
    night.day + (t.hour < 12 ? 1 : 0),
    t.hour,
    t.minute,
  );

  static DateTime wakeUpAfter(DateTime night, ClockTime t) =>
      DateTime(night.year, night.month, night.day + 1, t.hour, t.minute);

  static SleepLogEntry? _entryFor(List<SleepLogEntry> log, DateTime night) =>
      log.where((e) => e.night == night).firstOrNull;

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
  Future<bool> _sync(PlanConfig plan) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - 1);
    return ref
        .read(alarmServiceProvider)
        .scheduleChains(plan.chainsFrom(from, horizonNights + 1));
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
