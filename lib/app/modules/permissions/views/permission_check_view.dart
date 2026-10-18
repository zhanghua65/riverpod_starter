import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/app/core/utils/app_log.dart';
import '/app/core/services/alarm/alarm_permissions.dart';

/// Lists what the alarm chain needs and whether the phone grants it.
///
/// Notifications, exact alarms, full-screen notifications and battery
/// optimization can be read, so they show a real status. The vendor switches
/// (auto-start, lock-screen display, pop-ups) cannot, so they only link to
/// the settings page.
class PermissionCheckView extends StatefulWidget {
  const PermissionCheckView({super.key});

  @override
  State<PermissionCheckView> createState() => _PermissionCheckViewState();
}

class _PermissionCheckViewState extends State<PermissionCheckView>
    with WidgetsBindingObserver {
  AlarmPermissionReport? _report;
  bool _xiaomi = false;
  List<String> _log = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlarmPermissions.isXiaomi().then((v) {
      if (mounted) setState(() => _xiaomi = v);
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from a system settings page: read the statuses again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final report = await AlarmPermissions.check();
    final log = await AppLog.read();
    if (mounted) {
      setState(() {
        _report = report;
        _log = log;
      });
    }
  }

  /// Device line plus the log, oldest first: all an AI needs to read it.
  Future<String> _export() async {
    final maker = await AlarmPermissions.manufacturer();
    return 'device=$maker os=${Platform.operatingSystemVersion}\n'
        '${_log.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限自检'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  '闹钟能响、但锁屏时屏幕不亮，多半是下面某一项没放行。改完回到这里会自动重新检测。',
                ),
                const _Header('可自动检测'),
                _StatusTile(
                  title: '通知',
                  body: '关闭后闹钟只有声音，没有通知，也不会亮屏弹出响铃页',
                  ok: report.notification,
                  onFix: () async {
                    await AlarmPermissions.requestNotification();
                    await _refresh();
                  },
                ),
                _StatusTile(
                  title: '精确闹钟',
                  body: '没有的话闹钟可能晚响几分钟',
                  ok: report.exactAlarm,
                  onFix: () async {
                    await AlarmPermissions.requestExactAlarm();
                    await _refresh();
                  },
                ),
                _StatusTile(
                  title: '全屏通知（Android 14+）',
                  body: '锁屏时亮屏并弹出响铃页需要它',
                  ok: report.fullScreenIntent,
                  onFix: AlarmPermissions.openFullScreenIntentSettings,
                ),
                _StatusTile(
                  title: '不受电池优化限制',
                  body: '部分手机会在后台拦截闹钟',
                  ok: report.batteryOptimizationIgnored,
                  onFix: () async {
                    await AlarmPermissions.requestIgnoreBatteryOptimizations();
                    await _refresh();
                  },
                ),
                const _Header('无法自动检测，请手动确认'),
                if (_xiaomi) ...[
                  _ManualTile(
                    title: '锁屏显示、后台弹出界面',
                    body: '在“其他权限”里都设为允许，不要选“每次询问”',
                    button: '打开权限页',
                    onTap: AlarmPermissions.openPermissionEditor,
                  ),
                  _ManualTile(
                    title: '自启动',
                    body: '打开本应用的开关',
                    button: '打开自启动页',
                    onTap: AlarmPermissions.openAutoStartSettings,
                  ),
                  _ManualTile(
                    title: '省电策略选“无限制”',
                    body: '不要选“智能限制”',
                    button: '打开省电策略页',
                    onTap: AlarmPermissions.openBatteryStrategySettings,
                  ),
                ],
                _ManualTile(
                  title: '通知渠道',
                  body: '在应用通知管理里找到闹钟渠道：锁屏通知选“显示全部内容”，悬浮通知和横幅打开，不要静默',
                  button: '打开应用设置',
                  onTap: AlarmPermissions.openAppSettings,
                ),
                if (_xiaomi)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('在最近任务里锁定本应用'),
                    subtitle: Text('锁定后一键清理不会杀掉它，闹钟才不会被取消'),
                  ),
                const _Header('诊断日志'),
                Text(
                  '只记缺失的权限、闹钟注册、响铃和前后台切换。复制时会带上手机型号和系统版本。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('复制日志'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: await _export()));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('已复制日志')),
                        );
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清空'),
                      onPressed: () async {
                        await AppLog.clear();
                        await _refresh();
                      },
                    ),
                  ],
                ),
                if (_log.isEmpty)
                  const Text('暂无日志')
                else
                  SelectableText(
                    // Newest first, so the latest alarm is at the top.
                    _log.reversed.take(60).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                const SizedBox(height: 8),
                const Text('全部设置好后，到“作息”页的调试里注册测试闹钟链，锁屏等 1 分钟确认会亮屏。'),
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.title,
    required this.body,
    required this.ok,
    required this.onFix,
  });

  final String title;
  final String body;
  final bool ok;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      ok ? Icons.check_circle : Icons.error,
      color: ok ? Colors.green : Colors.orange,
    ),
    title: Text(title),
    subtitle: Text(ok ? '已允许' : body),
    trailing: ok ? null : TextButton(onPressed: onFix, child: const Text('去设置')),
  );
}

class _ManualTile extends StatelessWidget {
  const _ManualTile({
    required this.title,
    required this.body,
    required this.button,
    required this.onTap,
  });

  final String title;
  final String body;
  final String button;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.help_outline),
    title: Text(title),
    subtitle: Text(body),
    trailing: TextButton(onPressed: onTap, child: Text(button)),
  );
}
