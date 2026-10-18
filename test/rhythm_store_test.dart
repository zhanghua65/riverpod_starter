import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_store.dart';

void main() {
  final entry = SleepLogEntry(
    night: DateTime(2026, 10, 10),
    plannedBedtime: DateTime(2026, 10, 10, 23),
    actualBedtime: DateTime(2026, 10, 11, 0, 40),
    source: BedtimeSource.screen,
  );

  test('a log entry keeps how it was recorded', () {
    final restored = SleepLogEntry.fromJson(entry.toJson());
    expect(restored.source, BedtimeSource.screen);
    expect(restored.actualBedtime, entry.actualBedtime);
  });

  test('entries saved before sources existed count as manual', () {
    final json = entry.toJson()..remove('source');
    expect(SleepLogEntry.fromJson(json).source, BedtimeSource.manual);
  });

  test('a wake-up survives a round trip and is optional', () {
    final woke = entry.withWakeUp(DateTime(2026, 10, 11, 7, 20));
    expect(
      SleepLogEntry.fromJson(woke.toJson()).actualWakeUp,
      DateTime(2026, 10, 11, 7, 20),
    );
    expect(SleepLogEntry.fromJson(entry.toJson()).actualWakeUp, isNull);
  });

  test('a wake-up remembers whether the user entered it', () {
    final woke = entry.withWakeUp(
      DateTime(2026, 10, 11, 7, 20),
      source: BedtimeSource.manual,
    );
    expect(
      SleepLogEntry.fromJson(woke.toJson()).wakeUpSource,
      BedtimeSource.manual,
    );
    // Saved before wake-up sources existed: those came from the screen.
    final old = entry.withWakeUp(DateTime(2026, 10, 11, 7, 20)).toJson()
      ..remove('wakeUpSource');
    expect(SleepLogEntry.fromJson(old).wakeUpSource, BedtimeSource.screen);
  });

  test('a corrected bedtime counts as manual and keeps the wake-up', () {
    final woke = entry.withWakeUp(DateTime(2026, 10, 11, 7, 20));
    final fixed = woke.withBedtime(DateTime(2026, 10, 10, 23, 50));
    expect(fixed.source, BedtimeSource.manual);
    expect(fixed.actualBedtime, DateTime(2026, 10, 10, 23, 50));
    expect(fixed.actualWakeUp, DateTime(2026, 10, 11, 7, 20));
    expect(fixed.wakeUpSource, BedtimeSource.screen);
  });

  test('band times survive a round trip', () {
    final band = entry
        .withBedtime(DateTime(2026, 10, 11, 0, 55), source: BedtimeSource.band)
        .withWakeUp(DateTime(2026, 10, 11, 7, 5), source: BedtimeSource.band);
    final restored = SleepLogEntry.fromJson(band.toJson());
    expect(restored.source, BedtimeSource.band);
    expect(restored.wakeUpSource, BedtimeSource.band);
  });
}
