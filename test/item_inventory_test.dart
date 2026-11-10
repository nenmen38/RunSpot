import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/profile_cosmetics.dart';

void main() {
  testWidgets('아이템 페이지는 보관함과 상점으로 나뉩니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileCosmetics.store())),
    );
    await tester.pumpAndSettle();
    expect(find.text('아이템'), findsOneWidget);
    expect(find.text('미리보기'), findsOneWidget);
    expect(find.text('보관함이 비어 있어요.'), findsOneWidget);

    await tester.tap(find.text('상점'));
    await tester.pumpAndSettle();
    expect(find.text('블루 컬렉션'), findsOneWidget);

    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(find.text('보관함이 비어 있어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
