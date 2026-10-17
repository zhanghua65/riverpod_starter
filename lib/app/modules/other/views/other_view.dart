import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/base/base_view.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/di/controller_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/modules/other/controllers/other_controller.dart';

/// Stepping plan setup plus the alarm chain test tools.
class OtherView extends BaseView<OtherController> {
  @override
  PreferredSizeWidget? appBar(BuildContext context) {
    return null;
  }

  @override
  Widget body(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [_PlanPanel(), Divider(height: 32), _AlarmTestPanel()],
      ),
    );
  }

  @override
  ProviderBase<OtherController> get controller => otherControllerProvider;
}

class _AlarmTestPanel extends ConsumerWidget {
  const _AlarmTestPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduled = ref.watch(scheduledAlarmsProvider).value?.alarms ?? {};
    final ringing = ref.watch(ringingAlarmsProvider).value?.alarms ?? {};
    final service = ref.read(alarmServiceProvider);
    final alarms = scheduled.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '闹钟链测试',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('注册一条测试链：1 分钟后降速准备，2 分钟后熄灯躺平，3 分钟后起床（音量阶梯递增）。'),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _scheduleTestChain(context, ref),
          child: const Text('注册测试闹钟链'),
        ),
        if (ringing.isNotEmpty)
          ElevatedButton(
            onPressed: () {
              for (final alarm in ringing) {
                service.stop(alarm.id);
              }
            },
            child: const Text('停止正在响的闹钟'),
          ),
        TextButton(onPressed: service.stopAll, child: const Text('取消全部闹钟')),
        const Divider(),
        Text('已注册 ${alarms.length} 个'),
        for (final alarm in alarms)
          ListTile(
            title: Text(alarm.notificationSettings.title),
            subtitle: Text('${alarm.dateTime}  id=${alarm.id}'),
            trailing: ringing.any((r) => r.id == alarm.id)
                ? const Icon(Icons.alarm_on)
                : null,
          ),
      ],
    );
  }

  Future<void> _scheduleTestChain(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await AlarmPermissions.ensureGranted();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('缺少通知或精确闹钟权限，闹钟可能不准时')),
      );
    }

    final now = DateTime.now();
    final chain = AlarmChain(
      windDown: now.add(const Duration(minutes: 1)),
      bedtime: now.add(const Duration(minutes: 2)),
      wakeUp: now.add(const Duration(minutes: 3)),
    );
    final ok = await ref.read(alarmServiceProvider).scheduleChain(chain);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '已注册测试闹钟链' : '注册失败，请查看日志')),
    );
  }
}

/// Lets the user enter the current and target schedule, previews the
/// stepping plan and registers it as alarms.
class _PlanPanel extends ConsumerStatefulWidget {
  const _PlanPanel();

  @override
  ConsumerState<_PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends ConsumerState<_PlanPanel> {
  ClockTime _currentBedtime = const ClockTime(1, 30);
  ClockTime _currentWakeUp = const ClockTime(9, 30);
  ClockTime _targetBedtime = const ClockTime(23, 0);
  ClockTime _targetWakeUp = const ClockTime(7, 0);

  List<AlarmChain>? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rebuildPlan();
  }

  void _rebuildPlan() {
    final today = DateTime.now();
    try {
      _plan = SteppingPlan.build(
        currentBedtime: _currentBedtime,
        currentWakeUp: _currentWakeUp,
        targetBedtime: _targetBedtime,
        targetWakeUp: _targetWakeUp,
        firstNight: DateTime(today.year, today.month, today.day),
      );
      _error = null;
    } on ArgumentError {
      _plan = null;
      _error = '就寝时间必须早于第二天的起床时间';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '渐进作息计划',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('每天最多前推 30 分钟，最后一晚到达目标。'),
        _timeTile('现在几点睡', _currentBedtime, (t) => _currentBedtime = t),
        _timeTile('现在几点起', _currentWakeUp, (t) => _currentWakeUp = t),
        _timeTile('目标就寝', _targetBedtime, (t) => _targetBedtime = t),
        _timeTile('目标起床', _targetWakeUp, (t) => _targetWakeUp = t),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (plan != null) ...[
          const SizedBox(height: 8),
          Text('共 ${plan.length} 晚'),
          for (var i = 0; i < plan.length; i++)
            ListTile(
              dense: true,
              title: Text('第 ${i + 1} 晚  ${_md(plan[i].night)}'),
              subtitle: Text(
                '降速 ${_hm(plan[i].windDown)} · '
                '熄灯 ${_hm(plan[i].bedtime)} · '
                '起床 ${_hm(plan[i].wakeUp)}',
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _apply(plan),
            child: const Text('应用计划（替换现有闹钟）'),
          ),
        ],
      ],
    );
  }

  Widget _timeTile(
    String label,
    ClockTime value,
    void Function(ClockTime) onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value.toString(), style: const TextStyle(fontSize: 18)),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
        );
        if (picked == null) return;
        setState(() {
          onChanged(ClockTime(picked.hour, picked.minute));
          _rebuildPlan();
        });
      },
    );
  }

  Future<void> _apply(List<AlarmChain> plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await AlarmPermissions.ensureGranted();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('缺少通知或精确闹钟权限，闹钟可能不准时')),
      );
    }
    final ok = await ref.read(alarmServiceProvider).replaceAll(plan);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '已注册 ${plan.length} 晚的闹钟' : '部分闹钟注册失败，请查看日志'),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _md(DateTime t) => '${t.month}月${t.day}日';
}
