import 'package:alarm/alarm.dart';
import 'package:flutter/services.dart';

import '/app/core/services/schedule/band_sleep.dart';

/// Whether sleep can be read from Health Connect.
enum HealthSleepStatus {
  /// Not Android, or this phone has no Health Connect.
  unavailable,

  /// Health Connect is installed but too old for this app.
  needsUpdate,

  /// Available, but the user has not allowed reading sleep.
  denied,

  granted,
}

/// Reads the sleep sessions a band app (Mi Fitness / 小米运动健康) syncs to
/// Android's Health Connect. Read-only; nothing leaves the device.
class HealthSleep {
  static const _channel = MethodChannel('rhythm_compass/permissions');

  Future<HealthSleepStatus> status() async {
    if (!Alarm.android) return HealthSleepStatus.unavailable;
    try {
      final raw = await _channel.invokeMethod<String>('healthStatus');
      return HealthSleepStatus.values.asNameMap()[raw] ??
          HealthSleepStatus.unavailable;
    } on MissingPluginException {
      return HealthSleepStatus.unavailable;
    }
  }

  /// Shows Health Connect's permission dialog, or its store page when it
  /// needs an update. True when reading sleep is allowed afterwards.
  Future<bool> requestAccess() async =>
      await _channel.invokeMethod<bool>('requestHealthAccess') ?? false;

  /// Opens Health Connect's own settings, where the user can see which apps
  /// write sleep and grant this app access after declining twice.
  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openHealthConnect');

  /// Opens the band's companion app so the user can turn on syncing to
  /// Health Connect. False when neither Xiaomi app is installed.
  Future<bool> openBandApp() async =>
      await _channel.invokeMethod<bool>('openBandApp') ?? false;

  /// Sleep sessions overlapping [from]..[to], or null when they cannot be
  /// read (no Health Connect or no permission).
  Future<List<SleepSession>?> sessions(DateTime from, DateTime to) async {
    if (!Alarm.android) return null;
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'sleepSessions',
        {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch},
      );
      if (raw == null) return null;
      return [
        for (final s in raw)
          SleepSession(
            DateTime.fromMillisecondsSinceEpoch(s['start']! as int),
            DateTime.fromMillisecondsSinceEpoch(s['end']! as int),
            source: s['source'] as String? ?? '',
          ),
      ];
    } on MissingPluginException {
      return null;
    }
  }
}
