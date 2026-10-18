import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/ai/chat_client.dart';
import '/app/core/services/ai/rhythm_advisor.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// The AI advisor on the home page: kind words after a late night, the
/// weekly review, one-off adjustments and the one-off nights ahead.
class AdvisorCard extends ConsumerWidget {
  const AdvisorCard({super.key, required this.plan, required this.log});

  final PlanConfig plan;
  final List<SleepLogEntry> log;

  /// Comfort is shown until this long after the late night's date, i.e.
  /// all through the following day.
  static const comfortShownFor = Duration(days: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(aiConfigProvider).value;
    final comfort = ref.watch(comfortProvider).value;
    final reviewedAt = ref.watch(reviewedAtProvider).value;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final oneOffs =
        plan.overrides.entries.where((e) => !e.key.isBefore(today)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final showComfort =
        comfort != null && now.difference(comfort.night) < comfortShownFor;
    final reviewDue =
        log.length >= AdvisorController.minNightsToReview &&
        (reviewedAt == null ||
            now.difference(reviewedAt) >= AdvisorController.reviewEvery);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 20),
                SizedBox(width: 8),
                Text('AI 助手', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (showComfort) ...[
              const SizedBox(height: 8),
              Text(comfort.text),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => ref.read(comfortProvider.notifier).dismiss(),
                  child: const Text('知道了'),
                ),
              ),
            ],
            for (final e in oneOffs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note),
                title: Text('${monthDay(e.key)} 临时作息'),
                subtitle: Text('熄灯 ${e.value.bedtime} · 起床 ${e.value.wakeUp}'),
                trailing: IconButton(
                  tooltip: '恢复原计划',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(rhythmControllerProvider.notifier)
                      .removeOverride(e.key),
                ),
              ),
            if (config?.isComplete != true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '在“设置 → AI 助手”填写服务地址、API Key 和模型后可用：每周复盘调参、临时情况调整、晚睡后的建议。',
                ),
              )
            else ...[
              if (reviewDue)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('又过了一周，让 AI 看看要不要调整计划吧'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _review(context, ref),
                      child: const Text('复盘最近一周'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _adjust(context, ref),
                      child: const Text('临时调整'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final review = await _withProgress(
      context,
      ref.read(advisorProvider).review(),
    );
    if (review == null || !context.mounted) return;

    final changes = describeReview(review, plan);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 复盘'),
        content: SingleChildScrollView(
          child: Text(
            [
              review.reason,
              if (changes.isEmpty) '\n这周不用调整，继续保持。' else '\n建议调整：',
              ...changes.map((c) => '· $c'),
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(changes.isEmpty ? '知道了' : '暂不调整'),
          ),
          if (changes.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('采纳'),
            ),
        ],
      ),
    );
    if (accepted == null) return;
    await ref.read(reviewedAtProvider.notifier).markReviewed();
    if (accepted) {
      await ref.read(rhythmControllerProvider.notifier).applyReview(review);
      if (context.mounted) _toast(context, '已按建议调整计划并重新注册闹钟');
    }
  }

  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final request = await showDialog<String>(
      context: context,
      builder: (context) => const _RequestDialog(),
    );
    if (request == null || request.trim().isEmpty || !context.mounted) return;

    final adjustment = await _withProgress(
      context,
      ref.read(advisorProvider).adjust(request),
    );
    if (adjustment == null || !context.mounted) return;

    final nights = adjustment.nights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('临时调整'),
        content: Text(
          [
            for (final e in nights)
              '${monthDay(e.key)} ${weekdayName(e.key)}：'
                  '熄灯 ${e.value.bedtime} · 起床 ${e.value.wakeUp}',
            if (adjustment.reason.isNotEmpty) '\n${adjustment.reason}',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('采纳'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref
        .read(rhythmControllerProvider.notifier)
        .applyAdjustment(adjustment);
    if (context.mounted) _toast(context, '已安排临时作息，之后自动回到原计划');
  }

  /// Shows a spinner while [request] runs; errors become a snackbar.
  static Future<T?> _withProgress<T>(
    BuildContext context,
    Future<T> request,
  ) async {
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    try {
      return await request;
    } on AiException catch (e) {
      if (context.mounted) _toast(context, e.message);
      return null;
    } finally {
      navigator.pop();
    }
  }

  static void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}

class _RequestDialog extends StatefulWidget {
  const _RequestDialog();

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('最近有什么特殊安排？'),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLines: 3,
      decoration: const InputDecoration(hintText: '例如：周三要赶 7 点的高铁；明早 8 点有会'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('让 AI 排'),
      ),
    ],
  );
}

/// One line per change the review proposes, e.g. `每晚最多提前 30 → 20 分钟`.
List<String> describeReview(ReviewSuggestion review, PlanConfig plan) {
  final s = plan.settings;
  final bed = review.targetBedtime;
  final wake = review.targetWakeUp;
  final step = review.maxStepMinutes;
  final days = review.maxDays;
  final windDown = review.windDownLeadMinutes;
  final nap = review.napTime;
  return [
    if (bed != null && wake != null)
      '目标作息 ${plan.targetBedtime}–${plan.targetWakeUp} → $bed–$wake',
    if (step != null) '每晚最多提前 ${s.maxStepMinutes} → $step 分钟',
    if (days != null) '过渡期最多 ${s.maxDays} → $days 晚',
    if (windDown != null) '降速准备提前 ${s.windDownLeadMinutes} → $windDown 分钟',
    if (nap != null) '午休胶囊 ${s.napTime} → $nap',
  ];
}
