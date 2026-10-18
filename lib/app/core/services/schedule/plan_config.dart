import '/app/core/services/alarm/alarm_chain.dart';
import 'rhythm_settings.dart';
import 'stepping_plan.dart';

/// A one-off bedtime and wake-up for a single night, e.g. an early train.
class NightOverride {
  const NightOverride({required this.bedtime, required this.wakeUp});

  final ClockTime bedtime;
  final ClockTime wakeUp;

  @override
  bool operator ==(Object other) =>
      other is NightOverride &&
      other.bedtime == bedtime &&
      other.wakeUp == wakeUp;

  @override
  int get hashCode => Object.hash(bedtime, wakeUp);
}

/// What the user entered for a stepping plan, plus the night it starts on.
///
/// The alarms themselves are derived from this, so persisting it is enough to
/// rebuild and re-register the schedule at any time.
class PlanConfig {
  const PlanConfig({
    required this.currentBedtime,
    required this.currentWakeUp,
    required this.targetBedtime,
    required this.targetWakeUp,
    required this.firstNight,
    this.settings = const RhythmSettings(),
    this.overrides = const {},
  });

  final ClockTime currentBedtime;
  final ClockTime currentWakeUp;
  final ClockTime targetBedtime;
  final ClockTime targetWakeUp;
  final DateTime firstNight;
  final RhythmSettings settings;

  /// One-off nights keyed by date (midnight). They replace whatever the plan
  /// would have that night and leave the rest of the plan as it is.
  final Map<DateTime, NightOverride> overrides;

  /// One chain per transition night; the last one is on target.
  List<AlarmChain> get transition => SteppingPlan.build(
    currentBedtime: currentBedtime,
    currentWakeUp: currentWakeUp,
    targetBedtime: targetBedtime,
    targetWakeUp: targetWakeUp,
    firstNight: firstNight,
    maxStepMinutes: settings.maxStepMinutes,
    maxDays: settings.maxDays,
    windDownLead: settings.windDownLead,
  );

  /// The chain for [night]: a transition night while the plan runs, the
  /// target schedule after it ends, and null before [firstNight].
  /// From [firstNight] on, an override for [night] wins over the plan.
  AlarmChain? chainFor(DateTime night, {List<AlarmChain>? transition}) {
    final index = _daysBetween(firstNight, night);
    if (index < 0) return null;
    final override = overrides[_dateOnly(night)];
    if (override != null) {
      return _fixedChain(night, override.bedtime, override.wakeUp);
    }
    final plan = transition ?? this.transition;
    if (index < plan.length) return plan[index];
    return _fixedChain(night, targetBedtime, targetWakeUp);
  }

  /// The chain [night] would have without its override.
  AlarmChain? plannedChainFor(DateTime night) =>
      withOverrides(const {}).chainFor(night);

  AlarmChain _fixedChain(DateTime night, ClockTime bed, ClockTime wake) =>
      SteppingPlan.build(
        currentBedtime: bed,
        currentWakeUp: wake,
        targetBedtime: bed,
        targetWakeUp: wake,
        firstNight: _dateOnly(night),
        windDownLead: settings.windDownLead,
      ).single;

  /// Chains for [count] consecutive nights starting at [from], skipping
  /// nights before [firstNight].
  List<AlarmChain> chainsFrom(DateTime from, int count) {
    final plan = transition;
    return [
      for (var i = 0; i < count; i++)
        chainFor(
          DateTime(from.year, from.month, from.day + i),
          transition: plan,
        ),
    ].whereType<AlarmChain>().toList();
  }

  /// A plan that restarts from [bedtime]/[wakeUp] on [night], keeping the
  /// targets. Used to re-plan after a late night.
  PlanConfig restartFrom({
    required DateTime night,
    required ClockTime bedtime,
    required ClockTime wakeUp,
  }) => PlanConfig(
    currentBedtime: bedtime,
    currentWakeUp: wakeUp,
    targetBedtime: targetBedtime,
    targetWakeUp: targetWakeUp,
    firstNight: DateTime(night.year, night.month, night.day),
    settings: settings,
    overrides: overrides,
  );

  /// The same plan heading for new targets, restarting on [night] from the
  /// bedtime and wake-up it had planned for that night.
  PlanConfig retarget({
    required DateTime night,
    required ClockTime targetBedtime,
    required ClockTime targetWakeUp,
    RhythmSettings? settings,
  }) {
    final from = plannedChainFor(night);
    return PlanConfig(
      currentBedtime: from == null
          ? currentBedtime
          : ClockTime.of(from.bedtime),
      currentWakeUp: from == null ? currentWakeUp : ClockTime.of(from.wakeUp),
      targetBedtime: targetBedtime,
      targetWakeUp: targetWakeUp,
      firstNight: from == null ? firstNight : _dateOnly(night),
      settings: settings ?? this.settings,
      overrides: overrides,
    );
  }

  PlanConfig withOverrides(Map<DateTime, NightOverride> overrides) =>
      PlanConfig(
        currentBedtime: currentBedtime,
        currentWakeUp: currentWakeUp,
        targetBedtime: targetBedtime,
        targetWakeUp: targetWakeUp,
        firstNight: firstNight,
        settings: settings,
        overrides: overrides,
      );

  PlanConfig withSettings(RhythmSettings settings) => PlanConfig(
    currentBedtime: currentBedtime,
    currentWakeUp: currentWakeUp,
    targetBedtime: targetBedtime,
    targetWakeUp: targetWakeUp,
    firstNight: firstNight,
    settings: settings,
    overrides: overrides,
  );

  Map<String, Object> toJson() => {
    'currentBedtime': currentBedtime.minutes,
    'currentWakeUp': currentWakeUp.minutes,
    'targetBedtime': targetBedtime.minutes,
    'targetWakeUp': targetWakeUp.minutes,
    'firstNight': firstNight.toIso8601String(),
    'settings': settings.toJson(),
    'overrides': {
      for (final e in overrides.entries)
        _dateKey(e.key): {
          'bedtime': e.value.bedtime.minutes,
          'wakeUp': e.value.wakeUp.minutes,
        },
    },
  };

  factory PlanConfig.fromJson(Map<String, dynamic> json) => PlanConfig(
    currentBedtime: ClockTime.fromMinutes(json['currentBedtime'] as int),
    currentWakeUp: ClockTime.fromMinutes(json['currentWakeUp'] as int),
    targetBedtime: ClockTime.fromMinutes(json['targetBedtime'] as int),
    targetWakeUp: ClockTime.fromMinutes(json['targetWakeUp'] as int),
    firstNight: DateTime.parse(json['firstNight'] as String),
    settings: json['settings'] is Map<String, dynamic>
        ? RhythmSettings.fromJson(json['settings'] as Map<String, dynamic>)
        : const RhythmSettings(),
    overrides: _overridesFromJson(json['overrides']),
  );

  static Map<DateTime, NightOverride> _overridesFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const {};
    final result = <DateTime, NightOverride>{};
    for (final e in json.entries) {
      final night = DateTime.tryParse(e.key);
      final v = e.value;
      if (night == null || v is! Map<String, dynamic>) continue;
      final bed = v['bedtime'];
      final wake = v['wakeUp'];
      if (bed is! int || wake is! int) continue;
      result[_dateOnly(night)] = NightOverride(
        bedtime: ClockTime.fromMinutes(bed),
        wakeUp: ClockTime.fromMinutes(wake),
      );
    }
    return result;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
