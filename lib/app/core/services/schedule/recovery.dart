import '/app/core/services/alarm/alarm_chain.dart';
import 'plan_config.dart';
import 'stepping_plan.dart';

/// 弹性容错（Anti-Guilt）: what changes after the user goes to bed late.
class Recovery {
  const Recovery({required this.lateBy, this.wakeUp, this.napAt, this.replan});

  /// How much later than planned the user went to bed (zero when on time).
  final Duration lateBy;

  /// Postponed wake-up for this night, when it moves.
  final DateTime? wakeUp;

  /// When to offer the 20-minute nap capsule the next day.
  final DateTime? napAt;

  /// Plan restarting the next night from where the user actually is.
  final PlanConfig? replan;

  bool get isLate => replan != null;

  /// Going to bed less than this much late counts as on time.
  static const grace = Duration(minutes: 15);

  /// The wake-up moves until the user gets at least this much sleep...
  static const minSleep = Duration(hours: 6);

  /// ...but never more than this past the planned wake-up.
  static const maxWakeDelay = Duration(minutes: 60);

  static const napTime = ClockTime(13, 0);
  static const napLength = Duration(minutes: 20);

  /// Works out the recovery for [planned] when the user actually went to bed
  /// at [actualBedtime].
  ///
  /// - Wake-up: postponed to give [minSleep], capped at [maxWakeDelay].
  /// - Nap capsule: offered at [napTime] on the wake-up day.
  /// - Re-plan: the plan restarts the next night from the actual bedtime and
  ///   wake-up, stepping toward the same targets.
  static Recovery after({
    required AlarmChain planned,
    required DateTime actualBedtime,
    required PlanConfig config,
  }) {
    final lateBy = actualBedtime.difference(planned.bedtime);
    if (lateBy < grace) return Recovery(lateBy: Duration.zero);

    var wakeUp = actualBedtime.add(minSleep);
    final latest = planned.wakeUp.add(maxWakeDelay);
    if (wakeUp.isAfter(latest)) wakeUp = latest;
    if (wakeUp.isBefore(planned.wakeUp)) wakeUp = planned.wakeUp;

    final napAt = DateTime(
      wakeUp.year,
      wakeUp.month,
      wakeUp.day,
      napTime.hour,
      napTime.minute,
    );

    final night = planned.night;
    return Recovery(
      lateBy: lateBy,
      wakeUp: wakeUp == planned.wakeUp ? null : wakeUp,
      napAt: napAt.isAfter(wakeUp) ? napAt : null,
      replan: config.restartFrom(
        night: DateTime(night.year, night.month, night.day + 1),
        bedtime: ClockTime.of(actualBedtime),
        wakeUp: ClockTime.of(wakeUp),
      ),
    );
  }
}
