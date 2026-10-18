import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// Tunes the stepping plan and the anti-guilt recovery. A running plan is
/// rebuilt (and its alarms registered again) when a value changes.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rhythm = ref.watch(rhythmControllerProvider);
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
              _SliderTile(
                title: '每晚最多提前',
                unit: '分钟',
                value: settings.maxStepMinutes,
                min: RhythmSettings.stepRange.min,
                max: RhythmSettings.stepRange.max,
                step: 5,
                onChanged: (v) => update(settings.copyWith(maxStepMinutes: v)),
              ),
              _SliderTile(
                title: '过渡期最多',
                unit: '晚',
                value: settings.maxDays,
                min: RhythmSettings.daysRange.min,
                max: RhythmSettings.daysRange.max,
                step: 1,
                onChanged: (v) => update(settings.copyWith(maxDays: v)),
              ),
              _SliderTile(
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
                subtitle: const Text('晚睡后的第二天在这个时间提醒小睡 20 分钟'),
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
          );
        },
      ),
    );
  }
}

/// A slider that saves only when the user lets go.
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.title,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String title;
  final String unit;
  final int value;
  final int min;
  final int max;
  final int step;
  final Future<void> Function(int value) onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.title} ${value.round()} ${widget.unit}'),
        Slider(
          value: value,
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: (widget.max - widget.min) ~/ widget.step,
          label: '${value.round()}',
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) async {
            await widget.onChanged(v.round());
            if (mounted) setState(() => _dragging = null);
          },
        ),
      ],
    );
  }
}
