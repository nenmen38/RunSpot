import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/runner_celebration.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/character/runner_character_directory.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/progress/models/run_progress.dart';
import 'package:runquest/features/progress/widgets/run_reward_section.dart';

import 'support/progress_fakes.dart';

class FakeCharacterSource implements RunnerCharacterSource {
  final calls = <List<String>>[];
  final outfits = <String, List<CosmeticItem>>{};

  @override
  bool get isCurrentOwner => true;

  @override
  Future<Map<String, List<CosmeticItem>>> load(List<String> userIds) async {
    calls.add(userIds);
    return {
      for (final id in userIds)
        if (outfits.containsKey(id)) id: outfits[id]!,
    };
  }
}

RunnerCharacterPainter _painter(WidgetTester tester, String key) =>
    tester.widget<CustomPaint>(find.byKey(ValueKey(key))).painter!
        as RunnerCharacterPainter;

void main() {
  tearDown(RunnerCharacterDirectory.instance.unbind);

  testWidgets('크루원 캐릭터를 한 번에 불러와 입은 옷대로 보여 줍니다', (tester) async {
    final source = FakeCharacterSource()
      ..outfits['u1'] = [CosmeticItem.charCapBlue, CosmeticItem.charShoesRed];
    RunnerCharacterDirectory.instance.bind(source);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CrewRunnersStrip(
            members: [
              (userId: 'u1', nickname: '크루장', owner: true),
              (userId: 'u2', nickname: '크루원', owner: false),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(1));
    expect(source.calls.single, unorderedEquals(['u1', 'u2']));
    expect(_painter(tester, 'user-runner-u1').outfit.hat, isNotNull);
    expect(_painter(tester, 'user-runner-u1').outfit.shoes, isNotNull);
    // 아무것도 안 입었거나 볼 수 없는 사람은 맨몸 캐릭터입니다.
    expect(_painter(tester, 'user-runner-u2').outfit, CharacterOutfit.none);
    expect(find.text('👑 크루장'), findsOneWidget);

    // 내가 옷을 바꾸면 다시 불러옵니다.
    RunnerCharacterDirectory.instance.invalidate();
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(2));
  });

  testWidgets('완주 축하는 몇 번 뛴 뒤 만세 자세로 멈춥니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RunnerCelebration(outfit: CharacterOutfit(hat: Colors.blue)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 360));
    expect(_painter(tester, 'celebrating-runner').hop, greaterThan(0));
    await tester.pumpAndSettle();
    final painter = _painter(tester, 'celebrating-runner');
    expect(painter.hop, 0);
    expect(painter.cheer, 1);
    expect(painter.outfit.hat, isNotNull);
    expect(find.text('오늘도 완주했어요!'), findsOneWidget);
  });

  testWidgets('레벨이 오르면 내 캐릭터가 레벨 업 띠에서 만세합니다', (tester) async {
    final service = FakeProgressService(
      rewards: {
        'run-1': RunReward.fromJson({
          'status': 'ready',
          'run_id': 'run-1',
          'xp': 70,
          'reason': null,
          'level_before': 1,
          'level_after': 2,
          'progress': {
            'total_xp': 130,
            'level': 2,
            'level_xp': 30,
            'next_level_xp': 150,
          },
        }),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunRewardSection(
            service: service,
            runId: 'run-1',
            outfit: const CharacterOutfit(shoes: Colors.red),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('레벨 업!'), findsOneWidget);
    expect(_painter(tester, 'level-up-runner').outfit.shoes, isNotNull);
    expect(find.byIcon(Icons.emoji_events), findsNothing);
  });
}
