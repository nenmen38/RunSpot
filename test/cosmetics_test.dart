import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/crew/crew_controller.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetic_shop.dart';
import 'package:runquest/features/monetization/cosmetics.dart';

import 'support/crew_fakes.dart';
import 'support/wallet_fakes.dart';

void main() {
  testWidgets('꾸미기 아이템을 사고 보관함에서 칸마다 하나씩 착용·해제합니다', (tester) async {
    final service = FakeWalletService()..coins = 1000;
    final wallet = WalletController(service);
    await wallet.refresh();
    final messages = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CosmeticShop(
                controller: wallet,
                onCharge: () => messages.add('충전'),
                onMessage: messages.add,
              ),
              CosmeticInventory(controller: wallet, onMessage: messages.add),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 경로 색 네온 핑크(400코인)를 삽니다.
    final buyNeon = find.descendant(
      of: find.byKey(const ValueKey('shop-route_neon')),
      matching: find.text('구매'),
    );
    await tester.ensureVisible(buyNeon);
    await tester.pumpAndSettle();
    await tester.tap(buyNeon);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '구매').last);
    await tester.pumpAndSettle();
    expect(service.coins, 600);
    expect(wallet.wallet!.cosmetics, {CosmeticItem.routeNeon});

    // 코인이 모자란 아이템은 충전 창으로 안내합니다.
    final flame = find.descendant(
      of: find.byKey(const ValueKey('shop-aura_flame')),
      matching: find.text('코인 충전'),
    );
    await tester.ensureVisible(flame);
    await tester.pumpAndSettle();
    await tester.tap(flame);
    await tester.pump();
    expect(messages, contains('충전'));

    // 보관함에서 착용하고 해제합니다.
    final wear = find.descendant(
      of: find.byKey(const ValueKey('inventory-route_neon')),
      matching: find.text('착용'),
    );
    await tester.ensureVisible(wear);
    await tester.pumpAndSettle();
    await tester.tap(wear);
    await tester.pumpAndSettle();
    expect(wallet.equippedIn(CosmeticSlot.route), CosmeticItem.routeNeon);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('inventory-route_neon')),
        matching: find.text('해제'),
      ),
    );
    await tester.pumpAndSettle();
    expect(wallet.equippedIn(CosmeticSlot.route), isNull);
    wallet.dispose();
  });

  testWidgets('크루장은 자기 크루 정원을 한 번 50명으로 늘립니다', (tester) async {
    final service = FakeWalletService()..coins = 1500;
    final wallet = WalletController(service);
    await wallet.refresh();
    final crews = FakeCrewService()
      ..crews = [
        FakeCrewService.crewJson(),
        FakeCrewService.crewJson(owner: false, id: 'crew-2', name: '저녁런'),
      ];
    final crew = CrewController(crews);
    await crew.refresh();
    final messages = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CrewExpansionShop(
                controller: wallet,
                crew: crew,
                onCharge: () {},
                onMessage: messages.add,
              ),
            ],
          ),
        ),
      ),
    );
    // 크루장인 크루만 보입니다.
    expect(find.byKey(const ValueKey('expand-crew-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('expand-crew-2')), findsNothing);
    await tester.tap(find.text('정원 늘리기'));
    await tester.pumpAndSettle();
    expect(service.calls, contains('expand:crew-1'));
    expect(service.coins, 500);
    expect(messages.last, '새벽런 정원을 50명으로 늘렸어요.');
    wallet.dispose();
    crew.dispose();
  });
}
