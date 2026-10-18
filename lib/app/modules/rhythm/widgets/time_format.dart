import 'package:flutter/material.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/schedule/stepping_plan.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String hourMinute(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String monthDay(DateTime t) => '${t.month}月${t.day}日';

/// Sleep length in hours and how many 90-minute cycles it covers.
String sleepSummary(Duration sleep) {
  final hours = sleep.inMinutes / 60;
  final cycles = sleep.inMinutes / 90;
  return '睡 ${hours.toStringAsFixed(1)} 小时，约 ${cycles.toStringAsFixed(1)} 个周期';
}

String chainSummary(AlarmChain chain) =>
    '降速 ${hourMinute(chain.windDown)} · 熄灯 ${hourMinute(chain.bedtime)} · '
    '起床 ${hourMinute(chain.wakeUp)}\n'
    '${sleepSummary(chain.wakeUp.difference(chain.bedtime))}';

Future<ClockTime?> pickClockTime(
  BuildContext context,
  ClockTime initial,
) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
  );
  return picked == null ? null : ClockTime(picked.hour, picked.minute);
}
