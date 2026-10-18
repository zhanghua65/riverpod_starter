import 'package:alarm/alarm.dart';
import 'package:flutter/services.dart';

import '/app/core/services/schedule/screen_bedtime.dart';

/// Reads the screen's on/off history from Android's usage stats. Needs the
/// usage access the user grants in the system settings; nothing leaves the
/// device.
class ScreenUsage {
  static const _channel = MethodChannel('rhythm_compass/permissions');

  /// True when the app may read usage stats. False off Android.
  Future<bool> hasAccess() async {
    if (!Alarm.android) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system page where the user grants usage access.
  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openUsageAccessSettings');

  /// Screen on/off events between [from] and [to], or null when they cannot
  /// be read (no access, or Android older than 9).
  Future<List<ScreenEvent>?> events(DateTime from, DateTime to) async {
    if (!Alarm.android) return null;
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'screenEvents',
        {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch},
      );
      if (raw == null) return null;
      return [
        for (final e in raw)
          ScreenEvent(
            DateTime.fromMillisecondsSinceEpoch(e['at']! as int),
            on: e['on']! as bool,
          ),
      ];
    } on MissingPluginException {
      return null;
    }
  }
}
