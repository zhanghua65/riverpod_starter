import 'package:flutter/material.dart';
import '/app/core/services/alarm/alarm_permissions.dart';

/// Steps that stop MIUI / HyperOS from cancelling the alarms when the app is
/// swiped away in recents.
class XiaomiKeepAliveSteps extends StatelessWidget {
  const XiaomiKeepAliveSteps({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '小米/红米手机上，从最近任务划掉应用会强制停止它，已注册的闹钟也会被取消。请依次设置：',
      ),
      const SizedBox(height: 8),
      _row('1. 允许自启动', '打开本应用的开关', '打开自启动页',
          AlarmPermissions.openAutoStartSettings),
      _row('2. 省电策略选“无限制”', '不要选“智能限制”', '打开省电策略页',
          AlarmPermissions.openBatteryStrategySettings),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('3. 在最近任务里锁定本应用'),
        subtitle: Text('打开最近任务，下拉或长按本应用卡片，点锁形图标。锁定后一键清理不会杀掉它。'),
      ),
    ],
  );

  Widget _row(
    String title,
    String body,
    String button,
    Future<void> Function() onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(body),
    trailing: TextButton(onPressed: onTap, child: Text(button)),
  );
}
