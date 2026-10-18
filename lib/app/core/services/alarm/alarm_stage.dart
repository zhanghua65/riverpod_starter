import 'package:alarm/alarm.dart';

/// The three stages of the RhythmCompass alarm chain, in the order they ring.
enum AlarmStage {
  /// 降速准备：睡前 30~45 分钟的强打断提示。
  windDown(
    title: '降速准备',
    body: '放下手机，开始准备睡觉',
    loopAudio: false,
  ),

  /// 熄灯躺平：提示进入昏暗环境。
  bedtime(
    title: '熄灯躺平',
    body: '关灯，躺下，今天到此为止',
    loopAudio: false,
  ),

  /// 自然节律唤醒：音量阶梯递增的起床闹钟。
  wakeUp(
    title: '起床啦',
    body: '新的一天，慢慢醒来',
    loopAudio: true,
  ),

  /// 午休胶囊：破戒晚睡后的第二天中午，提醒小睡 20 分钟。
  nap(
    title: '午休胶囊',
    body: '昨晚睡晚了，中午小睡 20 分钟补一补',
    loopAudio: false,
  ),

  /// 午休结束：小睡 20 分钟后叫醒。
  napWake(
    title: '午休结束',
    body: '起来活动一下，喝口水',
    loopAudio: true,
  );

  /// The stages that make up one night's chain, in ringing order.
  static const chain = [windDown, bedtime, wakeUp];

  const AlarmStage({
    required this.title,
    required this.body,
    required this.loopAudio,
  });

  final String title;
  final String body;

  /// Soft chime for the reminders, a longer rising one for waking up.
  String get audioAsset => loopAudio
      ? 'assets/audio/wake.wav'
      : 'assets/audio/reminder.wav';

  /// Reminder stages ring the sound once; only the wake-up keeps ringing
  /// until the user stops it.
  final bool loopAudio;

  /// Volume curve for this stage.
  ///
  /// Wake-up follows the design doc: silent at first, 30% after 60 seconds,
  /// full volume after 180 seconds. The reminder stages fade in quickly to a
  /// moderate level so they interrupt without startling.
  VolumeSettings get volumeSettings {
    switch (this) {
      case AlarmStage.windDown:
      case AlarmStage.bedtime:
      case AlarmStage.nap:
        return VolumeSettings.fade(
          fadeDuration: const Duration(seconds: 5),
          volume: 0.5,
        );
      case AlarmStage.wakeUp:
      case AlarmStage.napWake:
        return VolumeSettings.staircaseFade(
          volume: 0.8,
          fadeSteps: [
            VolumeFadeStep(Duration.zero, 0),
            VolumeFadeStep(const Duration(seconds: 60), 0.3),
            VolumeFadeStep(const Duration(seconds: 180), 1),
          ],
        );
    }
  }
}
