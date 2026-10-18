import 'dart:convert';

import '/app/core/services/schedule/plan_config.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_settings.dart';
import '/app/core/services/schedule/rhythm_store.dart';
import '/app/core/services/schedule/stepping_plan.dart';
import '/app/core/services/schedule/work_schedule.dart';
import 'ai_config.dart';
import 'chat_client.dart';

/// Everything the advisor tells the model about the user. Only times and
/// settings, nothing that identifies the user or the device.
class AdvisorContext {
  const AdvisorContext({
    required this.now,
    required this.plan,
    this.work,
    this.log = const [],
  });

  final DateTime now;
  final PlanConfig plan;
  final WorkSchedule? work;

  /// Newest first.
  final List<SleepLogEntry> log;

  /// Nights the model may pick for a one-off adjustment, from tonight on.
  static const upcomingNights = 8;

  /// Nights of the sleep log sent along.
  static const recentNights = 14;

  RhythmSettings get settings => plan.settings;

  DateTime get today => DateTime(now.year, now.month, now.day);

  Map<String, Object?> toJson() {
    final work = this.work;
    return {
      'now': '${_date(now)} ${_weekday(now)} ${ClockTime.of(now)}',
      'target': {
        'bedtime': '${plan.targetBedtime}',
        'wakeUp': '${plan.targetWakeUp}',
      },
      'settings': {
        'maxStepMinutes': settings.maxStepMinutes,
        'maxDays': settings.maxDays,
        'windDownLeadMinutes': settings.windDownLeadMinutes,
        'napTime': '${settings.napTime}',
      },
      'work': work == null
          ? null
          : {
              'workdays': [
                for (final d in work.workdays.toList()..sort())
                  _weekdays[d - 1],
              ],
              'start': '${work.start}',
              'end': '${work.end}',
              'lunch': '${work.lunchStart}-${work.lunchEnd}',
              'morningMinutes': work.morningMinutes,
              'latestWakeUp': '${work.latestWakeUp}',
            },
      'upcomingNights': [
        for (final chain in plan.chainsFrom(today, upcomingNights))
          {
            'date': _date(chain.night),
            'weekday': _weekday(chain.night),
            'bedtime': '${ClockTime.of(chain.bedtime)}',
            'wakeUp': '${ClockTime.of(chain.wakeUp)}',
            if (plan.overrides.containsKey(chain.night)) 'oneOff': true,
          },
      ],
      'recentNights': [
        for (final e in log.take(recentNights))
          {
            'date': _date(e.night),
            'weekday': _weekday(e.night),
            'planned': '${ClockTime.of(e.plannedBedtime)}',
            'actual': '${ClockTime.of(e.actualBedtime)}',
            'lateMinutes': e.lateBy.inMinutes,
            if (e.actualWakeUp != null)
              'wokeUp': '${ClockTime.of(e.actualWakeUp!)}',
            if (e.sleepDuration != null)
              'sleepMinutes': e.sleepDuration!.inMinutes,
          },
      ],
    };
  }

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String _weekday(DateTime d) => _weekdays[d.weekday - 1];

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// What the weekly review proposes. Null fields stay as they are.
class ReviewSuggestion {
  const ReviewSuggestion({
    required this.reason,
    this.targetBedtime,
    this.targetWakeUp,
    this.maxStepMinutes,
    this.maxDays,
    this.windDownLeadMinutes,
    this.napTime,
  });

  final String reason;
  final ClockTime? targetBedtime;
  final ClockTime? targetWakeUp;
  final int? maxStepMinutes;
  final int? maxDays;
  final int? windDownLeadMinutes;
  final ClockTime? napTime;

  bool get changesTargets => targetBedtime != null;

  bool get changesNothing =>
      !changesTargets &&
      maxStepMinutes == null &&
      maxDays == null &&
      windDownLeadMinutes == null &&
      napTime == null;

  RhythmSettings applyTo(RhythmSettings settings) => settings.copyWith(
    maxStepMinutes: maxStepMinutes,
    maxDays: maxDays,
    windDownLeadMinutes: windDownLeadMinutes,
    napTime: napTime,
  );

  /// Target sleep, from bedtime to wake-up.
  static const minTargetSleep = Duration(hours: 7);
  static const maxTargetSleep = Duration(hours: 10);

  /// Targets outside 20:00 to 03:00 are not a bedtime this app plans for.
  static const earliestBedtime = ClockTime(20, 0);
  static const latestBedtime = ClockTime(3, 0);

  static const napWindow = (from: ClockTime(11, 0), to: ClockTime(16, 0));

  /// Reads the model's [reply] and keeps only what is safe to apply: values
  /// are clamped to the settings' ranges, targets must give 7 to 10 hours of
  /// sleep and, with a work schedule, not wake up after it allows. Values
  /// equal to the current ones are dropped.
  static ReviewSuggestion parse(String reply, AdvisorContext context) {
    final json = decodeJsonObject(reply);
    final settings = context.settings;
    final plan = context.plan;
    final work = context.work;

    int? number(String key, ({int min, int max}) range, int current, int step) {
      final v = json[key];
      if (v is! num) return null;
      final rounded = (v / step).round() * step;
      final clamped = rounded.clamp(range.min, range.max).toInt();
      return clamped == current ? null : clamped;
    }

    var bed = ClockTime.tryParse(json['targetBedtime']);
    var wake = ClockTime.tryParse(json['targetWakeUp']);
    if (bed != null || wake != null) {
      bed ??= plan.targetBedtime;
      wake ??= plan.targetWakeUp;
      if (work != null && wake.minutes > work.latestWakeUp.minutes) {
        wake = work.latestWakeUp;
      }
      final sleep = sleepBetween(bed, wake);
      final unchanged = bed == plan.targetBedtime && wake == plan.targetWakeUp;
      if (unchanged ||
          !_isBedtime(bed) ||
          sleep < minTargetSleep ||
          sleep > maxTargetSleep) {
        bed = null;
        wake = null;
      }
    }

    ClockTime? nap;
    final napReply = ClockTime.tryParse(json['napTime']);
    if (work == null &&
        napReply != null &&
        napReply != settings.napTime &&
        napReply.minutes >= napWindow.from.minutes &&
        napReply.minutes <= napWindow.to.minutes) {
      nap = napReply;
    }

    return ReviewSuggestion(
      reason: _text(json['reason'], fallback: 'AI 没有给出理由'),
      targetBedtime: bed,
      targetWakeUp: wake,
      maxStepMinutes: number(
        'maxStepMinutes',
        RhythmSettings.stepRange,
        settings.maxStepMinutes,
        5,
      ),
      maxDays: number('maxDays', RhythmSettings.daysRange, settings.maxDays, 1),
      windDownLeadMinutes: number(
        'windDownLeadMinutes',
        RhythmSettings.windDownRange,
        settings.windDownLeadMinutes,
        5,
      ),
      napTime: nap,
    );
  }

  static bool _isBedtime(ClockTime t) =>
      t.minutes >= earliestBedtime.minutes ||
      t.minutes <= latestBedtime.minutes;
}

/// One-off nights for a temporary situation, e.g. an early train.
class TemporaryAdjustment {
  const TemporaryAdjustment({required this.nights, required this.reason});

  final Map<DateTime, NightOverride> nights;
  final String reason;

  static const maxNights = 3;
  static const minSleep = Duration(hours: 4);
  static const maxSleep = Duration(hours: 11);

  /// Reads the model's [reply], keeping nights from tonight within
  /// [AdvisorContext.upcomingNights] whose wake-up is still ahead and that
  /// give 4 to 11 hours of sleep. Throws [AiException] when none is left.
  static TemporaryAdjustment parse(String reply, AdvisorContext context) {
    final json = decodeJsonObject(reply);
    final today = context.today;
    final nights = <DateTime, NightOverride>{};
    final list = json['nights'];
    for (final item in list is List ? list : const []) {
      if (nights.length == maxNights) break;
      if (item is! Map) continue;
      final date = item['date'] is String
          ? DateTime.tryParse(item['date'] as String)
          : null;
      final bed = ClockTime.tryParse(item['bedtime']);
      final wake = ClockTime.tryParse(item['wakeUp']);
      if (date == null || bed == null || wake == null) continue;

      final night = DateTime(date.year, date.month, date.day);
      final offset = DateTime.utc(
        night.year,
        night.month,
        night.day,
      ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
      if (offset < 0 || offset >= AdvisorContext.upcomingNights) continue;

      final sleep = sleepBetween(bed, wake);
      final wakeAt = DateTime(
        night.year,
        night.month,
        night.day + 1,
        wake.hour,
        wake.minute,
      );
      if (sleep < minSleep || sleep > maxSleep) continue;
      if (!wakeAt.isAfter(context.now)) continue;
      nights[night] = NightOverride(bedtime: bed, wakeUp: wake);
    }
    if (nights.isEmpty) {
      throw const AiException('没能从这段描述排出可用的临时作息，换个说法试试');
    }
    return TemporaryAdjustment(
      nights: nights,
      reason: _text(json['reason'], fallback: ''),
    );
  }
}

/// Asks the model for the three kinds of advice. Replies are validated
/// before they reach the caller; nothing here changes the plan.
class RhythmAdvisor {
  const RhythmAdvisor({required this.transport, required this.config});

  final ChatTransport transport;
  final AiConfig config;

  Future<ReviewSuggestion> review(AdvisorContext context) async {
    final reply = await _ask(_reviewPrompt, context.toJson());
    return ReviewSuggestion.parse(reply, context);
  }

  Future<TemporaryAdjustment> adjust(
    AdvisorContext context,
    String request,
  ) async {
    final reply = await _ask(_adjustPrompt, {
      ...context.toJson(),
      'request': request.trim(),
    });
    return TemporaryAdjustment.parse(reply, context);
  }

  /// A few kind words after [recovery], for the night the user went to bed
  /// late.
  Future<String> comfort(AdvisorContext context, Recovery recovery) async {
    final wakeUp = recovery.wakeUp;
    final napAt = recovery.napAt;
    final reply = await _ask(_comfortPrompt, {
      ...context.toJson(),
      'recovery': {
        'lateMinutes': recovery.lateBy.inMinutes,
        'postponedWakeUp': wakeUp == null ? null : '${ClockTime.of(wakeUp)}',
        'napAt': napAt == null ? null : '${ClockTime.of(napAt)}',
        'replanned': recovery.isLate,
      },
    });
    final text = _text(reply.replaceAll(RegExp(r'[*#`>]'), ''), fallback: '');
    if (text.isEmpty) throw const AiException('AI 没有给出回复');
    return text;
  }

  Future<String> _ask(String instructions, Map<String, Object?> data) =>
      transport.complete(config, [
        ChatMessage.system('$_intro\n\n$instructions'),
        ChatMessage.user(const JsonEncoder.withIndent(' ').convert(data)),
      ]);

  static const _intro =
      '你是「早一点点」App 里的作息顾问。App 用渐进式计划把用户的作息调到目标：'
      '每晚最多提前 maxStepMinutes 分钟，过渡期最多 maxDays 晚；每晚有降速准备、'
      '熄灯躺平、起床三段闹钟，降速准备在熄灯前 windDownLeadMinutes 分钟；'
      '晚睡超过 15 分钟算破戒，第二天会顺延起床、安排 20 分钟午休胶囊，并从实际入睡'
      '时间重排计划。用户数据以 JSON 给出，时间都是 24 小时制 HH:mm，凌晨的就寝时间'
      '属于前一晚。work 为 null 表示用户没有填工作作息。语气温和，不说教，不指责。';

  static const _reviewPrompt =
      '请复盘最近的入睡记录，判断计划要不要调整。只输出一个 JSON 对象，不要其他文字。'
      '字段：targetBedtime、targetWakeUp（"HH:mm"，不改就省略）；maxStepMinutes'
      '（10~60）；maxDays（3~14）；windDownLeadMinutes（30~60）；napTime'
      '（"HH:mm"，填了工作作息就省略）；reason（中文，100 字以内，说明依据）。'
      '思路：经常晚睡说明步子太大，可以减小步长、延长过渡期或提前降速；连续按时可以'
      '保持或稍微加快；recentNights 里有 sleepMinutes（实际睡眠分钟数）时一并参考，经常不足 6.5 小时'
      '说明起床太早或入睡太晚；目标睡眠 7~9 小时；起床不能晚于 work.latestWakeUp；'
      '不需要改的字段就省略，都不需要改就只输出 reason。';

  static const _adjustPrompt =
      '用户在 request 里描述了接下来的临时情况。把它变成某几晚的临时作息，只输出一个'
      ' JSON 对象，不要其他文字：{"nights":[{"date":"yyyy-MM-dd","bedtime":"HH:mm",'
      '"wakeUp":"HH:mm"}],"reason":"中文，60 字以内"}。date 是就寝那一晚的日期'
      '（第二天凌晨或早上起床的，算前一晚），只能从 upcomingNights 里选；起床要留出'
      '洗漱和出门的时间（参考 work.morningMinutes）；尽量睡够 6 小时，最少 4 小时；'
      '最多 3 晚；和这次情况无关的晚上不要列出。';

  static const _comfortPrompt =
      '用户昨晚比计划晚睡了（见 recovery）。用 2~3 句话、不超过 100 字回复：先安慰，'
      '不指责；再说今天 App 已经怎么帮用户补（顺延起床、午休胶囊、重排计划，没有的就'
      '不提）；最后给一个今晚就能做到的小建议。直接输出文字，不要 JSON，不要 markdown。';
}

/// Hours from [bed] to the next [wake], bedtimes before noon counting as
/// after midnight.
Duration sleepBetween(ClockTime bed, ClockTime wake) {
  final from = bed.hour < 12 ? bed.minutes + 24 * 60 : bed.minutes;
  return Duration(minutes: 24 * 60 + wake.minutes - from);
}

/// The JSON object in a model reply, tolerating code fences and text around
/// it.
Map<String, dynamic> decodeJsonObject(String reply) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final json = jsonDecode(reply.substring(start, end + 1));
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Reported below.
    }
  }
  throw const AiException('AI 的回复格式不对，请再试一次');
}

String _text(Object? value, {required String fallback}) {
  if (value is! String) return fallback;
  final text = value.trim();
  if (text.isEmpty) return fallback;
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
