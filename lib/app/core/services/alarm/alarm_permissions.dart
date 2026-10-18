import 'package:alarm/alarm.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '/app/core/utils/app_log.dart';

Future<bool> openAppSettingsPage() => openAppSettings();

/// What [AlarmPermissions.check] could read; the vendor switches are not here
/// because Android gives no way to read them.
class AlarmPermissionReport {
  const AlarmPermissionReport({
    required this.notification,
    required this.exactAlarm,
    required this.fullScreenIntent,
    required this.batteryOptimizationIgnored,
  });

  final bool notification;
  final bool exactAlarm;
  final bool fullScreenIntent;
  final bool batteryOptimizationIgnored;

  bool get allGranted =>
      notification && exactAlarm && fullScreenIntent && batteryOptimizationIgnored;
}

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

  /// True when notifications and exact alarms are both granted (or not on
  /// Android). Unlike [ensureGranted] it never prompts.
  static Future<bool> basicGranted() async {
    if (!Alarm.android) return true;
    return await Permission.notification.isGranted &&
        await Permission.scheduleExactAlarm.isGranted;
  }

  static String? _lastLogged;

  /// Reads every status that can be read, without prompting.
  static Future<AlarmPermissionReport> check() async {
    if (!Alarm.android) {
      return const AlarmPermissionReport(
        notification: true,
        exactAlarm: true,
        fullScreenIntent: true,
        batteryOptimizationIgnored: true,
      );
    }
    final report = AlarmPermissionReport(
      notification: await Permission.notification.isGranted,
      exactAlarm: await Permission.scheduleExactAlarm.isGranted,
      fullScreenIntent: await fullScreenIntentAllowed(),
      batteryOptimizationIgnored: await batteryOptimizationIgnored(),
    );
    // Only what is missing: the AI reading the log needs the problems.
    final missing = [
      if (!report.notification) 'notification',
      if (!report.exactAlarm) 'exactAlarm',
      if (!report.fullScreenIntent) 'fullScreenIntent',
      if (!report.batteryOptimizationIgnored) 'batteryOptimization',
    ].join(',');
    if (missing != _lastLogged) {
      _lastLogged = missing;
      AppLog.add('perm', missing.isEmpty ? 'all granted' : 'missing: $missing');
    }
    return report;
  }

  /// Asks for notifications; once denied for good the system shows no
  /// dialog, so this sends the user to the app settings instead.
  static Future<bool> requestNotification() => _requestOrOpenSettings(
    Permission.notification,
  );

  /// Same as [requestNotification] for exact alarms.
  static Future<bool> requestExactAlarm() => _requestOrOpenSettings(
    Permission.scheduleExactAlarm,
  );

  static Future<bool> _requestOrOpenSettings(Permission permission) async {
    if (await _request(permission)) return true;
    await openAppSettings();
    return false;
  }

  /// Opens this app's page in the system settings, where ROM-specific
  /// switches (auto-start, lock-screen display, pop-ups) live.
  static Future<bool> openAppSettings() => openAppSettingsPage();

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

  /// Xiaomi, Redmi and POCO phones (MIUI / HyperOS): swiping the app away in
  /// recents force-stops it and cancels its alarms unless the app is allowed
  /// to auto-start and has no battery restriction.
  static Future<bool> isXiaomi() async {
    final maker = await manufacturer();
    return maker.contains('xiaomi') ||
        maker.contains('redmi') ||
        maker.contains('poco');
  }

  /// Lower-case manufacturer, or '' off Android.
  static Future<String> manufacturer() async {
    if (!Alarm.android) return '';
    try {
      return await _channel.invokeMethod<String>('manufacturer') ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Opens the vendor's auto-start page; falls back to the app's settings.
  static Future<void> openAutoStartSettings() => _openVendorPage(
    'openAutoStartSettings',
  );

  /// Opens the vendor's per-app battery strategy page ("无限制").
  static Future<void> openBatteryStrategySettings() => _openVendorPage(
    'openBatteryStrategySettings',
  );

  /// Opens the vendor's per-app permission list, where "锁屏显示" and
  /// "后台弹出界面" live. Neither can be read from code, so this only guides.
  static Future<void> openPermissionEditor() => _openVendorPage(
    'openPermissionEditor',
  );

  static Future<void> _openVendorPage(String method) async {
    final opened = await _channel.invokeMethod<bool>(method) ?? false;
    if (!opened) await openAppSettings();
  }

  static Future<bool> _request(Permission permission) async {
    var status = await permission.status;
    if (status.isDenied) {
      status = await permission.request();
    }
    return status.isGranted;
  }
}
