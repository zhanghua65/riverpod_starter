import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/base/base_view.dart';
import '/app/core/di/controller_provider.dart';
import '/app/core/utils/wake_time_recommender.dart';
import '/app/modules/settings/controllers/settings_controller.dart';

class SettingsView extends BaseView<SettingsController> {
  @override
  PreferredSizeWidget? appBar(BuildContext context) {
    return null;
  }

  @override
  Widget body(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final c = ref.watch(controller);

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('目标就寝时间'),
            trailing: Text(c.bedtime.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: c.bedtime,
              );
              if (picked != null) c.setBedtime(picked);
            },
          ),
          ListTile(
            title: const Text('目标起床时间'),
            subtitle: Text(c.isWakeTimeRecommended ? '已采用推荐' : '手动设置'),
            trailing: Text(c.wakeTime.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: c.wakeTime,
              );
              if (picked != null) c.setWakeTime(picked);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('推荐起床时间(按 90 分钟睡眠周期)'),
          ),
          for (final r in c.recommendations) _recommendationTile(context, c, r),
        ],
      );
    });
  }

  Widget _recommendationTile(
      BuildContext context, SettingsController c, WakeTimeRecommendation r) {
    final time = TimeOfDay(hour: r.wakeTime.hour, minute: r.wakeTime.minute);
    final hours = r.sleepDuration.inMinutes / 60;

    return ListTile(
      title: Text(time.format(context)),
      subtitle: Text('${r.cycles} 个周期,约 $hours 小时${r.isPrimary ? ' · 推荐' : ''}'),
      trailing: TextButton(
        onPressed: () => c.setWakeTime(time),
        child: const Text('采用'),
      ),
    );
  }

  @override
  ProviderBase<SettingsController> get controller => settingsControllerProvider;
}
