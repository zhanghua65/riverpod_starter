# CLAUDE.md

RhythmCompass(节律罗盘):本地运行的渐进式作息调节 App,V1.0 只做 Android。产品文档见 `docs/RhythmCompass.md`,改功能前先读它,改完同步更新其中的"V1.0 Android 实现现状"。

## 技术栈
- Flutter 3.41+ / Dart 3,状态管理 Riverpod 2(`flutter_riverpod`),路由 `go_router`
- 闹钟:`alarm` 5.x;权限:`permission_handler`;本地存储:`shared_preferences`
- 无后端、无网络请求,数据只存本机

## 目录
- `lib/app/core/services/schedule/`:排期引擎(`stepping_plan.dart`)、计划配置、弹性容错(`recovery.dart`)、用户设置、本地存储。纯 Dart,不依赖 UI,改这里必须有单测
- `lib/app/core/services/alarm/`:三段闹钟链(降速、熄灯、起床,外加午休)、闹钟 id 规则、权限
- `lib/app/core/di/`:Riverpod provider。`rhythm_provider.dart` 里的 `RhythmController` 管计划并保持已注册闹钟同步
- `lib/app/modules/`:`rhythm`(主页、响铃页、计划设置)、`settings`、`onboarding`、`landing`(底部导航)
- `android/.../MainActivity.kt`:原生接口(全屏通知权限、小米自启动/省电策略页),channel 名 `rhythm_compass/permissions`
- `assets/audio/`:提示音(柔和钟声)

## 常用命令
```
flutter pub get
flutter analyze
flutter test
flutter run --flavor ... -t lib/main_dev.dart   # 入口:lib/main_dev.dart / lib/main_prod.dart
```
`flutter` 命令可能会自动改动 `analysis_options.yaml`、`pubspec.lock` 和 linux/macos/windows 的插件注册文件,提交前用 `git checkout` 还原,别带进提交。

## 约定
- 注释和提交信息用英文,UI 文案用中文(直接写在代码里,项目没有 l10n)
- 屏幕继承 `BaseView`(需要 controller 时)或用 `ConsumerWidget`;业务逻辑放 controller/service,不放在 widget 里
- 闹钟 id = `yyyyMMdd * 10 + 阶段序号`(见 `AlarmChain.idFor`),需放得进 32 位 int;新增阶段只能往 `AlarmStage` 末尾加
- 插件没有周期闹钟:App 每次启动补注册未来 8 晚(`RhythmController.horizonNights`)
- 用户可调的数值放 `RhythmSettings`,不要写死在引擎里;新增字段要有默认值,并兼容旧的已保存数据
- 新增或改动排期、容错、闹钟逻辑时同步加单测(`test/`,用 `FakeAlarmService`,不要碰真实插件)

## Android 注意事项
- 锁屏亮屏依赖:`USE_FULL_SCREEN_INTENT`(Android 14+ 需用户允许)、`MainActivity` 的 `showWhenLocked`/`turnScreenOn`
- 小米/红米(MIUI、澎湃):划掉应用会强制停止并取消闹钟,需用户允许自启动、省电策略选"无限制"、最近任务里锁定。这是系统限制,代码只能引导,不要尝试绕过
- 厂商设置页是非公开 Activity,找不到时必须回退到应用详情页
- 模拟器和 CI 里没有 Android SDK 时无法构建 APK,Dart 侧用 `flutter test` 验证;闹钟、锁屏、杀进程行为必须真机验证,别声称已验证

## Git
- 开发分支合并到 `develop`,打包从 `develop` 出;`master` 保持稳定
- 不要提交构建产物或 IDE 文件
