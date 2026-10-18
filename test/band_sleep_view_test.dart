import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/schedule/band_sleep.dart';
import 'package:riverpod_starter/app/modules/permissions/views/band_sleep_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_health_sleep.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(FakeHealthSleep health) => ProviderScope(
    overrides: [
      alarmServiceProvider.overrideWithValue(FakeAlarmService()),
      healthSleepProvider.overrideWithValue(health),
    ],
    child: const MaterialApp(home: BandSleepView()),
  );

  testWidgets('lists the synced sessions with their source', (tester) async {
    final now = DateTime.now();
    final night = DateTime(now.year, now.month, now.day - 2, 23, 30);
    await tester.pumpWidget(
      app(
        FakeHealthSleep([
          SleepSession(
            night,
            night.add(const Duration(hours: 7, minutes: 15)),
            source: 'com.mi.health',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('共 1 段睡眠'), findsOneWidget);
    expect(find.textContaining('7 小时 15 分'), findsOneWidget);
    expect(find.text('来源：小米运动健康'), findsOneWidget);
  });

  testWidgets('explains what to check when nothing synced', (tester) async {
    await tester.pumpWidget(app(FakeHealthSleep(const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有睡眠数据'), findsOneWidget);
    expect(find.text('打开小米运动健康'), findsOneWidget);
  });

  testWidgets('asks for access when reading is not allowed', (tester) async {
    await tester.pumpWidget(app(FakeHealthSleep()));
    await tester.pumpAndSettle();

    expect(find.text('去授权'), findsOneWidget);
  });

  test('source names fall back to the package', () {
    expect(sourceName('com.xiaomi.wearable'), '小米穿戴 / Mi Fitness');
    expect(sourceName('com.example.band'), 'com.example.band');
  });
}
