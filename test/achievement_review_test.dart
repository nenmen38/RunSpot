import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/admin/admin_screen.dart';
import 'package:runquest/features/admin/data/review_service.dart';
import 'package:runquest/features/profile/models/achievement.dart';
import 'package:runquest/features/profile/widgets/achievement_row.dart';
import 'package:runquest/features/progress/models/run_progress.dart';

class _Reviews implements ReviewService {
  @override
  bool isCurrentOwner = true;
  bool denied = false;
  final items = [
    IntegrityReview.fromJson({
      'id': 'case',
      'nickname': '검토러너',
      'distance_m': 6000,
      'duration_sec': 600,
      'risk': 90,
    }),
  ];
  final decisions = <bool>[];
  @override
  Future<List<IntegrityReview>> load() async {
    if (denied) throw StateError('권한 없음');
    return List.of(items);
  }

  @override
  Future<void> resolve(
    String id, {
    required bool approved,
    required String note,
  }) async {
    expect(note, '속도 검토 완료');
    decisions.add(approved);
    items.clear();
  }
}

void main() {
  testWidgets('관리자는 사유를 입력해야 조치하고 성공 후 서버 목록을 갱신합니다', (tester) async {
    final service = _Reviews();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('검토러너'), findsOneWidget);
    await tester.tap(find.text('반려'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확정'));
    await tester.pumpAndSettle();
    expect(service.decisions, isEmpty);
    await tester.enterText(find.byType(TextField), '속도 검토 완료');
    await tester.tap(find.text('확정'));
    await tester.pumpAndSettle();
    expect(service.decisions, [false]);
    expect(find.text('검토할 기록이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('권한 없는 관리자 조회는 예시 기록 대신 접근 오류를 표시합니다', (tester) async {
    final service = _Reviews()..denied = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('검토러너'), findsNothing);
    expect(find.textContaining('관리자 권한과 다중 인증'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('달성 업적은 진행률과 달성일을 표시합니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementRow(
            achievement: Achievement(
              '첫 러닝 완료',
              '1 / 1회',
              Icons.military_tech,
              1,
              achievedAt: DateTime(2026, 10, 21),
            ),
          ),
        ),
      ),
    );
    expect(find.text('달성 2026.10.21'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });

  test('반려 보상은 지급 이력과 별개로 현재 경험치에서 제외된 사유를 해석합니다', () {
    final reward = RunReward.fromJson({
      'status': 'ready',
      'xp': 0,
      'reason': 'rejected',
      'level_before': 1,
      'level_after': 1,
      'progress': {
        'total_xp': 0,
        'level': 1,
        'level_xp': 0,
        'next_level_xp': 100,
      },
    })!;
    expect(reward.reason, RewardReason.rejected);
    expect(reward.reasonMessage, contains('반려'));
  });
}
