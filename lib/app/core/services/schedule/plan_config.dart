import '/app/core/services/alarm/alarm_chain.dart';
import 'rhythm_settings.dart';
import 'stepping_plan.dart';

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
  });

  final ClockTime currentBedtime;
  final ClockTime currentWakeUp;
  final ClockTime targetBedtime;
  final ClockTime targetWakeUp;
  final DateTime firstNight;
  final RhythmSettings settings;

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
  AlarmChain? chainFor(DateTime night, {List<AlarmChain>? transition}) {
    final plan = transition ?? this.transition;
    final index = _daysBetween(firstNight, night);
    if (index < 0) return null;
    if (index < plan.length) return plan[index];
    return SteppingPlan.build(
      currentBedtime: targetBedtime,
      currentWakeUp: targetWakeUp,
      targetBedtime: targetBedtime,
      targetWakeUp: targetWakeUp,
      firstNight: night,
      windDownLead: settings.windDownLead,
    ).single;
  }

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
  );

  PlanConfig withSettings(RhythmSettings settings) => PlanConfig(
    currentBedtime: currentBedtime,
    currentWakeUp: currentWakeUp,
    targetBedtime: targetBedtime,
    targetWakeUp: targetWakeUp,
    firstNight: firstNight,
    settings: settings,
  );

  Map<String, Object> toJson() => {
    'currentBedtime': currentBedtime.minutes,
    'currentWakeUp': currentWakeUp.minutes,
    'targetBedtime': targetBedtime.minutes,
    'targetWakeUp': targetWakeUp.minutes,
    'firstNight': firstNight.toIso8601String(),
    'settings': settings.toJson(),
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
  );

  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
