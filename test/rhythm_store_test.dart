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
}
