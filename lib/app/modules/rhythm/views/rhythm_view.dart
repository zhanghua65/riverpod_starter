import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/modules/rhythm/widgets/plan_setup.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// The RhythmCompass home tab: plan setup, today's schedule, progress and
/// the sleep log.
class RhythmView extends ConsumerStatefulWidget {
  const RhythmView();

  @override
  ConsumerState<RhythmView> createState() => _RhythmViewState();
}

class _RhythmViewState extends ConsumerState<RhythmView> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final rhythm = ref.watch(rhythmControllerProvider);
    return SafeArea(
      child: rhythm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (state) {
          final plan = state.plan;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (plan == null || _editing)
                PlanSetup(
                  initial: plan,
                  settings: state.settings,
                  onApply: _apply,
                  onCancel: plan == null
                      ? null
                      : () => setState(() => _editing = false),
                )
              else ...[
                _PlanOverview(plan: plan, log: state.log),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _recordLastNight(plan),
                  child: const Text('补记昨晚入睡时间'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('重新设定计划'),
                ),
                TextButton(
                  onPressed: _stopPlan,
                  child: const Text('停止计划并取消所有闹钟'),
                ),
              ],
              const Divider(height: 32),
              const _UpcomingAlarms(),
              const _BatteryOptimizationTile(),
              const _FullScreenIntentTile(),
              const _DebugPanel(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _apply(PlanConfig plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await AlarmPermissions.ensureGranted();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('缺少通知或精确闹钟权限，闹钟可能不准时')),
      );
    }
    final ok = await ref
        .read(rhythmControllerProvider.notifier)
        .applyPlan(plan);
    if (!mounted) return;
    setState(() => _editing = false);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '计划已开始' : '部分闹钟注册失败，请查看日志')),
    );
  }

  Future<void> _recordLastNight(PlanConfig plan) async {
    final now = DateTime.now();
    final night = DateTime(now.year, now.month, now.day - 1);
    final planned = plan.chainFor(night);
    final picked = await pickClockTime(
      context,
      planned == null ? plan.targetBedtime : ClockTime.of(planned.bedtime),
    );
    if (picked == null || !mounted) return;

    final at = DateTime(
      night.year,
      night.month,
      night.day + (picked.hour < 12 ? 1 : 0),
      picked.hour,
      picked.minute,
    );
    final recovery = await ref
        .read(rhythmControllerProvider.notifier)
        .confirmBedtime(night, at);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(recoveryMessage(recovery))));
  }

  Future<void> _stopPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止计划？'),
        content: const Text('会删除计划并取消所有已注册的闹钟，睡眠记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(rhythmControllerProvider.notifier).clearPlan();
    }
  }
}

/// What the user is told after recording a bedtime.
String recoveryMessage(Recovery recovery) {
  if (!recovery.isLate) return '已记录，按计划入睡，继续保持';
  final parts = ['晚了 ${recovery.lateBy.inMinutes} 分钟，没关系'];
  final wakeUp = recovery.wakeUp;
  if (wakeUp != null) parts.add('起床顺延到 ${hourMinute(wakeUp)}');
  final napAt = recovery.napAt;
  if (napAt != null) parts.add('${hourMinute(napAt)} 安排了午休胶囊');
  parts.add('从今晚起重新排了过渡计划');
  return parts.join('，');
}

class _PlanOverview extends StatelessWidget {
  const _PlanOverview({required this.plan, required this.log});

  final PlanConfig plan;
  final List<SleepLogEntry> log;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final transition = plan.transition;
    final next = plan
        .chainsFrom(DateTime(today.year, today.month, today.day - 1), 3)
        .where((c) => c.wakeUp.isAfter(now))
        .firstOrNull;
    final dayIndex = next == null
        ? -1
        : transition.indexWhere((c) => c.night == next.night);

    final streak = log.takeWhile((e) => e.lateBy < Recovery.grace).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '目标 ${plan.targetBedtime} 睡 · ${plan.targetWakeUp} 起',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          dayIndex >= 0
              ? '过渡期第 ${dayIndex + 1} / ${transition.length} 晚'
              : '已到达目标作息，每天按目标提醒',
        ),
        if (next != null)
          Card(
            child: ListTile(
              title: Text('${monthDay(next.night)} 这一晚'),
              subtitle: Text(chainSummary(next)),
            ),
          ),
        const SizedBox(height: 8),
        Text('连续按时入睡 $streak 晚'),
        for (final entry in log.take(7))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              entry.lateBy < Recovery.grace
                  ? Icons.check_circle
                  : Icons.bedtime,
              color: entry.lateBy < Recovery.grace
                  ? Colors.green
                  : Colors.orange,
            ),
            title: Text(monthDay(entry.night)),
            subtitle: Text(
              '计划 ${hourMinute(entry.plannedBedtime)} · '
              '实际 ${hourMinute(entry.actualBedtime)}',
            ),
          ),
      ],
    );
  }
}

class _UpcomingAlarms extends ConsumerWidget {
  const _UpcomingAlarms();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduled = ref.watch(scheduledAlarmsProvider).value?.alarms ?? {};
    final alarms = scheduled.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('已注册的闹钟（${alarms.length}）'),
      children: [
        for (final alarm in alarms.take(12))
          ListTile(
            dense: true,
            title: Text(alarm.notificationSettings.title),
            subtitle: Text(
              '${monthDay(alarm.dateTime)} ${hourMinute(alarm.dateTime)}',
            ),
          ),
      ],
    );
  }
}

class _BatteryOptimizationTile extends StatefulWidget {
  const _BatteryOptimizationTile();

  @override
  State<_BatteryOptimizationTile> createState() =>
      _BatteryOptimizationTileState();
}

class _BatteryOptimizationTileState extends State<_BatteryOptimizationTile> {
  bool? _ignored;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ignored = await AlarmPermissions.batteryOptimizationIgnored();
    if (mounted) setState(() => _ignored = ignored);
  }

  @override
  Widget build(BuildContext context) {
    if (_ignored != false) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.battery_alert, color: Colors.orange),
      title: const Text('关闭电池优化'),
      subtitle: const Text('部分手机会在后台拦截闹钟，建议允许本应用不受电池优化限制'),
      onTap: () async {
        await AlarmPermissions.requestIgnoreBatteryOptimizations();
        await _refresh();
      },
    );
  }
}

/// Asks for the full-screen notification permission, without which the
/// screen stays dark when an alarm rings on a locked phone (Android 14+).
class _FullScreenIntentTile extends StatefulWidget {
  const _FullScreenIntentTile();

  @override
  State<_FullScreenIntentTile> createState() => _FullScreenIntentTileState();
}

class _FullScreenIntentTileState extends State<_FullScreenIntentTile>
    with WidgetsBindingObserver {
  bool? _allowed;

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

  // Back from the system settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final allowed = await AlarmPermissions.fullScreenIntentAllowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed != false) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.screen_lock_portrait, color: Colors.orange),
      title: const Text('允许全屏通知'),
      subtitle: const Text('否则闹钟响铃时锁屏不会亮屏弹出提醒页'),
      onTap: AlarmPermissions.openFullScreenIntentSettings,
    );
  }
}

/// Registers a short chain for checking the alarms and the ring page.
class _DebugPanel extends ConsumerWidget {
  const _DebugPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('调试'),
      children: [
        const Text('1 分钟后降速准备，2 分钟后熄灯躺平，3 分钟后起床。会额外注册，不影响计划。'),
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await AlarmPermissions.ensureGranted();
            final now = DateTime.now();
            final ok = await ref
                .read(alarmServiceProvider)
                .scheduleChain(
                  AlarmChain(
                    // A night far in the past keeps the ids clear of the plan.
                    night: DateTime(2000, 1, 1),
                    windDown: now.add(const Duration(minutes: 1)),
                    bedtime: now.add(const Duration(minutes: 2)),
                    wakeUp: now.add(const Duration(minutes: 3)),
                  ),
                );
            messenger.showSnackBar(
              SnackBar(content: Text(ok ? '已注册测试闹钟链' : '注册失败，请查看日志')),
            );
          },
          child: const Text('注册测试闹钟链'),
        ),
      ],
    );
  }
}
