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

  /// Time of a chain stage; throws for stages outside [AlarmStage.chain].
  DateTime timeOf(AlarmStage stage) {
    switch (stage) {
      case AlarmStage.windDown:
        return windDown;
      case AlarmStage.bedtime:
        return bedtime;
      case AlarmStage.wakeUp:
        return wakeUp;
      case AlarmStage.nap:
      case AlarmStage.napWake:
        throw ArgumentError.value(stage, 'stage', 'not part of the chain');
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

  /// The night encoded in an id from [idFor].
  static DateTime nightOf(int id) {
    final date = id ~/ 10;
    return DateTime(date ~/ 10000, date ~/ 100 % 100, date % 100);
  }

  List<int> get ids => [for (final s in AlarmStage.chain) idFor(night, s)];

  /// Settings for every stage whose time is still in the future.
  List<AlarmSettings> toAlarmSettings({DateTime? now}) {
    final current = now ?? DateTime.now();
    return [
      for (final stage in AlarmStage.chain)
        if (timeOf(stage).isAfter(current)) settingsFor(stage),
    ];
  }

  AlarmSettings settingsFor(AlarmStage stage) =>
      settingsAt(night, stage, timeOf(stage));

  /// Settings for [stage] of [night] ringing at [time]; also used for stages
  /// outside the chain, such as the nap capsule.
  static AlarmSettings settingsAt(
    DateTime night,
    AlarmStage stage,
    DateTime time,
  ) =>
      AlarmSettings(
        id: idFor(night, stage),
        dateTime: time,
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
