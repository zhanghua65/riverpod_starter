import '/app/core/services/alarm/alarm_chain.dart';

/// The screen turning on or off, as recorded by Android's usage stats.
class ScreenEvent {
  const ScreenEvent(this.at, {required this.on});

  final DateTime at;

  /// True when the screen turned on (interactive), false when it went off.
  final bool on;
}

/// Works out when the user put the phone down for the night and picked it
/// up in the morning from the screen's on/off history. Most users only turn
/// the screen off for good when they go to sleep, so the start of the
/// night's first long screen-off stretch is taken as the bedtime, and the
/// first stretch of real use after the night's sleep as the wake-up.
abstract class ScreenBedtime {
  ScreenBedtime._();

  /// How far before the planned bedtime the search starts.
  static const lookBack = Duration(hours: 4);

  /// How far after the planned wake-up the search ends.
  static const lookAhead = Duration(hours: 4);

  /// Screen-on moments up to this long inside a screen-off stretch (checking
  /// the time, a notification, the alarm page itself) do not end it.
  static const glance = Duration(minutes: 5);

  /// The screen must stay off at least this long to count as sleep.
  static const minSleep = Duration(hours: 3);

  /// The screen must stay on at least this long after the night's sleep to
  /// count as getting up; shorter moments are stopping the alarm or a look
  /// at the time.
  static const wakeUse = Duration(minutes: 10);

  /// Screen-off moments up to this long (the screen timing out and being
  /// woken again) do not interrupt that use.
  static const useGap = Duration(minutes: 1);

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
    final end = _end(planned, now);
    for (final off in _offStretches(_sorted(planned, events, end), end)) {
      if (off.from.isBefore(planned.wakeUp) && off.length >= minSleep) {
        return off.from;
      }
    }
    return null;
  }

  /// When the user got up after going to bed at [bedtime] on the night of
  /// [planned]: the start of the first [wakeUse] of screen use after the
  /// last screen-off stretch of [minSleep] that ends after [bedtime]. Null
  /// while the user is still asleep or has not used the phone that long.
  static DateTime? inferWakeUp({
    required AlarmChain planned,
    required List<ScreenEvent> events,
    required DateTime bedtime,
    required DateTime now,
  }) {
    final end = _end(planned, now);
    final sorted = _sorted(planned, events, end);
    final sleeps = [
      for (final off in _offStretches(sorted, end))
        if (off.length >= minSleep && off.to.isAfter(bedtime)) off,
    ];
    if (sleeps.isEmpty) return null;
    final after = sleeps.last.to;
    final morning = [
      for (final e in sorted)
        if (!e.at.isBefore(after)) e,
    ];
    for (final use in _onStretches(morning, end)) {
      if (use.length >= wakeUse) return use.from;
    }
    return null;
  }

  static DateTime _end(AlarmChain planned, DateTime now) {
    final end = windowEnd(planned);
    return now.isBefore(end) ? now : end;
  }

  static List<ScreenEvent> _sorted(
    AlarmChain planned,
    List<ScreenEvent> events,
    DateTime end,
  ) {
    final start = windowStart(planned);
    return [
      for (final e in events)
        if (!e.at.isBefore(start) && !e.at.isAfter(end)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  /// Screen-off stretches in [sorted], each from an off event to the next
  /// on event that lasts longer than [glance]. One still running at [end]
  /// ends there.
  static List<_Span> _offStretches(List<ScreenEvent> sorted, DateTime end) =>
      _stretches(sorted, end, on: false, gap: glance);

  /// Screen-on stretches in [sorted], ignoring screen-off moments up to
  /// [useGap].
  static List<_Span> _onStretches(List<ScreenEvent> sorted, DateTime end) =>
      _stretches(sorted, end, on: true, gap: useGap);

  /// Stretches where the screen is [on] (or off), bridging moments in the
  /// other state up to [gap] long.
  static List<_Span> _stretches(
    List<ScreenEvent> sorted,
    DateTime end, {
    required bool on,
    required Duration gap,
  }) {
    final spans = <_Span>[];
    DateTime? since;
    DateTime? brokenAt;
    for (final e in sorted) {
      if (e.on == on) {
        if (since != null &&
            brokenAt != null &&
            e.at.difference(brokenAt) > gap) {
          spans.add(_Span(since, brokenAt));
          since = null;
        }
        since ??= e.at;
        brokenAt = null;
      } else {
        brokenAt ??= e.at;
      }
    }
    if (since != null) {
      final broken = brokenAt != null && end.difference(brokenAt) > gap;
      spans.add(_Span(since, broken ? brokenAt : end));
    }
    return spans;
  }
}

class _Span {
  const _Span(this.from, this.to);

  final DateTime from;
  final DateTime to;

  Duration get length => to.difference(from);
}
