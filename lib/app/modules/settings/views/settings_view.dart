import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/modules/rhythm/widgets/time_format.dart';
import '/app/routes/app_routes.dart';
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                '设置',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              if (state.plan != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('修改后会按新的设置重排当前计划并重新注册闹钟。'),
                ),
              const SizedBox(height: 8),
              const _SectionTitle('作息节奏'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                    ],
                  ),
                ),
              ),
              const _SectionTitle('工作'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: WorkScheduleSection(work: state.work),
                ),
              ),
              if (ai != null) ...[
                const _SectionTitle('AI 顾问'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AiSettingsSection(config: ai),
                  ),
                ),
              ],
              const _SectionTitle('其他'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: const Text('权限自检'),
                      subtitle: const Text('闹钟不亮屏、不响时，检查通知、全屏通知等是否放行'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Paths.PERMISSIONS),
                    ),
                    ListTile(
                      leading: const Icon(Icons.watch_outlined),
                      title: const Text('手环睡眠数据'),
                      subtitle: const Text('查看 Health Connect 里同步到的睡眠记录'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Paths.BAND_SLEEP),
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('重新查看使用引导'),
                      subtitle: const Text('权限、电池优化和锁屏弹出设置'),
                      onTap: () =>
                          ref.read(onboardingProvider.notifier).setDone(false),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
