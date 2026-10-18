import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/sleep_stats.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// Sleep history: summary numbers, a bar per night for sleep length, and
/// the night-by-night list.
class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  /// Nights drawn as bars; older ones only count in the weekly list.
  static const _barNights = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(rhythmControllerProvider).valueOrNull?.log ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('睡眠历史')),
      body: log.isEmpty
          ? const Center(child: Text('还没有睡眠记录'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Summary(stats: SleepStats.of(log)),
                const SizedBox(height: 16),
                _DurationBars(log: log.take(_barNights).toList()),
                const SizedBox(height: 16),
                _WeeklyList(weeks: WeekStats.of(log)),
                const Divider(height: 32),
                for (final e in log) _NightTile(entry: e),
              ],
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats});

  final SleepStats stats;

  @override
  Widget build(BuildContext context) {
    final avg = stats.averageSleep;
    final late = stats.averageLateBy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(label: '平均睡眠', value: avg == null ? '—' : durationText(avg)),
            _Stat(
              label: '按时入睡',
              value: '${stats.onTimeNights}/${stats.nights} 晚',
            ),
            _Stat(
              label: '平均入睡',
              value: late == null
                  ? '—'
                  : late.inMinutes.abs() < 1
                  ? '准点'
                  : '${late.isNegative ? '早' : '晚'} ${late.inMinutes.abs()} 分',
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _WeeklyList extends StatelessWidget {
  const _WeeklyList({required this.weeks});

  final List<WeekStats> weeks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每周汇总', style: Theme.of(context).textTheme.titleSmall),
        for (final w in weeks)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${monthDay(w.monday)} 起的一周',
            ),
            subtitle: Text(
              '按时入睡 ${w.stats.onTimeNights}/${w.stats.nights} 晚',
            ),
            trailing: Text(
              w.stats.averageSleep == null
                  ? '—'
                  : '平均 ${durationText(w.stats.averageSleep!)}',
            ),
          ),
      ],
    );
  }
}

/// One bar per night (oldest on the left); the line marks 7.5 hours.
class _DurationBars extends StatelessWidget {
  const _DurationBars({required this.log});

  final List<SleepLogEntry> log;

  static const _maxHours = 10.0;
  static const _goalHours = 7.5;
  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final nights = log.reversed.toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('睡眠时长（虚线 7.5 小时）', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: _height * _goalHours / _maxHours,
                child: Divider(height: 1, color: scheme.outline),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in nights)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${monthDay(e.night)} '
                            '${e.sleepDuration == null ? '无时长' : durationText(e.sleepDuration!)}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Container(
                            height: _height *
                                ((e.sleepDuration?.inMinutes ?? 0) / 60)
                                    .clamp(0, _maxHours) /
                                _maxHours,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(monthDay(nights.first.night),
                style: Theme.of(context).textTheme.bodySmall),
            Text(monthDay(nights.last.night),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _NightTile extends StatelessWidget {
  const _NightTile({required this.entry});

  final SleepLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final onTime = entry.lateBy < Recovery.grace;
    final slept = entry.sleepDuration;
    final wake = entry.actualWakeUp;
    return ListTile(
      dense: true,
      leading: Icon(
        onTime ? Icons.check_circle : Icons.bedtime,
        color: onTime ? Colors.green : Colors.orange,
      ),
      title: Text('${monthDay(entry.night)} ${weekdayName(entry.night)}'),
      subtitle: Text(
        '入睡 ${hourMinute(entry.actualBedtime)}'
        '${wake == null ? '' : ' → 起床 ${hourMinute(wake)}'}'
        '${onTime ? '' : ' · 晚了 ${entry.lateBy.inMinutes} 分'}',
      ),
      trailing: Text(slept == null ? '—' : durationText(slept)),
    );
  }
}
