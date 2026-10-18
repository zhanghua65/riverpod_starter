import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/core/services/schedule/work_schedule.dart';
import '/app/modules/rhythm/widgets/time_format.dart';
import 'slider_tile.dart';

/// Work days and hours: keeps a postponed wake-up on time for work, puts
/// the nap capsule in the lunch break and feeds the AI advisor.
class WorkScheduleSection extends ConsumerWidget {
  const WorkScheduleSection({super.key, required this.work});

  final WorkSchedule? work;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = this.work;
    Future<void> update(WorkSchedule? next) =>
        ref.read(rhythmControllerProvider.notifier).updateWork(next);

    Widget time(
      String title,
      ClockTime value,
      WorkSchedule Function(ClockTime) apply,
    ) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Text('$value', style: const TextStyle(fontSize: 18)),
      onTap: () async {
        final picked = await pickClockTime(context, value);
        if (picked != null) await update(apply(picked));
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('工作作息'),
          subtitle: const Text('晚睡后顺延起床不会让你迟到，午休胶囊放进午休时间，AI 建议也会参考'),
          value: work != null,
          onChanged: (on) => update(on ? const WorkSchedule() : null),
        ),
        if (work != null) ...[
          Wrap(
            spacing: 6,
            children: [
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                FilterChip(
                  label: Text('周${_weekdays[day - 1]}'),
                  selected: work.workdays.contains(day),
                  onSelected: (on) => update(
                    work.copyWith(
                      workdays: on
                          ? {...work.workdays, day}
                          : ({...work.workdays}..remove(day)),
                    ),
                  ),
                ),
            ],
          ),
          time('上班时间', work.start, (t) => work.copyWith(start: t)),
          time('下班时间', work.end, (t) => work.copyWith(end: t)),
          time('午休开始', work.lunchStart, (t) => work.copyWith(lunchStart: t)),
          time('午休结束', work.lunchEnd, (t) => work.copyWith(lunchEnd: t)),
          SliderTile(
            title: '起床到上班（洗漱+通勤）',
            unit: '分钟',
            value: work.morningMinutes,
            min: WorkSchedule.morningRange.min,
            max: WorkSchedule.morningRange.max,
            step: 5,
            onChanged: (v) => update(work.copyWith(morningMinutes: v)),
          ),
          Text(
            '工作日最晚 ${work.latestWakeUp} 起床，午休胶囊在 ${work.napTime}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
