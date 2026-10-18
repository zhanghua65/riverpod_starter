import 'package:alarm/alarm.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime permissions the alarm chain needs on Android.
///
/// Manifest declarations alone are not enough: Android 13+ asks the user for
/// notifications, and Android 12+ may withhold exact alarms (without it the
/// plugin falls back to inexact alarms that can ring minutes late).
abstract class AlarmPermissions {
  AlarmPermissions._();

  /// Requests whatever is still missing. Returns true when both are granted.
  static Future<bool> ensureGranted() async {
    if (!Alarm.android) return true;

    final notification = await _request(Permission.notification);
    final exactAlarm = await _request(Permission.scheduleExactAlarm);
    return notification && exactAlarm;
  }

  /// Some Android ROMs kill background work under battery optimization,
  /// which can drop alarms. True when the app is exempt (or not on Android).
  static Future<bool> batteryOptimizationIgnored() async {
    if (!Alarm.android) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Shows the system dialog asking to exempt the app.
  static Future<bool> requestIgnoreBatteryOptimizations() =>
      _request(Permission.ignoreBatteryOptimizations);

  static const _channel = MethodChannel('rhythm_compass/permissions');

  /// Android 14+ can withhold the full-screen intent that lights the screen
  /// and opens the ring page over the lock screen. True when allowed (or not
  /// on Android).
  static Future<bool> fullScreenIntentAllowed() async {
    if (!Alarm.android) return true;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Opens the system page where the user allows full-screen notifications.
  static Future<void> openFullScreenIntentSettings() =>
      _channel.invokeMethod<void>('openFullScreenIntentSettings');

  static Future<bool> _request(Permission permission) async {
    var status = await permission.status;
    if (status.isDenied) {
      status = await permission.request();
    }
    return status.isGranted;
  }
}
