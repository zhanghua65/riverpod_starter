import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_starter/app/modules/onboarding/views/onboarding_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget app() => const ProviderScope(
    child: MaterialApp(home: OnboardingGate(child: Text('主页'))),
  );

  testWidgets('first launch shows the guide until it is finished', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用睡了吗'), findsOneWidget);
    expect(find.text('主页'), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('开启闹钟所需权限'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets('skipping finishes the guide and it is not shown again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);
  });
}
