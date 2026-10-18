import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/ai/ai_config.dart';
import 'package:riverpod_starter/app/core/services/ai/chat_client.dart';
import 'package:riverpod_starter/app/core/services/ai/rhythm_advisor.dart';
import 'package:riverpod_starter/app/core/services/schedule/plan_config.dart';
import 'package:riverpod_starter/app/core/services/schedule/recovery.dart';
import 'package:riverpod_starter/app/core/services/schedule/rhythm_store.dart';
import 'package:riverpod_starter/app/core/services/schedule/stepping_plan.dart';
import 'package:riverpod_starter/app/core/services/schedule/work_schedule.dart';

import 'fake_chat_transport.dart';

void main() {
  // Sunday evening.
  final now = DateTime(2026, 10, 18, 21, 0);
  final plan = PlanConfig(
    currentBedtime: const ClockTime(23, 0),
    currentWakeUp: const ClockTime(7, 0),
    targetBedtime: const ClockTime(23, 0),
    targetWakeUp: const ClockTime(7, 0),
    firstNight: DateTime(2026, 10, 18),
  );
  const work = WorkSchedule(start: ClockTime(8, 30), morningMinutes: 70);
  final log = [
    SleepLogEntry(
      night: DateTime(2026, 10, 17),
      plannedBedtime: DateTime(2026, 10, 17, 23, 0),
      actualBedtime: DateTime(2026, 10, 18, 0, 40),
      actualWakeUp: DateTime(2026, 10, 18, 7, 25),
    ),
  ];
  final withWork = AdvisorContext(now: now, plan: plan, work: work, log: log);
  final noWork = AdvisorContext(now: now, plan: plan, log: log);

  group('context', () {
    test('lists the nights ahead, recent nights and the work schedule', () {
      final json = withWork.toJson();
      final upcoming = json['upcomingNights'] as List;
      expect(upcoming, hasLength(AdvisorContext.upcomingNights));
      expect(upcoming.first, {
        'date': '2026-10-18',
        'weekday': '周日',
        'bedtime': '23:00',
        'wakeUp': '07:00',
      });
      expect((json['work'] as Map)['latestWakeUp'], '07:20');
      expect((json['recentNights'] as List).single, {
        'date': '2026-10-17',
        'weekday': '周六',
        'planned': '23:00',
        'actual': '00:40',
        'lateMinutes': 100,
        'wokeUp': '07:25',
        'sleepMinutes': 405,
      });
      expect(noWork.toJson()['work'], isNull);
    });
  });

  group('weekly review', () {
    ReviewSuggestion parse(Object reply, [AdvisorContext? context]) =>
        ReviewSuggestion.parse(
          reply is String ? reply : jsonEncode(reply),
          context ?? withWork,
        );

    test('clamps and rounds settings into their ranges', () {
      final r = parse({
        'maxStepMinutes': 17,
        'maxDays': 30,
        'windDownLeadMinutes': 90,
        'reason': '最近常晚睡',
      });
      expect(r.maxStepMinutes, 15);
      expect(r.maxDays, 14);
      expect(r.windDownLeadMinutes, 60);
      expect(r.reason, '最近常晚睡');
    });

    test('drops values that do not change anything', () {
      final r = parse({'maxStepMinutes': 30, 'targetBedtime': '23:00'});
      expect(r.changesNothing, isTrue);
      expect(r.reason, isNotEmpty);
    });

    test('keeps the wake-up target early enough for work', () {
      final r = parse({'targetBedtime': '22:30', 'targetWakeUp': '07:45'});
      expect(r.targetBedtime, const ClockTime(22, 30));
      expect(r.targetWakeUp, const ClockTime(7, 20));
    });

    test('fills a missing target from the current one', () {
      final r = parse({'targetBedtime': '22:30'}, noWork);
      expect(r.targetWakeUp, const ClockTime(7, 0));
    });

    test('rejects targets with too little sleep or odd bedtimes', () {
      expect(
        parse({
          'targetBedtime': '01:00',
          'targetWakeUp': '06:00',
        }).changesTargets,
        isFalse,
      );
      expect(
        parse({
          'targetBedtime': '15:00',
          'targetWakeUp': '23:00',
        }).changesTargets,
        isFalse,
      );
    });

    test('suggests a nap time only without a work schedule', () {
      expect(parse({'napTime': '12:30'}).napTime, isNull);
      expect(
        parse({'napTime': '12:30'}, noWork).napTime,
        const ClockTime(12, 30),
      );
      expect(parse({'napTime': '18:00'}, noWork).napTime, isNull);
    });

    test('reads json wrapped in a code fence', () {
      final r = parse('好的：\n```json\n{"maxDays": 10, "reason": "放慢"}\n```');
      expect(r.maxDays, 10);
    });

    test('a reply without json is an error', () {
      expect(() => parse('我觉得挺好'), throwsA(isA<AiException>()));
    });
  });

  group('temporary adjustment', () {
    TemporaryAdjustment parse(List<Map<String, String>> nights) =>
        TemporaryAdjustment.parse(
          jsonEncode({'nights': nights, 'reason': '早班高铁'}),
          withWork,
        );

    test('keeps valid nights ahead', () {
      final a = parse([
        {'date': '2026-10-21', 'bedtime': '22:00', 'wakeUp': '05:30'},
      ]);
      expect(a.nights, {
        DateTime(2026, 10, 21): const NightOverride(
          bedtime: ClockTime(22, 0),
          wakeUp: ClockTime(5, 30),
        ),
      });
      expect(a.reason, '早班高铁');
    });

    test('drops past, far-off and too-short nights, and caps the count', () {
      final a = parse([
        {'date': '2026-10-17', 'bedtime': '22:00', 'wakeUp': '06:00'},
        {'date': '2026-10-26', 'bedtime': '22:00', 'wakeUp': '06:00'},
        {'date': '2026-10-19', 'bedtime': '02:00', 'wakeUp': '05:00'},
        {'date': '2026-10-19', 'bedtime': 'soon', 'wakeUp': '05:00'},
        {'date': '2026-10-20', 'bedtime': '22:00', 'wakeUp': '06:00'},
        {'date': '2026-10-21', 'bedtime': '22:00', 'wakeUp': '06:00'},
        {'date': '2026-10-22', 'bedtime': '22:00', 'wakeUp': '06:00'},
        {'date': '2026-10-23', 'bedtime': '22:00', 'wakeUp': '06:00'},
      ]);
      expect(a.nights.keys.map((d) => d.day), [20, 21, 22]);
    });

    test('nothing usable is an error', () {
      expect(
        () => parse([
          {'date': '2026-10-17', 'bedtime': '22:00', 'wakeUp': '06:00'},
        ]),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('advisor', () {
    const config = AiConfig(
      baseUrl: 'https://example.com/v1',
      apiKey: 'k',
      model: 'm',
    );

    test('sends instructions and the user data, then validates', () async {
      final transport = FakeChatTransport(['{"maxDays": 10, "reason": "放慢"}']);
      final advisor = RhythmAdvisor(transport: transport, config: config);

      final review = await advisor.review(withWork);

      expect(review.maxDays, 10);
      final messages = transport.requests.single;
      expect(messages.map((m) => m.role), ['system', 'user']);
      expect(messages.first.content, contains('JSON'));
      expect(jsonDecode(messages.last.content), withWork.toJson());
    });

    test('passes the request along for an adjustment', () async {
      final transport = FakeChatTransport([
        '{"nights": [{"date": "2026-10-21", "bedtime": "22:00", '
            '"wakeUp": "05:30"}]}',
      ]);
      final advisor = RhythmAdvisor(transport: transport, config: config);

      final a = await advisor.adjust(withWork, ' 周三 7 点高铁 ');

      expect(a.nights.keys.single, DateTime(2026, 10, 21));
      final data = jsonDecode(transport.requests.single.last.content) as Map;
      expect(data['request'], '周三 7 点高铁');
    });

    test('comfort is plain text without markdown', () async {
      final transport = FakeChatTransport(['**没关系**，今天中午睡 20 分钟。']);
      final advisor = RhythmAdvisor(transport: transport, config: config);

      final text = await advisor.comfort(
        withWork,
        Recovery.after(
          planned: plan.chainFor(DateTime(2026, 10, 18))!,
          actualBedtime: DateTime(2026, 10, 19, 1, 0),
          config: plan,
          work: work,
        ),
      );

      expect(text, '没关系，今天中午睡 20 分钟。');
      final data = jsonDecode(transport.requests.single.last.content) as Map;
      expect((data['recovery'] as Map)['lateMinutes'], 120);
    });
  });

  test('sleep counts bedtimes before noon as after midnight', () {
    expect(
      sleepBetween(const ClockTime(23, 0), const ClockTime(7, 0)),
      const Duration(hours: 8),
    );
    expect(
      sleepBetween(const ClockTime(1, 0), const ClockTime(7, 0)),
      const Duration(hours: 6),
    );
  });
}
