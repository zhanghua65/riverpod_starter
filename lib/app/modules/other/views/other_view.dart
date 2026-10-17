import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/base/base_view.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/di/controller_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/modules/other/controllers/other_controller.dart';

/// Temporary test page for the alarm chain, until the scheduling UI exists.
class OtherView extends BaseView<OtherController> {
  @override
  PreferredSizeWidget? appBar(BuildContext context) {
    return null;
  }

  @override
  Widget body(BuildContext context) {
    return const _AlarmTestPanel();
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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
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
          TextButton(
            onPressed: service.stopAll,
            child: const Text('取消全部闹钟'),
          ),
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
      ),
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
