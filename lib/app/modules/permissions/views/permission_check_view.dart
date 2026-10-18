import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/app/core/utils/app_log.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/modules/permissions/widgets/permission_checklist.dart';

/// The one place for everything the alarm chain needs from the phone (the
/// list itself is [PermissionChecklist]), plus the diagnostic log.
class PermissionCheckView extends StatefulWidget {
  const PermissionCheckView({super.key});

  @override
  State<PermissionCheckView> createState() => _PermissionCheckViewState();
}

class _PermissionCheckViewState extends State<PermissionCheckView>
    with WidgetsBindingObserver {
  List<String> _log = const [];
  int _checkRound = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from a system settings page: the checklist rereads its statuses,
  // this page rereads the log.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final log = await AppLog.read();
    if (mounted) setState(() => _log = log);
  }

  /// Device line plus the log, oldest first: all an AI needs to read it.
  Future<String> _export() async {
    final maker = await AlarmPermissions.manufacturer();
    return 'device=$maker os=${Platform.operatingSystemVersion}\n'
        '${_log.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限自检'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // A new key makes the checklist read its statuses again.
              setState(() => _checkRound++);
              _refresh();
            },
          ),
        ],
      ),
      body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  '闹钟能响、但锁屏时屏幕不亮，多半是下面某一项没放行。改完回到这里会自动重新检测。',
                ),
                PermissionChecklist(key: ValueKey(_checkRound)),
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text('诊断日志', style: Theme.of(context).textTheme.titleSmall),
                ),
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
