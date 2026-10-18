import 'package:flutter/material.dart';
import '/app/core/services/alarm/alarm_permissions.dart';
import '/app/modules/rhythm/widgets/keep_alive_steps.dart';

/// First-use guide: what the app does, the permissions the alarms need and
/// the phone settings that keep them reliable.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView>
    with WidgetsBindingObserver {
  static const _pageCount = 3;

  final _pages = PageController();
  int _page = 0;

  bool? _basic;
  bool? _fullScreen;
  bool? _battery;
  bool _xiaomi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  // Back from a system settings page: show what the user just changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final basic = await AlarmPermissions.basicGranted();
    final fullScreen = await AlarmPermissions.fullScreenIntentAllowed();
    final battery = await AlarmPermissions.batteryOptimizationIgnored();
    final xiaomi = await AlarmPermissions.isXiaomi();
    if (!mounted) return;
    setState(() {
      _basic = basic;
      _fullScreen = fullScreen;
      _battery = battery;
      _xiaomi = xiaomi;
    });
  }

  Future<void> _next() async {
    if (_page == _pageCount - 1) {
      widget.onFinish();
      return;
    }
    await _pages.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [_intro(), _permissions(), _romTips()],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black12,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.onFinish,
                    child: const Text('跳过'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _next,
                    child: Text(last ? '开始使用' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageOf({
    required String title,
    required List<Widget> children,
  }) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      ...children,
    ],
  );

  Widget _intro() => _pageOf(
    title: '欢迎使用睡了吗',
    children: const [
      Text('从凌晨睡到 23 点，不用一步到位。每晚只提前 20~30 分钟，几天后自然到达目标。'),
      SizedBox(height: 16),
      _Step(icon: Icons.phone_android, title: '降速准备', body: '睡前提前提醒你放下手机（提前量可在设置里调）。'),
      _Step(icon: Icons.bedtime, title: '熄灯躺平', body: '到点提醒关灯，躺下后点一下记录。'),
      _Step(icon: Icons.wb_sunny, title: '温和唤醒', body: '音量逐渐增大，减轻起床的不适。'),
      SizedBox(height: 8),
      Text('晚睡了也没关系，起床会适当顺延，第二天自动重排。所有数据只保存在本机。'),
    ],
  );

  Widget _permissions() => _pageOf(
    title: '开启闹钟所需权限',
    children: [
      const Text('没有这些权限，闹钟可能不准时，或锁屏时屏幕不会亮起。'),
      const SizedBox(height: 8),
      _PermissionRow(
        title: '通知和精确闹钟',
        body: '让三段闹钟准时响起。',
        granted: _basic,
        actionLabel: '授权',
        onAction: () async {
          await AlarmPermissions.ensureGranted();
          await _refresh();
        },
      ),
      _PermissionRow(
        title: '全屏通知',
        body: '响铃时在锁屏上亮屏并弹出提醒页（Android 14 及以上需手动允许）。',
        granted: _fullScreen,
        actionLabel: '去设置',
        onAction: AlarmPermissions.openFullScreenIntentSettings,
      ),
      _PermissionRow(
        title: '不受电池优化限制',
        body: '部分手机会在后台拦截闹钟。',
        granted: _battery,
        actionLabel: '允许',
        onAction: () async {
          await AlarmPermissions.requestIgnoreBatteryOptimizations();
          await _refresh();
        },
      ),
    ],
  );

  Widget _romTips() => _pageOf(
    title: '让闹钟更可靠',
    children: [
      const _Step(
        icon: Icons.do_not_disturb_on,
        title: '不要划掉应用',
        body: '睡前不要从最近任务里清掉本应用，否则部分手机上闹钟会失效。',
      ),
      if (_xiaomi) ...[
        const XiaomiKeepAliveSteps(),
        const SizedBox(height: 8),
      ],
      const _Step(
        icon: Icons.settings,
        title: '检查手机的后台限制',
        body: '小米、华为、OPPO、vivo、三星等手机，请在应用设置里允许：自启动、后台弹出界面、锁屏显示。',
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: AlarmPermissions.openAppSettings,
        child: const Text('打开本应用的系统设置'),
      ),
      const SizedBox(height: 16),
      const Text('设置好后，建议在“作息”页用调试里的“注册测试闹钟链”试一次，锁屏等待 3 分钟确认会亮屏响铃。'),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(body),
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.body,
    required this.granted,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final bool? granted;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      granted == true ? Icons.check_circle : Icons.error_outline,
      color: granted == true ? Colors.green : Colors.orange,
    ),
    title: Text(title),
    subtitle: Text(body),
    trailing: granted == true
        ? null
        : TextButton(onPressed: onAction, child: Text(actionLabel)),
  );
}
