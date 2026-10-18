import 'stepping_plan.dart';

/// The user's working day. Keeps a postponed wake-up from making the user
/// late for work, places the nap capsule in the lunch break, and gives the
/// AI advisor the context for its suggestions.
class WorkSchedule {
  const WorkSchedule({
    this.workdays = const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
    this.start = const ClockTime(9, 0),
    this.end = const ClockTime(18, 0),
    this.lunchStart = const ClockTime(12, 0),
    this.lunchEnd = const ClockTime(13, 30),
    this.morningMinutes = 60,
  });

  /// Weekdays as in [DateTime.weekday] (1 = Monday).
  final Set<int> workdays;

  final ClockTime start;
  final ClockTime end;
  final ClockTime lunchStart;
  final ClockTime lunchEnd;

  /// Getting ready plus the commute, between waking up and starting work.
  final int morningMinutes;

  static const morningRange = (min: 10, max: 180);

  /// Time to eat before the nap capsule starts.
  static const lunchMeal = Duration(minutes: 30);

  /// The nap capsule plus a few minutes to get back to work.
  static const napRoom = Duration(minutes: 25);

  bool isWorkday(DateTime day) => workdays.contains(day.weekday);

  /// The latest wake-up that still gets the user to work on time.
  ClockTime get latestWakeUp =>
      ClockTime.fromMinutes((start.minutes - morningMinutes) % (24 * 60));

  /// After lunch, but early enough that the nap ends before the break does.
  ClockTime get napTime {
    final afterMeal = lunchStart.minutes + lunchMeal.inMinutes;
    final latest = lunchEnd.minutes - napRoom.inMinutes;
    var nap = afterMeal < latest ? afterMeal : latest;
    if (nap < lunchStart.minutes) nap = lunchStart.minutes;
    return ClockTime.fromMinutes(nap);
  }

  WorkSchedule copyWith({
    Set<int>? workdays,
    ClockTime? start,
    ClockTime? end,
    ClockTime? lunchStart,
    ClockTime? lunchEnd,
    int? morningMinutes,
  }) => WorkSchedule(
    workdays: workdays ?? this.workdays,
    start: start ?? this.start,
    end: end ?? this.end,
    lunchStart: lunchStart ?? this.lunchStart,
    lunchEnd: lunchEnd ?? this.lunchEnd,
    morningMinutes: morningMinutes ?? this.morningMinutes,
  );

  Map<String, Object> toJson() => {
    'workdays': (workdays.toList()..sort()),
    'start': start.minutes,
    'end': end.minutes,
    'lunchStart': lunchStart.minutes,
    'lunchEnd': lunchEnd.minutes,
    'morningMinutes': morningMinutes,
  };

  /// Missing or invalid values fall back to the defaults.
  factory WorkSchedule.fromJson(Map<String, dynamic> json) {
    const d = WorkSchedule();
    ClockTime time(String key, ClockTime fallback) {
      final v = json[key];
      return v is int && v >= 0 && v < 24 * 60
          ? ClockTime.fromMinutes(v)
          : fallback;
    }

    final days = json['workdays'];
    final morning = json['morningMinutes'];
    return WorkSchedule(
      workdays: days is List
          ? {
              for (final v in days)
                if (v is int && v >= DateTime.monday && v <= DateTime.sunday) v,
            }
          : d.workdays,
      start: time('start', d.start),
      end: time('end', d.end),
      lunchStart: time('lunchStart', d.lunchStart),
      lunchEnd: time('lunchEnd', d.lunchEnd),
      morningMinutes:
          morning is int &&
              morning >= morningRange.min &&
              morning <= morningRange.max
          ? morning
          : d.morningMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkSchedule &&
      other.workdays.length == workdays.length &&
      other.workdays.containsAll(workdays) &&
      other.start == start &&
      other.end == end &&
      other.lunchStart == lunchStart &&
      other.lunchEnd == lunchEnd &&
      other.morningMinutes == morningMinutes;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(workdays),
    start,
    end,
    lunchStart,
    lunchEnd,
    morningMinutes,
  );
}
