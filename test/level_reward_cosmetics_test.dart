import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/character_outfit.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetic_shop.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/progress/models/run_progress.dart';
import 'package:runquest/features/progress/widgets/run_reward_section.dart';

import 'support/progress_fakes.dart';
import 'support/wallet_fakes.dart';

void main() {
  test('레벨 보상 아이템은 레벨 5·10·20에 받고 캐릭터에 입혀집니다', () {
    expect(CosmeticItem.charHeadbandGold.unlockLevel, 5);
    expect(CosmeticItem.charShoesRainbow.unlockLevel, 10);
    expect(CosmeticItem.charSingletGold.unlockLevel, 20);
    expect(CosmeticItem.charCapBlue.isLevelReward, isFalse);
    final outfit = characterOutfit([
      CosmeticItem.charHeadbandGold,
      CosmeticItem.charSingletGold,
    ]);
    expect(outfit.headband, isTrue);
    expect(outfit.singlet, isTrue);
  });

  testWidgets('상점에서는 레벨 보상을 살 수 없고 받았으면 보유 중으로 보여 줍니다', (tester) async {
    final service = FakeWalletService()
      ..coins = 1000
      ..cosmetics.add(CosmeticItem.charHeadbandGold);
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [CosmeticShop(controller: wallet, onMessage: (_) {})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gold = find.byKey(const ValueKey('shop-char_headband_gold'));
    await tester.scrollUntilVisible(gold, 300);
    expect(
      find.descendant(of: gold, matching: find.text('보유 중')),
      findsOneWidget,
    );
    final rainbow = find.byKey(const ValueKey('shop-char_shoes_rainbow'));
    await tester.scrollUntilVisible(rainbow, 300);
    expect(
      find.descendant(of: rainbow, matching: find.text('Lv.10 선물')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rainbow, matching: find.text('레벨 10 달성 보상 · 무료')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rainbow, matching: find.text('구매')),
      findsNothing,
    );
  });

  testWidgets('레벨 5가 되면 레벨 업 띠에 선물 받은 아이템을 알려 줍니다', (tester) async {
    final service = FakeProgressService(
      rewards: {
        'run-1': RunReward.fromJson({
          'status': 'ready',
          'run_id': 'run-1',
          'xp': 120,
          'reason': null,
          'level_before': 4,
          'level_after': 5,
          'progress': {
            'total_xp': 720,
            'level': 5,
            'level_xp': 20,
            'next_level_xp': 300,
          },
        }),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunRewardSection(service: service, runId: 'run-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('🎁 골드 헤어밴드를 선물로 받았어요!'), findsOneWidget);
  });
}
