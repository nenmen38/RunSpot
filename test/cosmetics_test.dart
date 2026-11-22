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
              CosmeticShop(controller: wallet, onMessage: messages.add),
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

    final rainbow = find.byKey(const ValueKey('shop-route_rainbow'));
    final preview = find.descendant(
      of: rainbow,
      matching: find.byTooltip('미리보기'),
    );
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.coins, 600);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(find.text('200코인 부족'), findsNothing);
    final buyRainbow = find.descendant(of: rainbow, matching: find.text('구매'));
    await tester.ensureVisible(buyRainbow);
    await tester.tap(buyRainbow);
    await tester.pumpAndSettle();
    expect(find.text('200코인 부족'), findsOneWidget);
    expect(find.text('코인 충전'), findsNothing);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 보관함에서 착용하고 해제합니다.
    final wear = find.descendant(
      of: find.byKey(const ValueKey('inventory-route_neon')),
      matching: find.text('착용'),
    );
    // 목록이 길어 보관함이 아직 그려지지 않았을 수 있으니 내려가며 찾습니다.
    await tester.scrollUntilVisible(wear, 300);
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
    await tester.tap(find.text('구매'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '구매').last);
    await tester.pumpAndSettle();
    expect(service.calls, contains('expand:crew-1'));
    expect(service.coins, 500);
    expect(messages.last, '새벽런 정원을 50명으로 늘렸어요.');
    wallet.dispose();
    crew.dispose();
  });

  test('경로 색 아이템으로 지나온 길을 칠하고 무지개는 조각마다 색을 돌립니다', () {
    final route = [List.generate(20, (i) => i)];
    expect(skinRoute(route, null).colors, isNull);
    final gold = skinRoute(route, CosmeticItem.routeGold);
    expect(gold.segments, route);
    expect(gold.colors, ['#d4a017']);
    final rainbow = skinRoute(route, CosmeticItem.routeRainbow, chunk: 8);
    expect(rainbow.segments.map((s) => s.first), [0, 8, 16]);
    // 조각 끝점이 다음 조각 시작점과 겹쳐 선이 이어집니다.
    expect(rainbow.segments.first.last, 8);
    expect(rainbow.segments.last.last, 19);
    expect(rainbow.colors, ['#ef4444', '#f97316', '#facc15']);
  });
}
