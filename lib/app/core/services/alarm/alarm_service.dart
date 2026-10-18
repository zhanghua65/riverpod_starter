import 'package:alarm/alarm.dart';

import '/app/core/utils/app_log.dart';
import 'alarm_chain.dart';

/// Registers and cancels alarm chains through the alarm plugin.
///
/// The plugin has no recurring alarms, so callers register each night's chain
/// explicitly (and re-register upcoming nights on app start).
class AlarmService {
  /// Must run once before any other call, after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> init() => Alarm.init();

  /// Registers every future stage of [chain]. Stages already in the past are
  /// skipped. Returns false if any registration failed.
  Future<bool> scheduleChain(AlarmChain chain) async {
    final all = chain.toAlarmSettings();
    var ok = true;
    for (final settings in all) {
      ok = await Alarm.set(alarmSettings: settings) && ok;
    }
    _logSet(all, ok);
    return ok;
  }

  /// Registers every future stage of [chains], skipping alarms that are
  /// already registered with exactly the same settings. Each registration
  /// costs several native calls and store writes in the plugin, so leaving
  /// unchanged alarms alone keeps the sync on every app start cheap.
  Future<bool> scheduleChains(List<AlarmChain> chains) async {
    final existing = {for (final a in await getAlarms()) a.id: a};
    var ok = true;
    final changed = <AlarmSettings>[];
    for (final chain in chains) {
      for (final settings in chain.toAlarmSettings()) {
        if (existing[settings.id] == settings) continue;
        ok = await Alarm.set(alarmSettings: settings) && ok;
        changed.add(settings);
      }
    }
    _logSet(changed, ok);
    return ok;
  }

  /// Replaces every registered alarm with [chains], e.g. a new stepping plan.
  Future<bool> replaceAll(List<AlarmChain> chains) async {
    await Alarm.stopAll();
    var ok = true;
    for (final chain in chains) {
      ok = await scheduleChain(chain) && ok;
    }
    return ok;
  }

  Future<bool> schedule(AlarmSettings settings) async {
    final ok = await Alarm.set(alarmSettings: settings);
    _logSet([settings], ok);
    return ok;
  }

  /// One line per registration batch, not per alarm: a start re-registers
  /// up to 24 alarms.
  void _logSet(List<AlarmSettings> set, bool ok) {
    if (set.isEmpty && ok) return;
    final times = [for (final s in set) s.dateTime]..sort();
    AppLog.add(
      'alarm',
      'set ${set.length}, next=${times.isEmpty ? '-' : times.first} ok=$ok',
    );
  }

  Future<void> cancelChain(AlarmChain chain) async {
    for (final id in chain.ids) {
      await Alarm.stop(id);
    }
  }

  Future<bool> stop(int id) => Alarm.stop(id);

  Future<void> stopAll() => Alarm.stopAll();

  Future<List<AlarmSettings>> getAlarms() => Alarm.getAlarms();
}
