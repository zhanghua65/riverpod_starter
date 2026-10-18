import 'package:riverpod_starter/app/core/services/schedule/screen_bedtime.dart';
import 'package:riverpod_starter/app/core/services/usage/screen_usage.dart';

/// Returns canned screen events instead of reading usage stats.
class FakeScreenUsage extends ScreenUsage {
  FakeScreenUsage([this.screenEvents]);

  /// Null means usage access is not granted.
  List<ScreenEvent>? screenEvents;

  @override
  Future<bool> hasAccess() async => screenEvents != null;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<ScreenEvent>?> events(DateTime from, DateTime to) async =>
      screenEvents;
}
