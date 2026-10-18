/// 根据目标就寝时间推荐起床时间。
///
/// 按 90 分钟睡眠周期推算:起床时间 = 就寝时间 + 入睡耗时 + N 个周期,
/// 这样闹钟尽量落在周期结束(浅睡)的位置,减轻睡眠惯性。
class WakeTimeRecommendation {
  /// 睡眠周期数。
  final int cycles;

  /// 推荐的起床时间(可能落在就寝日的次日)。
  final DateTime wakeTime;

  /// 实际睡眠时长(不含入睡耗时)。
  final Duration sleepDuration;

  /// 是否为首选推荐(5 个周期,约 7.5 小时)。
  final bool isPrimary;

  const WakeTimeRecommendation({
    required this.cycles,
    required this.wakeTime,
    required this.sleepDuration,
    required this.isPrimary,
  });
}

class WakeTimeRecommender {
  static const Duration cycleLength = Duration(minutes: 90);
  static const Duration fallAsleepLatency = Duration(minutes: 15);
  static const int primaryCycles = 5;

  /// 返回 4~6 个周期的推荐,按睡眠时长从短到长排序,
  /// 其中 [primaryCycles] 个周期的一项标记为首选。
  static List<WakeTimeRecommendation> recommend(DateTime bedtime) {
    return [4, 5, 6].map((cycles) {
      final sleep = cycleLength * cycles;
      return WakeTimeRecommendation(
        cycles: cycles,
        wakeTime: bedtime.add(fallAsleepLatency + sleep),
        sleepDuration: sleep,
        isPrimary: cycles == primaryCycles,
      );
    }).toList();
  }

  /// 首选推荐起床时间:就寝时间 + 15 分钟入睡 + 5×90 分钟。
  static DateTime recommendedWakeTime(DateTime bedtime) {
    return bedtime.add(fallAsleepLatency + cycleLength * primaryCycles);
  }
}
