import 'package:alarm/alarm.dart';
import 'package:flutter/services.dart';

import '/app/core/services/schedule/band_sleep.dart';
import '/app/core/utils/app_log.dart';

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
  /// read (no Health Connect or no permission). Every read is logged with
  /// its outcome, so a missing night can be traced in the diagnostic log.
  Future<List<SleepSession>?> sessions(DateTime from, DateTime to) async {
    if (!Alarm.android) return null;
    final range = '${_stamp(from)}~${_stamp(to)}';
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'sleepSessions',
        {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch},
      );
      if (raw == null) {
        AppLog.add('band', 'read $range: no reply');
        return null;
      }
      final sessions = [
        for (final s in raw)
          SleepSession(
            DateTime.fromMillisecondsSinceEpoch(s['start']! as int),
            DateTime.fromMillisecondsSinceEpoch(s['end']! as int),
            source: s['source'] as String? ?? '',
          ),
      ];
      AppLog.add(
        'band',
        'read $range: ${sessions.length} sessions'
            '${sessions.isEmpty ? '' : ' ${[for (final s in sessions) '${_stamp(s.start)}-${_stamp(s.end)}@${s.source}'].join(' ')}'}',
      );
      return sessions;
    } on PlatformException catch (e) {
      AppLog.add('band', 'read $range failed: ${e.code} ${e.message ?? ''}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// A step-by-step probe of Health Connect: whether it is present, what
  /// this app may read, which band apps are installed and what the last 30
  /// days hold. Each line is also written to the diagnostic log.
  Future<List<String>> diagnose() async {
    if (!Alarm.android) return const ['not Android'];
    List<String> lines;
    try {
      lines =
          await _channel.invokeListMethod<String>('healthDiagnose') ??
          const ['no reply'];
    } on PlatformException catch (e) {
      lines = ['failed: ${e.code} ${e.message ?? ''}'];
    } on MissingPluginException {
      lines = const ['not available in this build'];
    }
    for (final line in lines) {
      AppLog.add('band', 'diag $line');
    }
    return lines;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
