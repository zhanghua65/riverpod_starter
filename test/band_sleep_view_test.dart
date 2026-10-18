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

  group('diagnosis hints', () {
    test('missing Health Connect stops there', () {
      final hints = diagnosisHints(['hc sdkStatus=unavailable']);
      expect(hints.single, contains('找不到 Health Connect'));
    });

    test('no sleep permission is named', () {
      final hints = diagnosisHints([
        'hc sdkStatus=available',
        'hc granted=READ_STEPS',
      ]);
      expect(hints.single, contains('睡眠'));
    });

    test('nothing written points at the band app', () {
      final hints = diagnosisHints([
        'hc sdkStatus=available',
        'pkg com.mi.health=3.30.0',
        'pkg com.xiaomi.wearable=missing',
        'hc granted=READ_SLEEP',
        'read 30d sleep sessions=0',
      ]);
      expect(hints, hasLength(2));
      expect(hints.first, contains('小米运动健康'));
      expect(hints.last, contains('不在本应用'));
    });

    test('data present names the writer', () {
      final hints = diagnosisHints([
        'hc sdkStatus=available',
        'hc granted=READ_SLEEP',
        'read 30d sleep sessions=3',
        'origin com.xiaomi.wearable count=3 latestEnd=10-18 07:10',
      ]);
      expect(hints.single, contains('com.xiaomi.wearable'));
    });
  });
}
