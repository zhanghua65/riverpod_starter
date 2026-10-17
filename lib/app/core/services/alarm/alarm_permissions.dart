import 'package:alarm/alarm.dart';
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

  static Future<bool> _request(Permission permission) async {
    var status = await permission.status;
    if (status.isDenied) {
      status = await permission.request();
    }
    return status.isGranted;
  }
}
