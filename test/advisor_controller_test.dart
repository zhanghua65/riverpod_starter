import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/di/advisor_provider.dart';
import 'package:riverpod_starter/app/core/di/alarm_provider.dart';
import 'package:riverpod_starter/app/core/di/rhythm_provider.dart';
import 'package:riverpod_starter/app/core/services/ai/ai_config.dart';
import 'package:riverpod_starter/app/core/services/ai/chat_client.dart';
import 'package:riverpod_starter/app/core/services/ai/rhythm_advisor.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:riverpod_starter/app/core/services/schedule/work_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_service.dart';
import 'fake_recall_notifier.dart';
import 'fake_chat_transport.dart';

void main() {
  late FakeAlarmService alarms;
  late FakeChatTransport chat;
  late ProviderContainer container;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  const ai = AiConfig(
    baseUrl: 'https://example.com/v1',
    apiKey: 'k',
    model: 'm',
  );

  final onTarget = PlanConfig(
    currentBedtime: const ClockTime(23, 0),
    currentWakeUp: const ClockTime(7, 0),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: today,
  );

  RhythmController controller() =>
      container.read(rhythmControllerProvider.notifier);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    alarms = FakeAlarmService();
    chat = FakeChatTransport([]);
    container = ProviderContainer(
      overrides: [
        alarmServiceProvider.overrideWithValue(alarms),
        recallNotifierProvider.overrideWithValue(FakeRecallNotifier()),
        chatTransportProvider.overrideWithValue(chat),
      ],
    );
    await container.read(rhythmControllerProvider.future);
    await controller().applyPlan(onTarget);
  });

  tearDown(() => container.dispose());

  DateTime bedtimeAlarm(DateTime night) =>
      alarms.alarms[AlarmChain.idFor(night, AlarmStage.bedtime)]!.dateTime;

  test('a one-off night replaces that night only and can be undone', () async {
    // Booked by an earlier late night; must survive the adjustment.
    final napId = AlarmChain.idFor(today, AlarmStage.nap);
    await alarms.schedule(
      AlarmChain.settingsAt(
        today,
        AlarmStage.nap,
        now.add(const Duration(hours: 1)),
      ),
    );

    await controller().applyAdjustment(
      TemporaryAdjustment(
        nights: {
          tomorrow: const NightOverride(
            bedtime: ClockTime(22, 0),
            wakeUp: ClockTime(5, 30),
          ),
        },
        reason: '',
      ),
    );

    expect(
      bedtimeAlarm(tomorrow),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 22),
    );
    final after = DateTime(now.year, now.month, now.day + 2);
    expect(bedtimeAlarm(after).hour, 23);
    expect(alarms.alarms, contains(napId));

    await controller().removeOverride(tomorrow);
    expect(bedtimeAlarm(tomorrow).hour, 23);
    final state = container.read(rhythmControllerProvider).value!;
    expect(state.plan!.overrides, isEmpty);
  });

  test(
    'an accepted review saves settings and steps toward new targets',
    () async {
      await controller().applyReview(
        const ReviewSuggestion(
          reason: '',
          targetBedtime: ClockTime(22, 0),
          targetWakeUp: ClockTime(6, 0),
          maxStepMinutes: 15,
        ),
      );

      final state = container.read(rhythmControllerProvider).value!;
      expect(state.settings.maxStepMinutes, 15);
      expect(state.plan!.targetBedtime, const ClockTime(22, 0));
      expect(state.plan!.firstNight, today);
      // Tonight already moves one 15-minute step.
      final tonight = bedtimeAlarm(today);
      expect((tonight.hour, tonight.minute), (22, 45));
    },
  );

  test('a late night on a workday never makes the user late', () async {
    await controller().updateWork(
      WorkSchedule(
        workdays: {tomorrow.weekday},
        start: const ClockTime(8, 0),
        morningMinutes: 50,
      ),
    );
    final recovery = await controller().confirmBedtime(
      today,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 1, 30),
    );
    expect(
      recovery.wakeUp,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 10),
    );
  });

  group('advisor', () {
    test('needs the AI to be set up', () async {
      expect(
        container.read(advisorProvider).review(),
        throwsA(isA<AiException>()),
      );
      expect(chat.requests, isEmpty);
    });

    test('reviews with the saved config', () async {
      await container.read(aiConfigProvider.notifier).save(ai);
      chat.replies.add('{"maxDays": 10, "reason": "放慢"}');

      final review = await container.read(advisorProvider).review();

      expect(review.maxDays, 10);
      expect(chat.requests, hasLength(1));
    });

    test('comfort after a late night is kept for the home page', () async {
      await container.read(aiConfigProvider.notifier).save(ai);
      chat.replies.add('没关系，今天中午补个觉。');
      final recovery = await controller().confirmBedtime(
        today,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 1, 0),
      );

      await container
          .read(comfortProvider.notifier)
          .requestFor(today, recovery);

      final comfort = container.read(comfortProvider).value!;
      expect(comfort.night, today);
      expect(comfort.text, '没关系，今天中午补个觉。');

      await container.read(comfortProvider.notifier).dismiss();
      expect(container.read(comfortProvider).value, isNull);
    });

    test('without the AI set up no comfort is asked for', () async {
      final late = await controller().confirmBedtime(
        today,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 1, 0),
      );
      await container.read(comfortProvider.notifier).requestFor(today, late);
      expect(chat.requests, isEmpty);
    });
  });
}
