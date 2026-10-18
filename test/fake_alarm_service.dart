import 'package:alarm/alarm.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_service.dart';

/// Keeps registered alarms in memory instead of calling the plugin.
class FakeAlarmService extends AlarmService {
  final alarms = <int, AlarmSettings>{};

  /// Registrations that reached the plugin.
  var scheduleCalls = 0;

  @override
  Future<bool> scheduleChain(AlarmChain chain) async {
    for (final s in chain.toAlarmSettings()) {
      alarms[s.id] = s;
    }
    return true;
  }

  @override
  Future<bool> schedule(AlarmSettings settings) async {
    scheduleCalls++;
    alarms[settings.id] = settings;
    return true;
  }

  @override
  Future<bool> stop(int id) async => alarms.remove(id) != null;

  @override
  Future<void> stopAll() async => alarms.clear();

  @override
  Future<List<AlarmSettings>> getAlarms() async => alarms.values.toList();
}
