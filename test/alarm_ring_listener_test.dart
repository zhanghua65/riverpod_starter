import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/modules/rhythm/widgets/alarm_ring_listener.dart';
import 'package:riverpod_starter/app/routes/app_pages.dart';
import 'package:riverpod_starter/flavors/build_config.dart';
import 'package:riverpod_starter/flavors/env_config.dart';
import 'package:riverpod_starter/flavors/environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_recall_notifier.dart';

void main() {
  // Off Android, permission requests are skipped (no platform channels).
  final notAndroid = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('a new alarm replaces a ring page nobody answered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // The landing page under the ring pages reads the app config.
    BuildConfig.instantiate(
      envType: Environment.DEVELOPMENT,
      envConfig: EnvConfig(appName: 'test'),
    );
    final alarms = FakeAlarmService();
    final ringing = StreamController<AlarmSet>();
    addTearDown(ringing.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
          ringingAlarmsProvider.overrideWith((ref) => ringing.stream),
        ],
        child: MaterialApp.router(
          routerConfig: AppPages.router,
          builder: (context, child) => AlarmRingListener(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final night = DateTime(2026, 10, 17);
    AlarmSettings settings(AlarmStage stage) => AlarmChain.settingsAt(
      night,
      stage,
      DateTime.now().add(const Duration(minutes: 1)),
    );

    // The wind-down rings and stops on its own; nobody taps it.
    ringing.add(AlarmSet([settings(AlarmStage.windDown)]));
    await tester.pumpAndSettle();
    expect(find.text('好，我放下手机'), findsOneWidget);
    ringing.add(AlarmSet.empty());
    await tester.pumpAndSettle();

    ringing.add(AlarmSet([settings(AlarmStage.bedtime)]));
    await tester.pumpAndSettle();
    expect(find.text('我已躺下'), findsOneWidget);

    await tester.tap(find.text('我已躺下'));
    await tester.pumpAndSettle();

    // Closing the bedtime page leaves no ring page behind.
    expect(find.text('我已躺下'), findsNothing);
    expect(find.text('好，我放下手机'), findsNothing);
  }, variant: notAndroid);
}
