import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/modules/rhythm/widgets/time_format.dart';
import '/app/modules/settings/widgets/ai_settings_section.dart';
import '/app/modules/settings/widgets/slider_tile.dart';
import '/app/modules/settings/widgets/work_schedule_section.dart';

/// Tunes the stepping plan and the anti-guilt recovery, and holds the work
/// schedule and the AI advisor's endpoint. A running plan is rebuilt (and
/// its alarms registered again) when a plan setting changes.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rhythm = ref.watch(rhythmControllerProvider);
    final ai = ref.watch(aiConfigProvider).value;
    return SafeArea(
      child: rhythm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (state) {
          final settings = state.settings;
          Future<void> update(RhythmSettings next) => ref
              .read(rhythmControllerProvider.notifier)
              .updateSettings(next);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '设置',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (state.plan != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('修改后会按新的设置重排当前计划并重新注册闹钟。'),
                ),
              const SizedBox(height: 8),
              SliderTile(
                title: '每晚最多提前',
                unit: '分钟',
                value: settings.maxStepMinutes,
                min: RhythmSettings.stepRange.min,
                max: RhythmSettings.stepRange.max,
                step: 5,
                onChanged: (v) => update(settings.copyWith(maxStepMinutes: v)),
              ),
              SliderTile(
                title: '过渡期最多',
                unit: '晚',
                value: settings.maxDays,
                min: RhythmSettings.daysRange.min,
                max: RhythmSettings.daysRange.max,
                step: 1,
                onChanged: (v) => update(settings.copyWith(maxDays: v)),
              ),
              SliderTile(
                title: '降速准备提前',
                unit: '分钟',
                value: settings.windDownLeadMinutes,
                min: RhythmSettings.windDownRange.min,
                max: RhythmSettings.windDownRange.max,
                step: 5,
                onChanged: (v) =>
                    update(settings.copyWith(windDownLeadMinutes: v)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('午休胶囊时间'),
                subtitle: Text(
                  state.work == null
                      ? '晚睡后的第二天在这个时间提醒小睡 20 分钟'
                      : '晚睡后的第二天提醒小睡 20 分钟；工作日改在午休时间',
                ),
                trailing: Text(
                  settings.napTime.toString(),
                  style: const TextStyle(fontSize: 18),
                ),
                onTap: () async {
                  final picked = await pickClockTime(context, settings.napTime);
                  if (picked != null) await update(settings.copyWith(napTime: picked));
                },
              ),
              const Divider(height: 32),
              WorkScheduleSection(work: state.work),
              const Divider(height: 32),
              if (ai != null) AiSettingsSection(config: ai),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('重新查看使用引导'),
                subtitle: const Text('权限、电池优化和锁屏弹出设置'),
                onTap: () =>
                    ref.read(onboardingProvider.notifier).setDone(false),
              ),
            ],
          );
        },
      ),
    );
  }
}
