import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/modules/rhythm/views/history_view.dart';
import 'package:riverpod_starter/app/modules/rhythm/views/rhythm_view.dart';
import 'package:riverpod_starter/app/modules/rhythm/views/ring_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';

void main() {
  late FakeAlarmService alarms;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    alarms = FakeAlarmService();
  });

  // Off Android, permission requests are skipped (no platform channels).
  final notAndroid = TargetPlatformVariant.only(TargetPlatform.linux);

  Widget app(Widget child) => ProviderScope(
    overrides: [alarmServiceProvider.overrideWithValue(alarms)],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('starting a plan registers alarms and shows the overview', (
    tester,
  ) async {
    await tester.pumpWidget(app(const RhythmView()));
    await tester.pumpAndSettle();

    expect(find.text('设定渐进作息计划'), findsOneWidget);
    expect(find.text('过渡期共 5 晚'), findsOneWidget);

    await tester.ensureVisible(find.text('开始计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始计划'));
    await tester.pumpAndSettle();

    expect(alarms.alarms, isNotEmpty);
    expect(find.text('目标 23:00 睡 · 07:00 起'), findsOneWidget);
    expect(find.text('补记昨晚入睡时间'), findsOneWidget);
    expect(find.text('昨晚还没有睡眠记录'), findsOneWidget);
  }, variant: notAndroid);

  testWidgets('the wind-down page waits for the user', (tester) async {
    final settings = AlarmChain.settingsAt(
      DateTime(2026, 10, 17),
      AlarmStage.windDown,
      DateTime.now().add(const Duration(minutes: 5)),
    );
    await tester.pumpWidget(app(RingView(alarm: settings)));
    await tester.pumpAndSettle();

    expect(find.text('降速准备'), findsOneWidget);
    expect(find.text('好，我放下手机'), findsOneWidget);
  }, variant: notAndroid);

  testWidgets('the bedtime page offers confirm and snooze', (tester) async {
    final AlarmSettings settings = AlarmChain.settingsAt(
      DateTime(2026, 10, 17),
      AlarmStage.bedtime,
      DateTime.now().add(const Duration(minutes: 5)),
    );
    await tester.pumpWidget(app(RingView(alarm: settings)));
    await tester.pumpAndSettle();

    expect(find.text('我已躺下'), findsOneWidget);
    expect(find.text('再给我 15 分钟'), findsOneWidget);
  }, variant: notAndroid);

  testWidgets('the history page says so when there are no records', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HistoryView()));
    await tester.pumpAndSettle();

    expect(find.text('还没有睡眠记录'), findsOneWidget);
  }, variant: notAndroid);
}
