import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/monetization/inventory_catalog.dart';
import 'package:runquest/features/monetization/shop_catalog.dart';

import 'support/wallet_fakes.dart';

class _Host extends StatefulWidget {
  const _Host({required this.wallet, required this.shops});
  final WalletController wallet;
  final List<ShopCategory> shops;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  ShopCategory? category;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          InventoryCatalog(
            wallet: widget.wallet,
            category: category,
            onCategory: (value) => setState(() => category = value),
            onShop: widget.shops.add,
            onMessage: (_) {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('보관함은 상점과 같은 분류로 가진 아이템만 보여 주고 캐릭터도 입고 벗습니다', (tester) async {
    final service = FakeWalletService()
      ..owned.add(FrameKind.basic)
      ..cosmetics.addAll({
        CosmeticItem.routeNeon,
        CosmeticItem.charHairDandy,
        CosmeticItem.charCapBlue,
      });
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    final shops = <ShopCategory>[];
    await tester.pumpWidget(_Host(wallet: wallet, shops: shops));
    await tester.pumpAndSettle();
    for (final category in ShopCategory.values) {
      expect(
        find.byKey(ValueKey('inventory-category-${category.name}')),
        findsOneWidget,
      );
    }
    // 처음은 가진 아이템이 있는 첫 분류(캐릭터) > 헤어스타일.
    final dandy = find.byKey(const ValueKey('inventory-char_hair_dandy'));
    expect(dandy, findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-char_cap_blue')), findsNothing);
    expect(find.byKey(const ValueKey('frame-basic')), findsNothing);
    await tester.tap(find.descendant(of: dandy, matching: find.text('착용')));
    await tester.pumpAndSettle();
    expect(
      wallet.equippedIn(CosmeticSlot.charHair),
      CosmeticItem.charHairDandy,
    );
    await tester.tap(find.descendant(of: dandy, matching: find.text('해제')));
    await tester.pumpAndSettle();
    expect(wallet.equippedIn(CosmeticSlot.charHair), isNull);

    // 캐릭터 안의 작은 묶음.
    await tester.tap(find.byKey(const ValueKey('inventory-group-accessory')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('inventory-char_cap_blue')),
      findsOneWidget,
    );
    // 가진 게 없는 묶음은 상점의 같은 분류로 안내합니다.
    await tester.tap(find.byKey(const ValueKey('inventory-group-pet')));
    await tester.pumpAndSettle();
    expect(find.text('반려동물 아이템이 아직 없어요.'), findsOneWidget);

    // 지도: 테두리와 경로 색만.
    await tester.tap(find.byKey(const ValueKey('inventory-category-map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('frame-basic')), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-route_neon')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inventory-char_hair_dandy')),
      findsNothing,
    );

    // 비어 있는 분류: 안내와 '상점 보기'(같은 분류).
    await tester.tap(find.byKey(const ValueKey('inventory-category-crew')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inventory-empty-crew')), findsOneWidget);
    await tester.tap(find.text('상점 보기'));
    expect(shops, [ShopCategory.crew]);
    expect(tester.takeException(), isNull);
  });
}
