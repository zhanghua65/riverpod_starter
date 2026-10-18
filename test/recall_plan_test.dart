import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/services/schedule/recall_plan.dart';

void main() {
  final now = DateTime(2026, 10, 18, 12);

  test('books a warning the evening before and a notice after the last alarm',
      () {
    final lastRing = DateTime(2026, 10, 26, 7);
    final notices = RecallPlan.plan(lastRing: lastRing, now: now);

    expect(notices.map((n) => n.id), [RecallPlan.warnId, RecallPlan.lapseId]);
    expect(notices[0].at, DateTime(2026, 10, 25, 20, 30));
    expect(notices[1].at, DateTime(2026, 10, 26, 19));
  });

  test('crosses month ends', () {
    final notices = RecallPlan.plan(
      lastRing: DateTime(2026, 11, 1, 7),
      now: now,
    );

    expect(notices[0].at, DateTime(2026, 10, 31, 20, 30));
  });

  test('leaves out the warning once it is due', () {
    // The last alarm rings tomorrow morning and tonight's 20:30 has passed.
    final late = DateTime(2026, 10, 18, 21);
    final notices = RecallPlan.plan(
      lastRing: DateTime(2026, 10, 19, 7),
      now: late,
    );

    expect(notices.map((n) => n.id), [RecallPlan.lapseId]);
  });

  test('books nothing for alarms that ran out long ago', () {
    expect(
      RecallPlan.plan(lastRing: DateTime(2026, 10, 1, 7), now: now),
      isEmpty,
    );
  });

  test('books nothing without alarms', () {
    expect(RecallPlan.plan(lastRing: null, now: now), isEmpty);
  });
}
