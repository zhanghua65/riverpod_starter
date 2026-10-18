import 'package:flutter/material.dart';
import '/app/core/services/alarm/alarm_chain.dart';
import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/core/utils/wake_time_recommender.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// Lets the user enter the current and target schedule and previews the
/// stepping plan before it is applied.
class PlanSetup extends StatefulWidget {
  const PlanSetup({required this.onApply, this.initial, this.onCancel});

  final PlanConfig? initial;
  final Future<void> Function(PlanConfig plan) onApply;
  final VoidCallback? onCancel;

  @override
  State<PlanSetup> createState() => _PlanSetupState();
}

class _PlanSetupState extends State<PlanSetup> {
  late ClockTime _currentBedtime;
  late ClockTime _currentWakeUp;
  late ClockTime _targetBedtime;
  late ClockTime _targetWakeUp;

  PlanConfig? _config;
  List<AlarmChain>? _plan;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _currentBedtime = initial?.currentBedtime ?? const ClockTime(1, 30);
    _currentWakeUp = initial?.currentWakeUp ?? const ClockTime(9, 30);
    _targetBedtime = initial?.targetBedtime ?? const ClockTime(23, 0);
    _targetWakeUp = initial?.targetWakeUp ?? const ClockTime(7, 0);
    _rebuildPlan();
  }

  void _rebuildPlan() {
    final today = DateTime.now();
    final config = PlanConfig(
      currentBedtime: _currentBedtime,
      currentWakeUp: _currentWakeUp,
      targetBedtime: _targetBedtime,
      targetWakeUp: _targetWakeUp,
      firstNight: DateTime(today.year, today.month, today.day),
    );
    try {
      _plan = config.transition;
      _config = config;
      _error = null;
    } on ArgumentError {
      _plan = null;
      _config = null;
      _error = '就寝时间必须早于第二天的起床时间';
    }
  }

  /// 按目标就寝时间推算的起床时间（90 分钟周期）。
  List<(WakeTimeRecommendation, ClockTime)> _recommendations() {
    final now = DateTime.now();
    final bedtime = DateTime(
      now.year,
      now.month,
      now.day,
      _targetBedtime.hour,
      _targetBedtime.minute,
    );
    return [
      for (final r in WakeTimeRecommender.recommend(bedtime))
        (r, ClockTime.of(r.wakeTime)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final config = _config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '设定渐进作息计划',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('每晚最多提前 30 分钟，最后一晚到达目标；之后每天按目标作息提醒。'),
        _timeTile('现在几点睡', _currentBedtime, (t) => _currentBedtime = t),
        _timeTile('现在几点起', _currentWakeUp, (t) => _currentWakeUp = t),
        _timeTile('目标就寝', _targetBedtime, (t) {
          _targetBedtime = t;
          // 就寝时间变化后，起床时间跟随推荐，仍可手动修改。
          _targetWakeUp = _recommendations().firstWhere((r) => r.isPrimary).$2;
        }),
        _timeTile('目标起床', _targetWakeUp, (t) => _targetWakeUp = t),
        Wrap(
          spacing: 8,
          children: [
            for (final r in _recommendations())
              ChoiceChip(
                label: Text(
                  '${r.$2}${r.$1.isPrimary ? ' 推荐' : ''}'
                  '（${r.$1.cycles} 个周期）',
                ),
                selected: _targetWakeUp == r.$2,
                onSelected: (_) => setState(() {
                  _targetWakeUp = r.$2;
                  _rebuildPlan();
                }),
              ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (plan != null && config != null) ...[
          const SizedBox(height: 8),
          Text('过渡期共 ${plan.length} 晚'),
          for (var i = 0; i < plan.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('第 ${i + 1} 晚  ${monthDay(plan[i].night)}'),
              subtitle: Text(chainSummary(plan[i])),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _applying ? null : () => _apply(config),
            child: const Text('开始计划'),
          ),
        ],
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('取消')),
      ],
    );
  }

  Future<void> _apply(PlanConfig config) async {
    setState(() => _applying = true);
    try {
      await widget.onApply(config);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Widget _timeTile(
    String label,
    ClockTime value,
    void Function(ClockTime) onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value.toString(), style: const TextStyle(fontSize: 18)),
      onTap: () async {
        final picked = await pickClockTime(context, value);
        if (picked == null) return;
        setState(() {
          onChanged(picked);
          _rebuildPlan();
        });
      },
    );
  }
}
