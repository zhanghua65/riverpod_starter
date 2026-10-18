import 'package:alarm/alarm.dart';

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
    var ok = true;
    for (final settings in chain.toAlarmSettings()) {
      ok = await Alarm.set(alarmSettings: settings) && ok;
    }
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

  Future<bool> schedule(AlarmSettings settings) =>
      Alarm.set(alarmSettings: settings);

  Future<void> cancelChain(AlarmChain chain) async {
    for (final id in chain.ids) {
      await Alarm.stop(id);
    }
  }

  Future<bool> stop(int id) => Alarm.stop(id);

  Future<void> stopAll() => Alarm.stopAll();

  Future<List<AlarmSettings>> getAlarms() => Alarm.getAlarms();
}
