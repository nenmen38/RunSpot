import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/character/runner_character_card.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';

import 'support/wallet_fakes.dart';

RunnerCharacterPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('runner-character')))
            .painter!
        as RunnerCharacterPainter;

void main() {
  testWidgets('꾸미기에는 산 캐릭터 아이템만 나오고 누르면 바로 입고 벗습니다', (tester) async {
    final service = FakeWalletService()
      ..coins = 1000
      ..cosmetics.addAll({
        CosmeticItem.charCapBlue,
        CosmeticItem.charShoesRed,
        CosmeticItem.routeNeon,
      });
    final wallet = WalletController(service);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [RunnerCharacterCard(wallet: wallet)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('꾸미기'), findsOneWidget);
    expect(find.byKey(const ValueKey('outfit-char_cap_blue')), findsOneWidget);
    expect(find.byKey(const ValueKey('outfit-char_shoes_red')), findsOneWidget);
    // 캐릭터 아이템이 아닌 것과 사지 않은 것은 나오지 않습니다.
    expect(find.byKey(const ValueKey('outfit-route_neon')), findsNothing);
    expect(find.byKey(const ValueKey('outfit-char_shoes_neon')), findsNothing);
    expect(_painter(tester).outfit.hat, isNull);

    await tester.tap(find.byKey(const ValueKey('outfit-char_cap_blue')));
    await tester.pumpAndSettle();
    expect(
      service.equippedCosmetics[CosmeticSlot.charHead],
      CosmeticItem.charCapBlue,
    );
    expect(_painter(tester).outfit.hat, isNotNull);

    await tester.tap(find.byKey(const ValueKey('outfit-char_shoes_red')));
    await tester.pumpAndSettle();
    expect(_painter(tester).outfit.shoes, isNotNull);

    // 한 번 더 누르면 벗습니다.
    await tester.tap(find.byKey(const ValueKey('outfit-char_cap_blue')));
    await tester.pumpAndSettle();
    expect(service.equippedCosmetics[CosmeticSlot.charHead], isNull);
    expect(_painter(tester).outfit.hat, isNull);
    expect(_painter(tester).outfit.shoes, isNotNull);
    wallet.dispose();
  });

  testWidgets('아이템이 없으면 상점 안내가 나오고 캐릭터는 좌우로 밀어 돌립니다', (tester) async {
    final wallet = WalletController(FakeWalletService()..coins = 0);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [RunnerCharacterCard(wallet: wallet)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('내 러너 캐릭터 꾸미기'), findsOneWidget);

    final before = _painter(tester).yaw;
    await tester.drag(
      find.byKey(const ValueKey('runner-character')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(_painter(tester).yaw, isNot(closeTo(before, 0.5)));
    wallet.dispose();
  });
}
