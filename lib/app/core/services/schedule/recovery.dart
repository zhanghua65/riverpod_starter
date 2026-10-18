import '/app/core/services/alarm/alarm_chain.dart';
import 'plan_config.dart';
import 'stepping_plan.dart';
import 'work_schedule.dart';

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

  static const napLength = Duration(minutes: 20);

  /// Works out the recovery for [planned] when the user actually went to bed
  /// at [actualBedtime].
  ///
  /// - Wake-up: postponed to give [minSleep], capped at [maxWakeDelay] and,
  ///   on a workday of [work], at the latest wake-up that is still on time.
  /// - Nap capsule: offered at the configured nap time on the wake-up day,
  ///   or in the lunch break on a workday.
  /// - Re-plan: the plan restarts the next night from the actual bedtime and
  ///   wake-up, stepping toward the same targets.
  static Recovery after({
    required AlarmChain planned,
    required DateTime actualBedtime,
    required PlanConfig config,
    WorkSchedule? work,
  }) {
    final lateBy = actualBedtime.difference(planned.bedtime);
    if (lateBy < grace) return Recovery(lateBy: Duration.zero);

    final workday = work != null && work.isWorkday(planned.wakeUp);
    var wakeUp = actualBedtime.add(minSleep);
    var latest = planned.wakeUp.add(maxWakeDelay);
    if (workday) {
      final onTime = _at(planned.wakeUp, work.latestWakeUp);
      if (onTime.isBefore(latest)) latest = onTime;
    }
    if (wakeUp.isAfter(latest)) wakeUp = latest;
    if (wakeUp.isBefore(planned.wakeUp)) wakeUp = planned.wakeUp;

    final napAt = _at(wakeUp, workday ? work.napTime : config.settings.napTime);

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

  static DateTime _at(DateTime day, ClockTime time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);
}
