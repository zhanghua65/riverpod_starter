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
  );

  const AlarmStage({
    required this.title,
    required this.body,
    required this.loopAudio,
  });

  final String title;
  final String body;

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
        return VolumeSettings.fade(
          fadeDuration: const Duration(seconds: 5),
          volume: 0.5,
        );
      case AlarmStage.wakeUp:
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
