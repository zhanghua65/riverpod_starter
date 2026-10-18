import '/app/core/services/alarm/alarm_chain.dart';

/// The screen turning on or off, as recorded by Android's usage stats.
class ScreenEvent {
  const ScreenEvent(this.at, {required this.on});

  final DateTime at;

  /// True when the screen turned on (interactive), false when it went off.
  final bool on;
}

/// Works out when the user put the phone down for the night from the
/// screen's on/off history. Most users only turn the screen off for good
/// when they go to sleep, so the start of the night's first long screen-off
/// stretch is taken as the bedtime.
abstract class ScreenBedtime {
  ScreenBedtime._();

  /// How far before the planned bedtime the search starts.
  static const lookBack = Duration(hours: 4);

  /// How far after the planned wake-up the search ends.
  static const lookAhead = Duration(hours: 2);

  /// Screen-on moments up to this long inside a screen-off stretch (checking
  /// the time, a notification, the alarm page itself) do not end it.
  static const glance = Duration(minutes: 5);

  /// The screen must stay off at least this long to count as sleep.
  static const minSleep = Duration(hours: 3);

  /// Events to request for [planned]: from [lookBack] before its bedtime to
  /// [lookAhead] after its wake-up.
  static DateTime windowStart(AlarmChain planned) =>
      planned.bedtime.subtract(lookBack);

  static DateTime windowEnd(AlarmChain planned) =>
      planned.wakeUp.add(lookAhead);

  /// When the screen went off for the night of [planned], or null when no
  /// screen-off stretch of [minSleep] starts before the planned wake-up.
  ///
  /// [events] may be in any order; those outside the window are ignored.
  /// A stretch still running at [now] ends at [now].
  static DateTime? infer({
    required AlarmChain planned,
    required List<ScreenEvent> events,
    required DateTime now,
  }) {
    final start = windowStart(planned);
    var end = windowEnd(planned);
    if (now.isBefore(end)) end = now;

    final sorted = [
      for (final e in events)
        if (!e.at.isBefore(start) && !e.at.isAfter(end)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));

    // Screen-off stretches, each from an off event to the next on event
    // that is not followed by an off event within [glance].
    DateTime? offSince;
    DateTime? onSince;
    for (final e in sorted) {
      if (!e.on) {
        if (onSince != null && e.at.difference(onSince) > glance) {
          // The screen was in use: the stretch before it ended when it
          // came on.
          final found = _sleep(offSince, onSince, planned);
          if (found != null) return found;
          offSince = null;
        }
        offSince ??= e.at;
        onSince = null;
      } else {
        onSince ??= e.at;
      }
    }
    final stillOn = onSince != null && end.difference(onSince) > glance;
    return _sleep(offSince, stillOn ? onSince : end, planned);
  }

  static DateTime? _sleep(DateTime? from, DateTime to, AlarmChain planned) {
    if (from == null || !from.isBefore(planned.wakeUp)) return null;
    return to.difference(from) >= minSleep ? from : null;
  }
}
