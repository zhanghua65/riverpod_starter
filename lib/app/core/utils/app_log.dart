import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small on-device log for chasing alarm and permission problems.
///
/// Entries go to logcat (tag `RhythmLog`, also in release builds) and to the
/// last [capacity] lines kept in shared preferences, so they survive the app
/// being killed and can be read on the permission check page.
class AppLog {
  AppLog._();

  static const capacity = 300;
  static const _key = 'app_log';

  static List<String>? _lines;
  static Future<void> _pending = Future.value();

  /// Appends one line stamped with the current time. Never throws.
  static void add(String tag, String message) {
    final now = DateTime.now();
    final line = '${_stamp(now)} [$tag] $message';
    debugPrint('RhythmLog $line');
    // Serialized so lines written back to back keep their order.
    _pending = _pending.then((_) => _append(line)).catchError((_) {});
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
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:'
        '${two(t.second)}';
  }

  @visibleForTesting
  static void resetForTest() {
    _lines = null;
    _pending = Future.value();
  }
}
