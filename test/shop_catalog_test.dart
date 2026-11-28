import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/shop_catalog.dart';

import 'support/wallet_fakes.dart';

void main() {
  testWidgets('상점은 분류 칩으로 한 분류씩 보여 줍니다', (tester) async {
    final wallet = WalletController(FakeWalletService()..coins = 1000);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [ShopCatalog(wallet: wallet, onMessage: (_) {})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final category in ShopCategory.values) {
      expect(
        find.byKey(ValueKey('shop-category-${category.name}')),
        findsOneWidget,
      );
    }
    // 처음은 캐릭터 > 헤어스타일: 여자·남자 머리만 보이고 다른 분류는 숨김.
    expect(find.byKey(const ValueKey('shop-char_hair_dandy')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-char_hair_bob')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-char_cap_blue')), findsNothing);
    expect(
      find.byKey(const ValueKey('shop-char_haircolor_pink')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('shop-basic')), findsNothing);
    expect(find.byKey(const ValueKey('shop-route_neon')), findsNothing);

    // 캐릭터 안의 작은 묶음: 모자·선글라스.
    await tester.tap(find.byKey(const ValueKey('shop-group-accessory')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('shop-char_cap_blue')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-char_hair_bob')), findsNothing);

    // 지도: 테두리와 경로 색.
    await tester.tap(find.byKey(const ValueKey('shop-category-map')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('shop-basic')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-route_neon')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-crew-ticket')), findsNothing);
    expect(find.byKey(const ValueKey('shop-char_cap_blue')), findsNothing);

    // 칭호·채팅.
    await tester.tap(find.byKey(const ValueKey('shop-category-profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('shop-title_gold')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-bubble_mint')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-basic')), findsNothing);

    // 크루: 생성권만(테두리는 없음).
    await tester.tap(find.byKey(const ValueKey('shop-category-crew')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('shop-crew-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-basic')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
