import 'package:flutter/material.dart';
import '/app/modules/permissions/widgets/permission_checklist.dart';

/// First-use guide: what the app does, the permissions the alarms need and
/// the phone settings that keep them reliable.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  static const _pageCount = 2;

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
                children: [_intro(), _permissions()],
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
    title: '欢迎使用早一点点',
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
    children: const [
      Text('没有这些权限，闹钟可能不准时，或锁屏时屏幕不会亮起。以后也可以在“设置 → 权限自检”里再看。'),
      PermissionChecklist(),
      SizedBox(height: 16),
      Text('设置好后，建议在“作息”页用调试里的“注册测试闹钟链”试一次，锁屏等待 3 分钟确认会亮屏响铃。'),
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
