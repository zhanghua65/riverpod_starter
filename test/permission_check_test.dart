import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod_starter/app/core/services/alarm/alarm_permissions.dart';
import 'package:riverpod_starter/app/modules/permissions/views/permission_check_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Off Android nothing can be withheld and no platform channel is used.
  test('check reports everything granted off Android', () async {
    final report = await AlarmPermissions.check();
    expect(report.allGranted, isTrue);
  });

  testWidgets('shows readable statuses and the manual items', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PermissionCheckView()));
    await tester.pumpAndSettle();

    expect(find.text('权限自检'), findsOneWidget);
    expect(find.text('已允许'), findsNWidgets(4));
    expect(find.text('通知渠道'), findsOneWidget);
    expect(find.text('诊断日志'), findsOneWidget);
    // The vendor switches only show on Xiaomi phones.
    expect(find.text('锁屏显示、后台弹出界面'), findsNothing);
  });
}
