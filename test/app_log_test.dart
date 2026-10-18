import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/core/utils/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.resetForTest();
  });

  test('keeps lines in order and tags them', () async {
    AppLog.add('a', 'one');
    AppLog.add('b', 'two');
    final lines = await AppLog.read();
    expect(lines, hasLength(2));
    expect(lines[0], contains('[a] one'));
    expect(lines[1], contains('[b] two'));
  });

  test('drops the oldest lines past the capacity', () async {
    for (var i = 0; i < AppLog.capacity + 5; i++) {
      AppLog.add('t', 'n$i');
    }
    final lines = await AppLog.read();
    expect(lines, hasLength(AppLog.capacity));
    expect(lines.first, contains('n5'));
    expect(lines.last, contains('n${AppLog.capacity + 4}'));
  });

  test('survives a restart and can be cleared', () async {
    AppLog.add('t', 'kept');
    await AppLog.read();
    AppLog.resetForTest();
    expect(await AppLog.read(), hasLength(1));
    await AppLog.clear();
    expect(await AppLog.read(), isEmpty);
  });
}
