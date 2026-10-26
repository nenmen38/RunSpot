import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/progress/models/run_progress.dart';
import 'package:runquest/features/progress/widgets/profile_level_card.dart';
import 'package:runquest/features/progress/widgets/run_reward_section.dart';

import 'support/progress_fakes.dart';

Map<String, dynamic> rewardJson({
  int xp = 70,
  String? reason,
  int before = 1,
  int after = 2,
}) => {
  'status': 'ready',
  'run_id': 'run-1',
  'xp': xp,
  'reason': reason,
  'level_before': before,
  'level_after': after,
  'progress': {
    'total_xp': 130,
    'level': 2,
    'level_xp': 30,
    'next_level_xp': 150,
  },
};

void main() {
  group('경험치 응답', () {
    test('진행도와 보상을 읽습니다', () {
      final reward = RunReward.fromJson(rewardJson())!;
      expect(reward.xp, 70);
      expect(reward.leveledUp, isTrue);
      expect(reward.reasonMessage, isNull);
      expect(reward.progress.fraction, closeTo(.2, 1e-9));
      expect(reward.progress.remainingXp, 120);
    });

    test('보상 대상이 아니면 null입니다', () {
      expect(RunReward.fromJson({'status': 'unavailable'}), isNull);
    });

    test('지급 제외 사유를 안내합니다', () {
      final reward = RunReward.fromJson(
        rewardJson(xp: 0, reason: 'daily_limit', after: 1),
      )!;
      expect(reward.reason, RewardReason.dailyLimit);
      expect(reward.reasonMessage, contains('500 XP'));
      expect(reward.leveledUp, isFalse);
    });

    test('검토 중 보상은 지급되지 않고 레벨 상승을 표시하지 않습니다', () {
      final reward = RunReward.fromJson(
        rewardJson(xp: 0, reason: 'review_pending', after: 1),
      )!;
      expect(reward.reason, RewardReason.reviewPending);
      expect(reward.reasonMessage, '검토 중 · 승인 후 경험치 지급');
      expect(reward.leveledUp, isFalse);
    });

    test('최대 레벨은 다음 목표가 없습니다', () {
      final progress = RunProgress.fromJson({
        'total_xp': 999999,
        'level': 99,
        'level_xp': 500,
        'next_level_xp': null,
      });
      expect(progress.isMaxLevel, isTrue);
      expect(progress.fraction, 1);
    });

    test('잘못된 응답을 거부합니다', () {
      for (final json in [
        {...rewardJson(), 'status': 'pending'},
        {...rewardJson(), 'xp': -1},
        {...rewardJson(), 'reason': 'bonus'},
        rewardJson(before: 3, after: 2),
        {
          ...rewardJson(),
          'progress': {
            'total_xp': 10,
            'level': 1,
            'level_xp': 120,
            'next_level_xp': 100,
          },
        },
      ]) {
        expect(() => RunReward.fromJson(json), throwsFormatException);
      }
    });

    test('레벨 칭호', () {
      expect(levelTitle(1), '새내기 러너');
      expect(levelTitle(12), '성장하는 러너');
      expect(levelTitle(99), '마스터 러너');
    });
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('보상 확인 중 실패하면 다시 확인해 레벨 상승을 표시합니다', (tester) async {
    final service = FakeProgressService(
      rewards: {'run-1': RunReward.fromJson(rewardJson())},
    )..rewardFailure = const SocketException('오프라인');
    service.pendingReward = Completer<void>();
    await show(tester, RunRewardSection(service: service, runId: 'run-1'));
    await tester.pump();
    expect(find.text('보상 확인 중'), findsOneWidget);
    service.pendingReward!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('보상을 확인하지 못했습니다'), findsOneWidget);
    expect(find.text('레벨 업!'), findsNothing);

    service.rewardFailure = null;
    service.pendingReward = null;
    await tester.tap(find.text('보상 다시 확인'));
    await tester.pumpAndSettle();
    expect(service.rewardRequests, ['run-1', 'run-1']);
    expect(find.text('+70 XP'), findsOneWidget);
    expect(find.text('레벨 업!'), findsOneWidget);
    expect(find.text('Lv.1 → Lv.2 새내기 러너'), findsOneWidget);
    expect(find.text('30 / 150 XP'), findsOneWidget);
    expect(find.text('다음 레벨까지 120 XP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('응답이 지연되면 실패로 처리합니다', (tester) async {
    final service = FakeProgressService()..pendingReward = Completer<void>();
    await show(
      tester,
      RunRewardSection(
        service: service,
        runId: 'run-1',
        timeout: const Duration(seconds: 1),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('보상 다시 확인'), findsOneWidget);
    service.pendingReward!.complete();
  });

  testWidgets('지급 제외와 대상 아님, 서버 저장 대기를 구분합니다', (tester) async {
    final service = FakeProgressService(
      rewards: {
        'short': RunReward.fromJson(
          rewardJson(xp: 0, reason: 'too_short', after: 1),
        ),
        'old': null,
      },
    );
    await show(tester, RunRewardSection(service: service, runId: 'short'));
    await tester.pumpAndSettle();
    expect(find.text('+0 XP'), findsOneWidget);
    expect(find.textContaining('300m 미만'), findsOneWidget);
    expect(find.text('레벨 업!'), findsNothing);

    await show(tester, RunRewardSection(service: service, runId: 'old'));
    await tester.pumpAndSettle();
    expect(find.text('이 기록은 경험치 지급 대상이 아니에요.'), findsOneWidget);

    await show(
      tester,
      RunRewardSection(service: service, runId: 'local', pendingSync: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('서버에 저장되면 경험치가 지급돼요.'), findsOneWidget);
    expect(service.rewardRequests, ['short', 'old']);
  });

  testWidgets('다른 계정으로 바뀌면 이전 보상을 표시하지 않습니다', (tester) async {
    final service = FakeProgressService(
      rewards: {'run-1': RunReward.fromJson(rewardJson())},
    )..pendingReward = Completer<void>();
    await show(tester, RunRewardSection(service: service, runId: 'run-1'));
    service.isCurrentOwner = false;
    service.pendingReward!.complete();
    await tester.pumpAndSettle();
    expect(find.text('+70 XP'), findsNothing);
  });

  testWidgets('프로필 레벨 카드는 실패 후 다시 불러옵니다', (tester) async {
    final service = FakeProgressService()
      ..loadFailure = const SocketException('오프라인');
    await show(tester, ProfileLevelCard(service: service));
    await tester.pumpAndSettle();
    expect(find.text('레벨 정보를 불러오지 못했습니다.'), findsOneWidget);
    service.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(service.loads, 2);
    expect(find.text('새내기 러너 · 누적 130 XP'), findsOneWidget);
    expect(find.text('Lv.2'), findsOneWidget);
    expect(find.text('30 / 150 XP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
