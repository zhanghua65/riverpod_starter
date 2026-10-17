import 'package:alarm/alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_stage.dart';

void main() {
  final chain = AlarmChain(
    windDown: DateTime(2026, 10, 17, 23, 15),
    bedtime: DateTime(2026, 10, 17, 23, 45),
    wakeUp: DateTime(2026, 10, 18, 7, 15),
  );

  test('ids are unique per stage, keyed by the night, and fit in 32 bits', () {
    expect(chain.ids, [202610170, 202610171, 202610172]);
    expect(chain.ids.every((id) => id < 0x7fffffff), isTrue);
    expect(AlarmChain.stageOf(202610172), AlarmStage.wakeUp);
  });

  test('consecutive nights do not collide', () {
    final next = AlarmChain(
      windDown: DateTime(2026, 10, 18, 23, 0),
      bedtime: DateTime(2026, 10, 18, 23, 30),
      wakeUp: DateTime(2026, 10, 19, 7, 0),
    );
    expect(next.ids.toSet().intersection(chain.ids.toSet()), isEmpty);
  });

  test('stages in the past are skipped', () {
    final settings = chain.toAlarmSettings(now: DateTime(2026, 10, 17, 23, 30));
    expect(settings.map((s) => s.id), [202610171, 202610172]);
  });

  test('wake-up uses the staircase volume curve and loops', () {
    final wake = chain.settingsFor(AlarmStage.wakeUp);
    expect(wake.dateTime, DateTime(2026, 10, 18, 7, 15));
    expect(wake.loopAudio, isTrue);
    expect(wake.volumeSettings.fadeSteps.map((s) => s.volume), [0, 0.3, 1]);
    expect(
      wake.volumeSettings.fadeSteps.last.time,
      const Duration(seconds: 180),
    );
  });

  test('reminder stages ring once with a short fade', () {
    final windDown = chain.settingsFor(AlarmStage.windDown);
    expect(windDown.loopAudio, isFalse);
    expect(windDown.volumeSettings.fadeDuration, const Duration(seconds: 5));
    expect(windDown.notificationSettings.title, '降速准备');
  });

  test('every setting passes the plugin validation', () {
    for (final s in chain.toAlarmSettings(now: DateTime(2026, 10, 17))) {
      expect(() => Alarm.alarmSettingsValidation(s), returnsNormally);
    }
  });
}
