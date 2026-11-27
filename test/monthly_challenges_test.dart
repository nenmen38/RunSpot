import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/character_outfit.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/profile/monthly_challenges.dart';

class FakeChallengeService implements ChallengeService {
  FakeChallengeService(this.json);
  Map<String, dynamic> json;
  @override
  bool get isCurrentOwner => true;
  @override
  Future<MonthlyChallenges> load() async => MonthlyChallenges.fromJson(json);
}

Map<String, dynamic> challengeJson({
  int meters = 32400,
  int weekend = 4,
  int days = 7,
  bool allDone = false,
}) => {
  'month': '2026-12-01',
  'challenges': [
    {'code': 'distance_50k', 'progress': meters, 'goal': 50000},
    {'code': 'weekend_4', 'progress': weekend, 'goal': 4},
    {'code': 'days_10', 'progress': days, 'goal': 10},
  ],
  'all_done': allDone,
  'reward_item': 'char_cap_santa',
  'completed_months': allDone ? 1 : 0,
};

void main() {
  test('산타 러닝캡은 12월 챌린지 보상이고 흰 테두리를 그립니다', () {
    expect(CosmeticItem.charCapSanta.isReward, isTrue);
    expect(CosmeticItem.charCapSanta.rewardButton, '12월 챌린지');
    expect(CosmeticItem.charCapSanta.rewardNote, '12월 챌린지 완주 보상 · 무료');
    expect(CosmeticItem.charHeadbandGold.rewardButton, 'Lv.5 선물');
    final outfit = characterOutfit([CosmeticItem.charCapSanta]);
    expect(outfit.hat, isNotNull);
    expect(outfit.hatTrim, const Color(0xFFFFFFFF));
    expect(characterOutfit([CosmeticItem.charCapBlue]).hatTrim, isNull);
  });

  testWidgets('이번 달 챌린지 진행도와 보상을 보여 줍니다', (tester) async {
    final service = FakeChallengeService(challengeJson());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [MonthlyChallengeCard(service: service)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12월 챌린지'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('32.4 / 50km'), findsOneWidget);
    expect(find.text('4 / 4번'), findsOneWidget);
    expect(find.text('7 / 10일'), findsOneWidget);
    expect(find.textContaining('🎅 산타 러닝캡'), findsOneWidget);
  });

  testWidgets('모두 마치면 선물을 받았다고 알려 줍니다', (tester) async {
    final service = FakeChallengeService(
      challengeJson(meters: 50000, days: 10, allDone: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [MonthlyChallengeCard(service: service)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('🎉 모두 완료! 산타 러닝캡을 선물로 받았어요.'), findsOneWidget);
    expect(find.text('지금까지 챌린지 완주 1번'), findsOneWidget);
  });
}
