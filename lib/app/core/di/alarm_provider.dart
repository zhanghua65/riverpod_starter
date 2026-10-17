import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/services/alarm/alarm_service.dart';

final alarmServiceProvider = Provider<AlarmService>((ref) => AlarmService());

/// Alarms currently registered with the plugin.
final scheduledAlarmsProvider = StreamProvider<AlarmSet>(
  (ref) => Alarm.scheduled,
);

/// Alarms ringing right now.
final ringingAlarmsProvider = StreamProvider<AlarmSet>(
  (ref) => Alarm.ringing,
);
