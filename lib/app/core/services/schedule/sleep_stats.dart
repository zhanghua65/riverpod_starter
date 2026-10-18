import 'recovery.dart';
import 'rhythm_store.dart';

/// Summary of the sleep log for the history page. Pure Dart.
class SleepStats {
  SleepStats._({
    required this.nights,
    required this.onTimeNights,
    required this.averageSleep,
    required this.sleepNights,
    required this.averageLateBy,
  });

  /// [log] is newest first, as the store returns it.
  factory SleepStats.of(List<SleepLogEntry> log) {
    final slept = [
      for (final e in log)
        if (e.sleepDuration != null) e.sleepDuration!,
    ];
    final totalSleep = slept.fold(Duration.zero, (a, b) => a + b);
    final totalLate = log.fold(Duration.zero, (a, e) => a + e.lateBy);
    return SleepStats._(
      nights: log.length,
      onTimeNights: log.where((e) => e.lateBy < Recovery.grace).length,
      sleepNights: slept.length,
      averageSleep: slept.isEmpty
          ? null
          : Duration(minutes: totalSleep.inMinutes ~/ slept.length),
      averageLateBy: log.isEmpty
          ? null
          : Duration(minutes: totalLate.inMinutes ~/ log.length),
    );
  }

  /// Nights in the log.
  final int nights;

  /// Nights the user went to bed within the grace period of the plan.
  final int onTimeNights;

  /// Nights with both a bedtime and a wake-up, so a sleep length.
  final int sleepNights;

  /// Mean sleep length over [sleepNights]; null when there are none.
  final Duration? averageSleep;

  /// Mean of actual minus planned bedtime (negative when earlier); null for
  /// an empty log.
  final Duration? averageLateBy;

  /// Share of nights on time, 0 for an empty log.
  double get onTimeRate => nights == 0 ? 0 : onTimeNights / nights;
}
