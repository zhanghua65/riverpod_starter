import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/advisor_provider.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/ai/ai_config.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:riverpod_starter/app/modules/rhythm/widgets/advisor_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_chat_transport.dart';

void main() {
  late FakeAlarmService alarms;
  late FakeChatTransport chat;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  String two(int n) => n.toString().padLeft(2, '0');
  final tomorrowKey =
      '${tomorrow.year}-${two(tomorrow.month)}-${two(tomorrow.day)}';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    alarms = FakeAlarmService();
    chat = FakeChatTransport([]);
    container = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        chatTransportProvider.overrideWithValue(chat),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// Lets the store and the fake request finish in real time; the spinner
  /// keeps fake time from ever settling on its own.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.runAsync(() async {
      await container.read(rhythmControllerProvider.future);
      await container
          .read(rhythmControllerProvider.notifier)
          .applyPlan(
            PlanConfig(
              currentBedtime: const ClockTime(23, 0),
              currentWakeUp: const ClockTime(7, 0),
              targetBedtime: const ClockTime(23, 0),
              targetWakeUp: const ClockTime(7, 0),
              firstNight: today,
            ),
          );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(rhythmControllerProvider).value!;
                return AdvisorCard(plan: state.plan!, log: state.log);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without AI settings it explains where to set them up', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.textContaining('设置 → AI 助手'), findsOneWidget);
    expect(find.text('临时调整'), findsNothing);
  });

  testWidgets('a temporary adjustment is shown and applied when accepted', (
    tester,
  ) async {
    await tester.runAsync(
      () => container
          .read(aiConfigProvider.notifier)
          .save(
            const AiConfig(
              baseUrl: 'https://example.com/v1',
              apiKey: 'k',
              model: 'm',
            ),
          ),
    );
    chat.replies.add(
      '{"nights": [{"date": "$tomorrowKey", "bedtime": "22:00", '
      '"wakeUp": "05:30"}], "reason": "早班高铁"}',
    );
    await pumpCard(tester);

    await tester.tap(find.text('临时调整'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '明天要赶早班高铁');
    await tester.tap(find.text('让 AI 排'));
    await settle(tester);

    expect(find.textContaining('熄灯 22:00 · 起床 05:30'), findsOneWidget);
    expect(find.textContaining('早班高铁'), findsOneWidget);

    await tester.tap(find.text('采纳'));
    await settle(tester);

    final bed = alarms.alarms[AlarmChain.idFor(tomorrow, AlarmStage.bedtime)]!;
    expect(bed.dateTime.hour, 22);
    expect(
      find.text('${tomorrow.month}月${tomorrow.day}日 临时作息'),
      findsOneWidget,
    );
  });
}
