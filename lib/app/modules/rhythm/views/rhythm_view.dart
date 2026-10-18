import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/core/values/app_values.dart';
import '/app/routes/app_routes.dart';
import '/app/modules/rhythm/widgets/advisor_card.dart';
import '/app/modules/rhythm/widgets/plan_setup.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// The RhythmCompass home tab: plan setup, today's schedule, progress and
/// the sleep log.
class RhythmView extends ConsumerStatefulWidget {
  const RhythmView();

  @override
  ConsumerState<RhythmView> createState() => _RhythmViewState();
}

class _RhythmViewState extends ConsumerState<RhythmView>
    with WidgetsBindingObserver {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordFromScreen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Opened in the morning, or back from granting usage access.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recordFromScreen();
  }

  /// Fills in last night's bedtime and wake-up from the screen's history.
  Future<void> _recordFromScreen() async {
    final record = await ref
        .read(rhythmControllerProvider.notifier)
        .recordFromScreen(throttled: true);
    if (record == null) return;
    // Best effort; the kind words show up on this page when they arrive.
    final recovery = record.recovery;
    if (recovery != null) {
      ref.read(comfortProvider.notifier).requestFor(record.night, recovery);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(screenRecordMessage(record))));
  }

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                AdvisorCard(plan: plan, log: state.log),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => _recordLastNight(plan),
                  child: const Text('补记昨晚入睡时间'),
                ),
                const SizedBox(height: 8),
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
              const _PermissionBanner(),
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
    // Best effort; the kind words show up on this page when they arrive.
    ref.read(comfortProvider.notifier).requestFor(night, recovery);
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

String screenRecordMessage(ScreenRecord record) {
  final parts = <String>[];
  final bedtime = record.bedtime;
  final recovery = record.recovery;
  if (bedtime != null) {
    final off = record.fromBand
        ? '手环记录昨晚 ${hourMinute(bedtime)} 入睡'
        : '昨晚 ${hourMinute(bedtime)} 熄屏，已记为入睡时间';
    if (recovery == null) {
      // The band replaced a screen-off time recorded earlier.
      if (record.fromBand) parts.add('$off，已更新记录');
    } else {
      parts.add(
        recovery.isLate
            ? '$off。${recoveryMessage(recovery)}'
            : '$off，按计划入睡，继续保持',
      );
    }
  }
  final wakeUp = record.wakeUp;
  if (wakeUp != null) {
    parts.add(
      record.fromBand
          ? '手环记录今早 ${hourMinute(wakeUp)} 醒来，已记为起床时间'
          : '今早 ${hourMinute(wakeUp)} 开始用手机，已记为起床时间',
    );
  }
  return parts.join('\n');
}

/// The plan's headline: target times, transition progress and the streak.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.progress,
    required this.fraction,
    required this.streak,
  });

  final String title;
  final String progress;
  final double fraction;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppValues.largeRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF38686A), Color(0xFF5A8F8C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(progress, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '连续按时入睡 $streak 晚',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
        _HeroCard(
          title: '目标 ${plan.targetBedtime} 睡 · ${plan.targetWakeUp} 起',
          progress: dayIndex >= 0
              ? '过渡期第 ${dayIndex + 1} / ${transition.length} 晚'
              : '已到达目标作息，每天按目标提醒',
          fraction: dayIndex >= 0 && transition.isNotEmpty
              ? (dayIndex + 1) / transition.length
              : 1,
          streak: streak,
        ),
        _LastNightCard(log: log),
        if (next != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.nights_stay_outlined),
              title: Text(
                plan.overrides.containsKey(next.night)
                    ? '${monthDay(next.night)} 这一晚（临时作息）'
                    : '${monthDay(next.night)} 这一晚',
              ),
              subtitle: Text(chainSummary(next)),
            ),
          ),
        const SizedBox(height: 8),
        for (final entry in log.take(7))
          ListTile(
            dense: true,
            leading: Icon(
              entry.lateBy < Recovery.grace
                  ? Icons.check_circle
                  : Icons.bedtime,
              color: entry.lateBy < Recovery.grace
                  ? Colors.green
                  : Colors.orange,
            ),
            title: Text(monthDay(entry.night)),
            subtitle: Text(_logLine(entry)),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => _EditEntrySheet(night: entry.night),
            ),
          ),
      ],
    );
  }
}

String _logLine(SleepLogEntry entry) {
  final bedSource = switch (entry.source) {
    BedtimeSource.screen => '（熄屏）',
    BedtimeSource.band => '（手环）',
    BedtimeSource.manual => '',
  };
  final wakeUp = entry.actualWakeUp;
  final wakeSource = switch (entry.wakeUpSource) {
    BedtimeSource.screen => '（亮屏）',
    BedtimeSource.band => '（手环）',
    BedtimeSource.manual => '',
  };
  final woke = wakeUp == null ? '' : ' · 起床 ${hourMinute(wakeUp)}$wakeSource';
  final slept = entry.sleepDuration;
  final length = slept == null ? '' : ' · 睡了 ${durationText(slept)}';
  return '计划 ${hourMinute(entry.plannedBedtime)} · '
      '实际 ${hourMinute(entry.actualBedtime)}$bedSource$woke$length';
}

/// Last night's sleep at a glance: bedtime, wake-up, length and how it
/// compares with the plan. Shown every day so the answer is one glance away.
class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.log});

  final List<SleepLogEntry> log;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastNight = DateTime(now.year, now.month, now.day - 1);
    final entry = log
        .where(
          (e) =>
              e.night.year == lastNight.year &&
              e.night.month == lastNight.month &&
              e.night.day == lastNight.day,
        )
        .firstOrNull;

    final String headline;
    final String detail;
    if (entry == null) {
      headline = '昨晚还没有睡眠记录';
      detail = '可在权限自检页开启自动记录，也可以点下方“补记昨晚入睡时间”';
    } else {
      final slept = entry.sleepDuration;
      final wake = entry.actualWakeUp;
      headline = slept == null
          ? '昨晚 ${hourMinute(entry.actualBedtime)} 入睡'
          : '昨晚睡了 ${durationText(slept)}';
      final lines = <String>[
        '入睡 ${hourMinute(entry.actualBedtime)}'
            '${wake == null ? '，起床时间还没记录' : ' → 起床 ${hourMinute(wake)}'}',
        entry.lateBy < Recovery.grace
            ? '按计划入睡，继续保持'
            : '比计划晚了 ${entry.lateBy.inMinutes} 分钟',
        if (slept != null) sleepSummary(slept),
      ];
      detail = lines.join('\n');
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bedtime_outlined),
        title: Text(headline),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Paths.HISTORY),
      ),
    );
  }
}

/// Lets the user correct the bedtime and wake-up recorded for [night].
class _EditEntrySheet extends ConsumerWidget {
  const _EditEntrySheet({required this.night});

  final DateTime night;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref
        .watch(rhythmControllerProvider)
        .value
        ?.log
        .where((e) => e.night == night)
        .firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final wakeUp = entry.actualWakeUp;

    Future<void> edit({ClockTime? bedtime, ClockTime? wakeUp}) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(rhythmControllerProvider.notifier)
            .editEntry(night, bedtime: bedtime, wakeUp: wakeUp);
      } on ArgumentError {
        messenger.showSnackBar(const SnackBar(content: Text('起床时间要晚于入睡时间')));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '修改 ${monthDay(night)} 的记录',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('只修改记录，不会改动闹钟和计划；改过的时间不会再被自动记录覆盖。'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('实际入睡'),
              subtitle: Text(switch (entry.source) {
                BedtimeSource.screen => '按熄屏时间自动记录',
                BedtimeSource.band => '按手环记录的入睡时间',
                BedtimeSource.manual => '手动记录',
              }),
              trailing: Text(
                hourMinute(entry.actualBedtime),
                style: const TextStyle(fontSize: 18),
              ),
              onTap: () async {
                final picked = await pickClockTime(
                  context,
                  ClockTime.of(entry.actualBedtime),
                );
                if (picked != null) await edit(bedtime: picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('实际起床'),
              subtitle: Text(
                wakeUp == null
                    ? '还没有记录，点击补记'
                    : switch (entry.wakeUpSource) {
                        BedtimeSource.screen => '按早上亮屏超过 10 分钟自动记录',
                        BedtimeSource.band => '按手环记录的醒来时间',
                        BedtimeSource.manual => '手动记录',
                      },
              ),
              trailing: Text(
                wakeUp == null ? '--:--' : hourMinute(wakeUp),
                style: const TextStyle(fontSize: 18),
              ),
              onTap: () async {
                final picked = await pickClockTime(
                  context,
                  wakeUp == null
                      ? ClockTime.of(
                          entry.plannedBedtime.add(const Duration(hours: 8)),
                        )
                      : ClockTime.of(wakeUp),
                );
                if (picked != null) await edit(wakeUp: picked);
              },
            ),
          ],
        ),
      ),
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

/// Points to the permission page while something the alarms need is missing.
class _PermissionBanner extends StatefulWidget {
  const _PermissionBanner();

  @override
  State<_PermissionBanner> createState() => _PermissionBannerState();
}

class _PermissionBannerState extends State<_PermissionBanner>
    with WidgetsBindingObserver {
  bool _missing = false;

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
    final report = await AlarmPermissions.check();
    if (mounted) setState(() => _missing = !report.allGranted);
  }

  @override
  Widget build(BuildContext context) {
    if (!_missing) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.error, color: Colors.orange),
      title: const Text('有权限还没放行'),
      subtitle: const Text('闹钟可能不准时，或锁屏时不亮屏。点此到权限自检里处理'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await context.push(Paths.PERMISSIONS);
        await _refresh();
      },
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
        const Text(
          '1 分钟后降速准备，2 分钟后熄灯躺平，3 分钟后起床。会额外注册，不影响计划。'
          '测试前请先锁屏，并确认已允许“锁屏显示”和“后台弹出界面”，否则只会响不会亮屏。',
        ),
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
