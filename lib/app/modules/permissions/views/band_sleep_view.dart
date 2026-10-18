import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/schedule/band_sleep.dart';
import '/app/core/services/usage/health_sleep.dart';
import '/app/modules/rhythm/widgets/time_format.dart';

/// Shows the sleep sessions Health Connect returns for the last
/// [BandSleepView.days] days, so the user can see whether the band app
/// syncs at all, and which session last night's record would use.
class BandSleepView extends ConsumerStatefulWidget {
  const BandSleepView({super.key});

  static const days = 7;

  @override
  ConsumerState<BandSleepView> createState() => _BandSleepViewState();
}

class _BandSleepViewState extends ConsumerState<BandSleepView>
    with WidgetsBindingObserver {
  bool _loading = true;
  HealthSleepStatus? _status;
  List<SleepSession>? _sessions;
  DateTime? _readAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Health Connect or the band app: the data may have synced.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final health = ref.read(healthSleepProvider);
    final status = await health.status();
    final now = DateTime.now();
    final sessions = status == HealthSleepStatus.granted
        ? await health.sessions(
            now.subtract(const Duration(days: BandSleepView.days)),
            now,
          )
        : null;
    if (!mounted) return;
    setState(() {
      _status = status;
      _sessions = sessions == null
          ? null
          : ([...sessions]..sort((a, b) => b.start.compareTo(a.start)));
      _readAt = now;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手环睡眠数据'),
        actions: [
          IconButton(
            tooltip: '重新读取',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: _body()),
    );
  }

  List<Widget> _body() {
    final health = ref.read(healthSleepProvider);
    final sessions = _sessions;
    final readAt = _readAt;
    switch (_status) {
      case HealthSleepStatus.unavailable:
      case null:
        return const [Text('本机没有 Health Connect（健康数据共享），无法读取手环数据。')];
      case HealthSleepStatus.needsUpdate:
        return [
          const Text('需要先更新 Health Connect。'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => health.requestAccess(),
            child: const Text('去更新'),
          ),
        ];
      case HealthSleepStatus.denied:
        return [
          const Text('还没有允许读取睡眠数据。'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              if (!await health.requestAccess()) await health.openSettings();
              await _load();
            },
            child: const Text('去授权'),
          ),
        ];
      case HealthSleepStatus.granted:
        break;
    }

    if (sessions == null) {
      return const [Text('读取失败：Health Connect 没有返回数据，请稍后点右上角重试。')];
    }

    final picked = _lastNight(sessions);
    return [
      Text(
        '已允许读取。${readAt == null ? '' : '${hourMinute(readAt)} 读取，'}'
        '最近 ${BandSleepView.days} 天共 ${sessions.length} 段睡眠。',
      ),
      const SizedBox(height: 8),
      if (sessions.isEmpty) ...[
        const Text(
          'Health Connect 里还没有睡眠数据。请检查：\n'
          '1. 小米运动健康 → 我的 → 第三方数据 / Health Connect，打开睡眠同步\n'
          '2. 手环已和小米运动健康同步过（打开小米运动健康下拉刷新）\n'
          '3. 在 Health Connect 的“数据和访问 → 睡眠”里能看到记录',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () async {
                if (!await health.openBandApp()) await health.openSettings();
              },
              child: const Text('打开小米运动健康'),
            ),
            OutlinedButton(
              onPressed: health.openSettings,
              child: const Text('打开 Health Connect'),
            ),
          ],
        ),
      ] else ...[
        if (picked != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.bedtime),
              title: const Text('昨晚记录会用这段'),
              subtitle: Text(_span(picked)),
            ),
          )
        else if (ref.read(rhythmControllerProvider).value?.plan != null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('昨晚没有可用的睡眠'),
              subtitle: Text(
                '需要计划就寝前 4 小时到计划起床后 4 小时内、合计至少 3 小时的睡眠；'
                '还没过计划起床时间时也不会读取',
              ),
            ),
          ),
        for (final s in sessions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.watch_outlined),
            title: Text(_span(s)),
            subtitle: Text('来源：${sourceName(s.source)}'),
          ),
      ],
    ];
  }

  /// What last night's record would pick, the same way the controller does.
  SleepSession? _lastNight(List<SleepSession> sessions) {
    final plan = ref.read(rhythmControllerProvider).value?.plan;
    if (plan == null) return null;
    final now = DateTime.now();
    final planned = plan.chainFor(DateTime(now.year, now.month, now.day - 1));
    if (planned == null) return null;
    return BandSleep.pick(planned: planned, sessions: sessions, now: now);
  }

  static String _span(SleepSession s) {
    final minutes = s.length.inMinutes;
    return '${monthDay(s.start)} ${hourMinute(s.start)} – '
        '${s.end.day == s.start.day ? '' : '${monthDay(s.end)} '}'
        '${hourMinute(s.end)} · ${minutes ~/ 60} 小时 ${minutes % 60} 分';
  }
}

/// Readable name for the app that wrote a session.
String sourceName(String package) => switch (package) {
  'com.mi.health' => '小米运动健康',
  'com.xiaomi.wearable' => '小米穿戴 / Mi Fitness',
  'com.huawei.health' => '华为运动健康',
  'com.google.android.apps.fitness' => 'Google Fit',
  '' => '未知',
  _ => package,
};
