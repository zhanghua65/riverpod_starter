import 'package:alarm/alarm.dart';

import 'alarm_stage.dart';

/// One night's alarm chain: wind-down, bedtime and the next morning's wake-up.
///
/// Each chain is keyed by its [night], so several nights can be registered at
/// once without their ids colliding.
class AlarmChain {
  AlarmChain({
    required this.windDown,
    required this.bedtime,
    required this.wakeUp,
    DateTime? night,
  })  : night = _dateOnly(night ?? bedtime),
        assert(windDown.isBefore(bedtime), 'windDown must be before bedtime'),
        assert(bedtime.isBefore(wakeUp), 'bedtime must be before wakeUp');

  final DateTime windDown;
  final DateTime bedtime;
  final DateTime wakeUp;

  /// The date this chain belongs to. Defaults to the date of [bedtime]; pass
  /// it explicitly when bedtime can fall after midnight, otherwise a 00:30
  /// bedtime and the next evening's 23:45 bedtime would share a night.
  final DateTime night;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime timeOf(AlarmStage stage) {
    switch (stage) {
      case AlarmStage.windDown:
        return windDown;
      case AlarmStage.bedtime:
        return bedtime;
      case AlarmStage.wakeUp:
        return wakeUp;
    }
  }

  /// Alarm id for [stage] on [night]: `yyyyMMdd * 10 + stage index`.
  ///
  /// Fits in a 32-bit int (the Android side stores ids as Int), and lets
  /// [stageOf] recover the stage from an id.
  static int idFor(DateTime night, AlarmStage stage) =>
      (night.year * 10000 + night.month * 100 + night.day) * 10 + stage.index;

  static AlarmStage? stageOf(int id) {
    final index = id % 10;
    return index < AlarmStage.values.length ? AlarmStage.values[index] : null;
  }

  List<int> get ids => [for (final s in AlarmStage.values) idFor(night, s)];

  /// Settings for every stage whose time is still in the future.
  List<AlarmSettings> toAlarmSettings({DateTime? now}) {
    final current = now ?? DateTime.now();
    return [
      for (final stage in AlarmStage.values)
        if (timeOf(stage).isAfter(current)) settingsFor(stage),
    ];
  }

  AlarmSettings settingsFor(AlarmStage stage) => AlarmSettings(
        id: idFor(night, stage),
        dateTime: timeOf(stage),
        assetAudioPath: null, // device default alarm sound
        loopAudio: stage.loopAudio,
        vibrate: true,
        volumeSettings: stage.volumeSettings,
        androidFullScreenIntent: true,
        warningNotificationOnKill: true,
        payload: stage.name,
        notificationSettings: NotificationSettings(
          title: stage.title,
          body: stage.body,
          stopButton: '停止',
        ),
      );
}
