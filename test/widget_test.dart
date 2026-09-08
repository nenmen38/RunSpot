import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runquest/main.dart';

void main() {
  testWidgets('RunQuest shows the mobile app shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const RunQuestApp());

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
    await tester.pumpWidget(const RunQuestApp());

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
    await tester.pumpWidget(const RunQuestApp());

    final viewport = tester.getSize(find.byType(RunQuestShell));

    expect(viewport.height, greaterThan(viewport.width));
    expect(viewport.width / viewport.height, closeTo(390 / 844, .01));

    await tester.binding.setSurfaceSize(null);
  });
}
