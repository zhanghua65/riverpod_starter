import 'package:flutter_test/flutter_test.dart';

import 'package:riverpod_starter/app/core/utils/wake_time_recommender.dart';

void main() {
  test('23:00 bedtime recommends 06:45 wake time', () {
    final bedtime = DateTime(2026, 10, 18, 23, 0);
    expect(
      WakeTimeRecommender.recommendedWakeTime(bedtime),
      DateTime(2026, 10, 19, 6, 45),
    );
  });

  test('recommend returns 4/5/6 cycles with only 5 as primary', () {
    final list = WakeTimeRecommender.recommend(DateTime(2026, 10, 18, 23, 0));
    expect(list.map((e) => e.cycles), [4, 5, 6]);
    expect(list.where((e) => e.isPrimary).single.cycles, 5);
    expect(list.first.wakeTime, DateTime(2026, 10, 19, 5, 15));
    expect(list.last.wakeTime, DateTime(2026, 10, 19, 8, 15));
  });
}
