import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/character/runner_character_card.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/profile/privacy_controls.dart';

import 'support/wallet_fakes.dart';

RunnerCharacterPainter _painter(WidgetTester tester, {int index = 0}) =>
    tester
            .widgetList<CustomPaint>(
              find.byKey(const ValueKey('runner-character')),
            )
            .elementAt(index)
            .painter!
        as RunnerCharacterPainter;

Widget _app(WalletController wallet) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        ProfileIdentityHeader(
          name: '러너',
          verified: true,
          onEdit: () {},
          editLabel: '프로필 편집',
          extraAction: CharacterDressButton(wallet: wallet),
        ),
        RunnerCharacterCard(wallet: wallet),
      ],
    ),
  ),
);

void main() {
  testWidgets('꾸미기 버튼은 프로필 편집 버튼 바로 왼쪽에 있습니다', (tester) async {
    final wallet = WalletController(FakeWalletService()..coins = 0);
    await wallet.refresh();
    await tester.pumpWidget(_app(wallet));
    await tester.pumpAndSettle();
    final dress = tester.getRect(
      find.byKey(const ValueKey('character-dress-button')),
    );
    final edit = tester.getRect(find.byTooltip('프로필 편집'));
    expect(dress.right, lessThanOrEqualTo(edit.left + 1));
    expect(edit.left - dress.right, lessThan(12));
    expect((dress.center.dy - edit.center.dy).abs(), lessThan(4));
    wallet.dispose();
  });

  testWidgets('꾸미기 창에서 카테고리별로 산 아이템만 골라 입고 벗습니다', (tester) async {
    final service = FakeWalletService()
      ..coins = 1000
      ..cosmetics.addAll({
        CosmeticItem.charCapBlue,
        CosmeticItem.charHeadbandRed,
        CosmeticItem.charShoesRed,
        CosmeticItem.routeNeon,
      });
    final wallet = WalletController(service);
    await wallet.refresh();
    await tester.pumpWidget(_app(wallet));
    await tester.pumpAndSettle();
    expect(_painter(tester).outfit.hat, isNull);

    await tester.tap(find.byKey(const ValueKey('character-dress-button')));
    await tester.pumpAndSettle();
    expect(find.text('캐릭터 꾸미기'), findsOneWidget);
    for (final slot in characterSlots) {
      expect(find.byKey(ValueKey('dress-tab-${slot.code}')), findsOneWidget);
    }
    // 첫 탭(모자)에는 산 모자 두 개만 나옵니다.
    expect(find.byKey(const ValueKey('dress-char_cap_blue')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dress-char_headband_red')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dress-char_cap_black')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dress-char_cap_blue')));
    await tester.pumpAndSettle();
    expect(
      service.equippedCosmetics[CosmeticSlot.charHead],
      CosmeticItem.charCapBlue,
    );
    // 창 안의 캐릭터에도 바로 씌워집니다.
    expect(_painter(tester, index: 1).outfit.hat, isNotNull);

    // 선글라스 탭: 산 것이 없으면 안내가 나옵니다.
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_eyes')));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 산 선글라스 아이템이 없어요'), findsOneWidget);

    // 운동화 탭에서 신고, 모자 탭에서 '없음'으로 벗습니다.
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_shoes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-char_shoes_red')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_head')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-none-char_head')));
    await tester.pumpAndSettle();
    expect(service.equippedCosmetics[CosmeticSlot.charHead], isNull);
    expect(
      service.equippedCosmetics[CosmeticSlot.charShoes],
      CosmeticItem.charShoesRed,
    );

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.text('캐릭터 꾸미기'), findsNothing);
    // 프로필 캐릭터에도 그대로 반영됩니다.
    expect(_painter(tester).outfit.hat, isNull);
    expect(_painter(tester).outfit.shoes, isNotNull);
    wallet.dispose();
  });

  testWidgets('캐릭터는 좌우로 밀어 돌립니다', (tester) async {
    final wallet = WalletController(FakeWalletService()..coins = 0);
    await wallet.refresh();
    await tester.pumpWidget(_app(wallet));
    await tester.pumpAndSettle();
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
