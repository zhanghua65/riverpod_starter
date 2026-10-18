import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/base/base_controller.dart';
import '/app/core/utils/wake_time_recommender.dart';

class SettingsController extends BaseController {
  SettingsController({
    required Ref<ChangeNotifier> ref,
  }) : super(ref: ref);

  TimeOfDay _bedtime = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay get bedtime => _bedtime;

  /// 用户手动选择的起床时间;为空时采用首选推荐。
  TimeOfDay? _wakeTime;

  List<WakeTimeRecommendation> get recommendations =>
      WakeTimeRecommender.recommend(_bedtimeAsDateTime());

  TimeOfDay get wakeTime =>
      _wakeTime ?? _toTimeOfDay(recommendations.firstWhere((e) => e.isPrimary).wakeTime);

  bool get isWakeTimeRecommended => _wakeTime == null;

  void setBedtime(TimeOfDay time) {
    _bedtime = time;
    // 就寝时间变化后,重新跟随推荐。
    _wakeTime = null;
    notifyListeners();
  }

  void setWakeTime(TimeOfDay time) {
    _wakeTime = time;
    notifyListeners();
  }

  DateTime _bedtimeAsDateTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, _bedtime.hour, _bedtime.minute);
  }

  TimeOfDay _toTimeOfDay(DateTime time) =>
      TimeOfDay(hour: time.hour, minute: time.minute);
}
