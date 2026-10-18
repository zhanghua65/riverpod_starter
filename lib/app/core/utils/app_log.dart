import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small on-device log for chasing alarm and permission problems.
///
/// The same lines are also written to `rhythm_log.txt` in the app's external
/// files directory, so the file can be pulled with
/// `adb pull /sdcard/Android/data/<applicationId>/files/rhythm_log.txt`.
///
/// Entries go to logcat (tag `RhythmLog`, also in release builds) and to the
/// last [capacity] lines kept in shared preferences, so they survive the app
/// being killed and can be read on the permission check page.
class AppLog {
  AppLog._();

  static const capacity = 300;
  static const _key = 'app_log';

  static const fileName = 'rhythm_log.txt';
  static const _channel = MethodChannel('rhythm_compass/permissions');

  static List<String>? _lines;
  static File? _file;
  static String _header = '';
  static Future<void> _pending = Future.value();

  /// Appends one line stamped with the current time. Never throws.
  static void add(String tag, String message) {
    final now = DateTime.now();
    final line = '${_stamp(now)} [$tag] $message';
    debugPrint('RhythmLog $line');
    // Serialized so lines written back to back keep their order.
    _pending = _pending.then((_) => _append(line)).catchError((_) {});
  }

  /// Starts mirroring the log to [fileName]. Does nothing off Android.
  static Future<void> enableFile() async {
    try {
      final dir = await _channel.invokeMethod<String>('logDir');
      if (dir == null) return;
      final maker = await _channel.invokeMethod<String>('manufacturer') ?? '';
      _header = 'device=$maker os=${Platform.operatingSystemVersion}';
      _file = File('$dir/$fileName');
      _pending = _pending.then((_) => _writeFile()).catchError((_) {});
    } catch (_) {}
  }

  /// All kept lines, oldest first.
  static Future<List<String>> read() async {
    await _pending;
    try {
      return List.of(await _load());
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    await _pending;
    _lines = [];
    try {
      await _writeFile();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static Future<List<String>> _load() async {
    final cached = _lines;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    return _lines = List.of(prefs.getStringList(_key) ?? const []);
  }

  static Future<void> _append(String line) async {
    final lines = await _load();
    lines.add(line);
    if (lines.length > capacity) {
      lines.removeRange(0, lines.length - capacity);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, lines);
    await _writeFile();
  }

  static Future<void> _writeFile() async {
    final file = _file;
    if (file == null) return;
    // 300 short lines: rewriting the whole file keeps it trimmed and simple.
    await file.writeAsString('$_header\n${(await _load()).join('\n')}\n');
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:'
        '${two(t.second)}';
  }

  @visibleForTesting
  static void resetForTest() {
    _lines = null;
    _file = null;
    _pending = Future.value();
  }
}
