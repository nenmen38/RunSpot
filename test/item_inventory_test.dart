import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/profile_cosmetics.dart';

Widget itemApp() =>
    const MaterialApp(home: Scaffold(body: ProfileCosmetics.store()));

ButtonStyleButton button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  testWidgets('아이템 페이지는 보관함과 상점으로 나뉩니다', (tester) async {
    await tester.pumpWidget(itemApp());
    await tester.pumpAndSettle();
    expect(find.text('아이템'), findsOneWidget);
    expect(find.text('보관함'), findsOneWidget);
    expect(find.text('상점'), findsOneWidget);
    // 처음에는 보관함을 보여주고 예시 테두리가 들어 있습니다.
    expect(find.text('파란 프로필 테두리'), findsOneWidget);
    expect(find.text('예시'), findsOneWidget);

    await tester.tap(find.text('상점'));
    await tester.pumpAndSettle();
    expect(find.text('블루 컬렉션'), findsOneWidget);
    expect(find.text('착용'), findsNothing);

    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(find.text('착용'), findsOneWidget);
  });

  testWidgets('착용하면 착용 중이 표시되고 해제는 착용 중일 때만 누를 수 있습니다', (tester) async {
    await tester.pumpWidget(itemApp());
    await tester.pumpAndSettle();
    expect(find.text('착용 중'), findsNothing);
    expect(button(tester, '착용').onPressed, isNotNull);
    expect(button(tester, '해제').onPressed, isNull);

    await tester.tap(find.text('착용'));
    await tester.pumpAndSettle();
    expect(find.text('착용 중'), findsOneWidget);
    expect(button(tester, '착용').onPressed, isNull);
    expect(button(tester, '해제').onPressed, isNotNull);

    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(find.text('착용 중'), findsNothing);
    expect(button(tester, '착용').onPressed, isNotNull);
    expect(button(tester, '해제').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
