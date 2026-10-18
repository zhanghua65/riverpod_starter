import '/app/core/services/alarm/alarm_chain.dart';

/// A wall-clock time without a date, e.g. 23:30.
class ClockTime {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  ClockTime.fromMinutes(int minutes)
      : this((minutes ~/ 60) % 24, minutes % 60);

  ClockTime.of(DateTime t) : this(t.hour, t.minute);

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => minutes;
}

/// 自适应渐进排期引擎（Dynamic Stepping Engine）。
///
/// Moves bedtime and wake-up from the user's current schedule to the target
/// in equal daily steps of at most [maxStepMinutes], and turns each day into
/// an [AlarmChain]. The last night always lands exactly on the target.
class SteppingPlan {
  SteppingPlan._();

  /// Bedtimes before noon are read as after midnight (01:30 is later than
  /// 23:30), so a night's bedtime is counted in minutes from that evening's
  /// midnight and can exceed 24 hours.
  static const _afterMidnightBefore = 12;

  /// Builds one [AlarmChain] per night, starting on [firstNight].
  ///
  /// The number of nights is whatever keeps each step within
  /// [maxStepMinutes], capped at [maxDays]; when the cap applies the steps
  /// grow larger instead of leaving the target unreached. Times are rounded
  /// to 5 minutes except on the final night.
  ///
  /// Throws [ArgumentError] when a bedtime would not come before the next
  /// morning's wake-up.
  static List<AlarmChain> build({
    required ClockTime currentBedtime,
    required ClockTime currentWakeUp,
    required ClockTime targetBedtime,
    required ClockTime targetWakeUp,
    required DateTime firstNight,
    int maxStepMinutes = 30,
    int maxDays = 7,
    Duration windDownLead = const Duration(minutes: 45),
  }) {
    final fromBed = _bedtimeMinutes(currentBedtime);
    final toBed = _bedtimeMinutes(targetBedtime);
    final fromWake = currentWakeUp.minutes;
    final toWake = targetWakeUp.minutes;

    final bedShift = toBed - fromBed;
    final wakeShift = toWake - fromWake;
    final days = daysNeeded(
      bedShift: bedShift,
      wakeShift: wakeShift,
      maxStepMinutes: maxStepMinutes,
      maxDays: maxDays,
    );

    return [
      for (var day = 1; day <= days; day++)
        _chainFor(
          night: DateTime(
            firstNight.year,
            firstNight.month,
            firstNight.day + day - 1,
          ),
          bedMinutes: fromBed + _step(bedShift, day, days),
          wakeMinutes: fromWake + _step(wakeShift, day, days),
          windDownLead: windDownLead,
        ),
    ];
  }

  static int daysNeeded({
    required int bedShift,
    required int wakeShift,
    required int maxStepMinutes,
    required int maxDays,
  }) {
    final largest = bedShift.abs() > wakeShift.abs()
        ? bedShift.abs()
        : wakeShift.abs();
    final days = (largest / maxStepMinutes).ceil();
    return days.clamp(1, maxDays);
  }

  static int _bedtimeMinutes(ClockTime t) =>
      t.hour < _afterMidnightBefore ? t.minutes + 24 * 60 : t.minutes;

  /// Cumulative shift after [day] of [days], rounded to 5 minutes; exact on
  /// the last day.
  static int _step(int shift, int day, int days) {
    if (day == days) return shift;
    return (shift * day / days / 5).round() * 5;
  }

  static AlarmChain _chainFor({
    required DateTime night,
    required int bedMinutes,
    required int wakeMinutes,
    required Duration windDownLead,
  }) {
    // Minute overflow rolls into the following days, which handles bedtimes
    // after midnight and the next morning's wake-up.
    DateTime at(int minutes) =>
        DateTime(night.year, night.month, night.day, 0, minutes);

    final bedtime = at(bedMinutes);
    final wakeUp = at(24 * 60 + wakeMinutes);
    if (!bedtime.isBefore(wakeUp)) {
      throw ArgumentError('bedtime $bedtime is not before wake-up $wakeUp');
    }
    return AlarmChain(
      night: night,
      windDown: at(bedMinutes - windDownLead.inMinutes),
      bedtime: bedtime,
      wakeUp: wakeUp,
    );
  }
}
