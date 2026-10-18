import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/core/services/usage/health_sleep.dart';

/// What the alarms need from the phone, in one place: the settings the app can
/// read show a real status, the vendor switches only link to their page.
///
/// Used by the permission check page and the first-use guide, so the list of
/// permissions is defined only here.
class PermissionChecklist extends ConsumerStatefulWidget {
  const PermissionChecklist({super.key});

  @override
  ConsumerState<PermissionChecklist> createState() =>
      _PermissionChecklistState();
}

class _PermissionChecklistState extends ConsumerState<PermissionChecklist>
    with WidgetsBindingObserver {
  AlarmPermissionReport? _report;
  bool? _usageAccess;
  HealthSleepStatus? _health;
  bool _xiaomi = false;

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
    final usage = Alarm.android
        ? await ref.read(screenUsageProvider).hasAccess()
        : null;
    final health = Alarm.android
        ? await ref.read(healthSleepProvider).status()
        : null;
    if (!mounted) return;
    setState(() {
      _report = report;
      _usageAccess = usage;
      _health = health;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    if (report == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (_usageAccess != null)
          _StatusTile(
            title: '使用情况访问（可选）',
            body: '允许后用每晚最后一次熄屏的时间当作入睡时间，忘了点“我已躺下”也能记上。只在本机读取',
            ok: _usageAccess!,
            onFix: () => ref.read(screenUsageProvider).openSettings(),
          ),
        if (_health != null) _bandTile(_health!),
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
            subtitle: Text('小米/红米划掉应用会取消闹钟；锁定后一键清理不会杀掉它'),
          )
        else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('睡前不要划掉本应用'),
            subtitle: Text('部分手机从最近任务清掉应用后，闹钟会失效'),
          ),
      ],
    );
  }

  /// Reading the band's sleep from Health Connect. The band app must also
  /// sync to Health Connect, which the app cannot check, so the tile links
  /// there once access is granted.
  Widget _bandTile(HealthSleepStatus status) {
    final health = ref.read(healthSleepProvider);
    const title = '手环睡眠数据（可选）';
    switch (status) {
      case HealthSleepStatus.unavailable:
        return const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.watch_outlined),
          title: Text(title),
          subtitle: Text('本机没有 Health Connect（健康数据共享），无法读取手环数据'),
        );
      case HealthSleepStatus.needsUpdate:
        return _StatusTile(
          title: title,
          body: '需要先更新 Health Connect',
          ok: false,
          onFix: () async {
            await health.requestAccess();
          },
        );
      case HealthSleepStatus.denied:
        return _StatusTile(
          title: title,
          body: '允许读取睡眠后，用小米手环记录的入睡和醒来时间代替熄屏推算。只在本机读取',
          ok: false,
          onFix: () async {
            // Health Connect stops showing the dialog after two refusals.
            if (!await health.requestAccess()) await health.openSettings();
            await _refresh();
          },
        );
      case HealthSleepStatus.granted:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: const Text(title),
          subtitle: const Text(
            '已允许。还需在小米运动健康（Mi Fitness）里打开“同步到 Health Connect”的睡眠数据，手环同步后才读得到',
          ),
          trailing: TextButton(
            onPressed: () async {
              if (!await health.openBandApp()) await health.openSettings();
            },
            child: const Text('去打开同步'),
          ),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
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
