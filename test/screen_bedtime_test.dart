import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_chain.dart';
import 'package:riverpod_starter/app/core/services/schedule/screen_bedtime.dart';

void main() {
  // Night of Oct 10: bed at 23:00, up at 07:00.
  final planned = AlarmChain(
    windDown: DateTime(2026, 10, 10, 22, 15),
    bedtime: DateTime(2026, 10, 10, 23),
    wakeUp: DateTime(2026, 10, 11, 7),
  );
  final morning = DateTime(2026, 10, 11, 9);

  DateTime at(int day, int hour, [int minute = 0, int second = 0]) =>
      DateTime(2026, 10, day, hour, minute, second);
  ScreenEvent on(DateTime t) => ScreenEvent(t, on: true);
  ScreenEvent off(DateTime t) => ScreenEvent(t, on: false);

  DateTime? infer(List<ScreenEvent> events, {DateTime? now}) =>
      ScreenBedtime.infer(
        planned: planned,
        events: events,
        now: now ?? morning,
      );

  test('the last screen-off before the night is the bedtime', () {
    expect(
      infer([
        on(at(10, 21)),
        off(at(10, 21, 40)),
        on(at(10, 22)),
        off(at(11, 1, 12)),
        on(at(11, 7, 2)),
      ]),
      at(11, 1, 12),
    );
  });

  test('a short glance at night does not split the sleep', () {
    expect(
      infer([
        off(at(10, 23, 30)),
        on(at(11, 3)),
        off(at(11, 3, 2)),
        on(at(11, 7)),
      ]),
      at(10, 23, 30),
    );
  });

  test('using the phone for a while in the evening is not sleep', () {
    expect(
      infer([
        off(at(10, 19)),
        on(at(10, 20, 30)),
        off(at(10, 23, 45)),
        on(at(11, 6, 50)),
      ]),
      at(10, 23, 45),
    );
  });

  test('the first long stretch wins over a longer one after a night wake', () {
    expect(
      infer([
        off(at(10, 23)),
        on(at(11, 2, 30)),
        off(at(11, 3, 10)),
        on(at(11, 7, 30)),
      ]),
      at(10, 23),
    );
  });

  test('events can come in any order', () {
    expect(
      infer([on(at(11, 7)), off(at(10, 23, 50)), on(at(10, 22))]),
      at(10, 23, 50),
    );
  });

  test('a screen still off counts up to now', () {
    expect(
      infer([on(at(10, 22)), off(at(10, 23, 10))], now: at(11, 7, 5)),
      at(10, 23, 10),
    );
  });

  test('nothing is found when the phone was never put down for long', () {
    expect(
      infer([
        off(at(10, 23)),
        on(at(11, 1)),
        off(at(11, 1, 30)),
      ], now: at(11, 3)),
      isNull,
    );
  });

  test('a screen-off after the planned wake-up is not the bedtime', () {
    expect(infer([on(at(10, 22)), off(at(11, 7, 30))]), isNull);
  });

  test('no events, no bedtime', () {
    expect(infer(const []), isNull);
  });

  test('events outside the window are ignored', () {
    expect(
      infer([
        off(at(10, 12)),
        on(at(10, 21)),
        off(at(11, 0, 20)),
        on(at(11, 6, 40)),
      ]),
      at(11, 0, 20),
    );
  });

  group('wake-up', () {
    DateTime? wakeUp(
      List<ScreenEvent> events, {
      DateTime? bedtime,
      DateTime? now,
    }) => ScreenBedtime.inferWakeUp(
      planned: planned,
      events: events,
      bedtime: bedtime ?? at(10, 23),
      now: now ?? morning,
    );

    test('the first 10 minutes of use after sleep is the wake-up', () {
      expect(
        wakeUp([
          off(at(10, 23)),
          on(at(11, 7)),
          off(at(11, 7, 1)),
          on(at(11, 7, 20)),
          off(at(11, 7, 45)),
        ]),
        at(11, 7, 20),
      );
    });

    test('use still going on counts up to now', () {
      expect(
        wakeUp([off(at(10, 23)), on(at(11, 6, 50))], now: at(11, 7, 1)),
        at(11, 6, 50),
      );
      expect(
        wakeUp([off(at(10, 23)), on(at(11, 6, 55))], now: at(11, 7, 1)),
        isNull,
      );
    });

    test('the screen timing out briefly does not break the use', () {
      expect(
        wakeUp([
          off(at(10, 23)),
          on(at(11, 7)),
          off(at(11, 7, 6)),
          on(at(11, 7, 6, 30)),
          off(at(11, 7, 12)),
        ]),
        at(11, 7),
      );
    });

    test(
      'using the phone at night before sleeping again is not getting up',
      () {
        expect(
          wakeUp([
            off(at(10, 23)),
            on(at(11, 2, 30)),
            off(at(11, 3)),
            on(at(11, 7, 10)),
          ]),
          at(11, 7, 10),
        );
      },
    );

    test('scrolling after tapping "我已躺下" is not getting up', () {
      expect(
        wakeUp([
          on(at(10, 23)),
          off(at(10, 23, 30)),
          on(at(11, 6, 40)),
          off(at(11, 7)),
        ], bedtime: at(10, 23, 1)),
        at(11, 6, 40),
      );
    });

    test('nothing while still asleep or without a night of sleep', () {
      expect(wakeUp([off(at(10, 23))], now: at(11, 6)), isNull);
      expect(
        wakeUp([off(at(10, 23)), on(at(11, 1)), off(at(11, 1, 30))]),
        isNull,
      );
    });
  });
}
