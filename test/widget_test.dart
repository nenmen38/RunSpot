import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';

Widget testApp() {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: const MobileAppViewport(child: RunQuestShell()),
  );
}

void main() {
  testWidgets('프리셋 선택은 탭 전환 후에도 유지됩니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('코스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10K 기록 도전'));
    await tester.pumpAndSettle();
    expect(find.text('10K 도심 신호적게'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.text('10K 도심 신호적게'), findsOneWidget);
    await tester.tap(find.text('소셜').last);
    await tester.pumpAndSettle();
    expect(find.text('친구 랭킹'), findsOneWidget);
    await tester.tap(find.text('성장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('관리').last);
    await tester.pumpAndSettle();
    expect(find.text('이상 기록'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.text('10K 도심 신호적게'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RunQuest shows the mobile app shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(testApp());

    expect(find.text('오늘은\n어디로 달릴까요?'), findsOneWidget);
    expect(find.text('코스 다시 만들기'), findsOneWidget);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('소셜'), findsOneWidget);
    expect(find.text('관리'), findsOneWidget);

    await tester.tap(find.text('코스'));
    await tester.pumpAndSettle();

    expect(find.text('코스 만들기'), findsOneWidget);
    expect(find.text('5가지만 고르면 추천 완료'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('RunQuest stays phone-sized on desktop web', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(testApp());

    final viewport = tester.getSize(find.byType(RunQuestShell));

    expect(viewport.width, lessThanOrEqualTo(430));
    expect(viewport.height, greaterThan(viewport.width));
    expect(find.text('오늘은\n어디로 달릴까요?'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('RunQuest keeps portrait ratio in a wide short browser', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 500));
    await tester.pumpWidget(testApp());

    final viewport = tester.getSize(find.byType(RunQuestShell));

    expect(viewport.height, greaterThan(viewport.width));
    expect(viewport.width / viewport.height, closeTo(390 / 844, .01));

    await tester.binding.setSurfaceSize(null);
  });
}
