import '/app/core/services/alarm/alarm_chain.dart';
import 'screen_bedtime.dart';

/// A sleep session a band or watch app (e.g. Xiaomi's Mi Fitness) wrote to
/// Health Connect.
class SleepSession {
  const SleepSession(this.start, this.end, {this.source = ''});

  final DateTime start;
  final DateTime end;

  /// Package name of the app that wrote it.
  final String source;

  Duration get length => end.difference(start);
}

/// Picks last night's sleep out of the sessions a band recorded. Bands split
/// a night into several sessions when the wearer is awake for a while, so
/// sessions close together are joined first.
abstract class BandSleep {
  BandSleep._();

  /// Sessions at most this far apart are one night's sleep.
  static const joinGap = Duration(hours: 1);

  /// A joined night shorter than this is a nap, not the night's sleep.
  static const minSleep = Duration(hours: 3);

  /// The night's sleep for [planned]: the first joined run of [sessions]
  /// that starts before the planned wake-up and lasts [minSleep]. Searches
  /// the same window as [ScreenBedtime]. Sessions still running at [now] are
  /// skipped, since the band only writes them once they end.
  ///
  /// [sessions] may be in any order.
  static SleepSession? pick({
    required AlarmChain planned,
    required List<SleepSession> sessions,
    required DateTime now,
  }) {
    final start = ScreenBedtime.windowStart(planned);
    final end = ScreenBedtime.windowEnd(planned);
    final sorted = [
      for (final s in sessions)
        if (s.end.isAfter(start) &&
            s.start.isBefore(end) &&
            s.end.isAfter(s.start) &&
            !s.end.isAfter(now))
          s,
    ]..sort((a, b) => a.start.compareTo(b.start));

    final joined = <SleepSession>[];
    for (final s in sorted) {
      final last = joined.lastOrNull;
      if (last != null && !s.start.isAfter(last.end.add(joinGap))) {
        joined[joined.length - 1] = SleepSession(
          last.start,
          s.end.isAfter(last.end) ? s.end : last.end,
          source: last.source,
        );
      } else {
        joined.add(s);
      }
    }
    for (final night in joined) {
      if (night.start.isBefore(planned.wakeUp) && night.length >= minSleep) {
        return night;
      }
    }
    return null;
  }
}
