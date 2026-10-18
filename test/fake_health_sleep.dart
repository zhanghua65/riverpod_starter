import 'package:riverpod_starter/app/core/services/schedule/band_sleep.dart';
import 'package:riverpod_starter/app/core/services/usage/health_sleep.dart';

/// Returns canned sleep sessions instead of reading Health Connect.
class FakeHealthSleep extends HealthSleep {
  FakeHealthSleep([this.sleepSessions]);

  /// Null means reading sleep is not allowed.
  List<SleepSession>? sleepSessions;

  @override
  Future<HealthSleepStatus> status() async => sleepSessions == null
      ? HealthSleepStatus.denied
      : HealthSleepStatus.granted;

  @override
  Future<bool> requestAccess() async => sleepSessions != null;

  @override
  Future<void> openSettings() async {}

  @override
  Future<bool> openBandApp() async => false;

  @override
  Future<List<String>> diagnose() async => const ['fake'];

  @override
  Future<List<SleepSession>?> sessions(DateTime from, DateTime to) async =>
      sleepSessions;
}
