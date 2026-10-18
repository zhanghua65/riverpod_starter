import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_stage.dart';
import '/app/core/values/app_colors.dart';
import '/app/modules/rhythm/views/rhythm_view.dart';
import '/app/modules/rhythm/widgets/time_format.dart';
import '/app/routes/app_routes.dart';

/// Full-screen page shown while an alarm rings, also over the lock screen
/// (the alarms use `androidFullScreenIntent`).
///
/// It stays until the user picks an action, even after a non-looping
/// reminder has finished playing, so the wind-down prompt actually
/// interrupts whatever was on screen.
class RingView extends ConsumerStatefulWidget {
  const RingView({required this.alarm});

  final AlarmSettings alarm;

  @override
  ConsumerState<RingView> createState() => _RingViewState();
}

class _RingViewState extends ConsumerState<RingView> {
  bool _busy = false;

  int get _id => widget.alarm.id;
  AlarmStage? get _stage => AlarmChain.stageOf(_id);
  DateTime get _night => AlarmChain.nightOf(_id);

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.colorDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  hourMinute(DateTime.now()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.alarm.notificationSettings.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _hint(stage),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const Spacer(),
                ..._actions(stage),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _hint(AlarmStage? stage) {
    switch (stage) {
      case AlarmStage.windDown:
        final bedtime = ref
            .read(rhythmControllerProvider)
            .value
            ?.plan
            ?.chainFor(_night)
            ?.bedtime;
        final left = bedtime?.difference(DateTime.now()).inMinutes;
        final steps = '1. 退出短视频，把手机放到床外\n2. 洗漱、上厕所\n3. 把灯调暗';
        return left != null && left > 0 ? '离熄灯还有 $left 分钟\n\n$steps' : steps;
      case AlarmStage.bedtime:
        return '关灯躺下。躺下后点“我已躺下”，晚了也没关系，明天会自动调整。';
      case AlarmStage.wakeUp:
        return '拉开窗帘，让光线进来。';
      case AlarmStage.nap:
        return '找个安静的地方，闭眼 20 分钟，到点会叫你。';
      case AlarmStage.napWake:
      case null:
        return widget.alarm.notificationSettings.body;
    }
  }

  List<Widget> _actions(AlarmStage? stage) {
    final controller = ref.read(rhythmControllerProvider.notifier);
    final comfort = ref.read(comfortProvider.notifier);
    switch (stage) {
      case AlarmStage.windDown:
        return [_primary('好，我放下手机', () async => null)];
      case AlarmStage.bedtime:
        return [
          _primary('我已躺下', () async {
            final recovery = await controller.confirmBedtime(
              _night,
              DateTime.now(),
            );
            // Not awaited: the page closes now and the advisor's kind
            // words show up on the home page when they arrive.
            comfort.requestFor(_night, recovery);
            return recoveryMessage(recovery);
          }),
          _secondary('再给我 15 分钟', () async {
            await controller.snooze(_night);
            return '15 分钟后再提醒你';
          }),
        ];
      case AlarmStage.wakeUp:
        return [_primary('我醒了', () async => null)];
      case AlarmStage.nap:
        return [
          _primary('开始午休 20 分钟', () async {
            await controller.startNap(_night);
            return '20 分钟后叫你';
          }),
          _secondary('今天不睡了', () async => null),
        ];
      case AlarmStage.napWake:
      case null:
        return [_primary('停止', () async => null)];
    }
  }

  Widget _primary(String label, Future<String?> Function() action) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: _busy ? null : () => _finish(action),
      child: Text(label),
    ),
  );

  Widget _secondary(String label, Future<String?> Function() action) =>
      TextButton(
        onPressed: _busy ? null : () => _finish(action),
        child: Text(label, style: const TextStyle(color: Colors.white70)),
      );

  /// Stops the alarm, runs [action] and closes the page, showing the
  /// message [action] returns.
  Future<void> _finish(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(alarmServiceProvider).stop(_id);
    final message = await action();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Paths.LANDING);
    }
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
