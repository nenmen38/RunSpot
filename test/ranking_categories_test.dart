import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/data/ranking_service.dart';
import 'package:runquest/features/social/models/weekly_ranking.dart';
import 'package:runquest/features/social/widgets/friend_ranking.dart';

WeeklyRanking result(RankingCategory category, String name, int score) =>
    WeeklyRanking.fromJson({
      'can_interact': true,
      'week_started_at': '2026-11-02T00:00:00+09:00',
      'entries': [
        {'rank': 1, 'nickname': name, 'score': score, 'is_me': false},
      ],
    }, category: category);

class _Service implements FilteredRankingService {
  Completer<WeeklyRanking>? pending;
  final requests = <(RankingCategory, RankingAudience)>[];
  @override
  bool get isCurrentOwner => true;
  @override
  Future<WeeklyRanking> load() =>
      loadRanking(RankingCategory.distance, RankingAudience.friends);
  @override
  Future<WeeklyRanking> loadRanking(
    RankingCategory category,
    RankingAudience audience,
  ) async {
    requests.add((category, audience));
    if (category == RankingCategory.distance && pending != null) {
      return pending!.future;
    }
    return result(
      category,
      '새 순위',
      category == RankingCategory.longest ? 1200 : 1500000000,
    );
  }
}

void main() {
  test('최장 거리와 5km 기록을 서로 다른 단위로 표시합니다', () {
    expect(
      result(RankingCategory.longest, '러너', 1200).entries.single.value,
      '1.2km',
    );
    expect(
      result(RankingCategory.fiveK, '러너', 1500000000).entries.single.value,
      '25:00',
    );
  });
  testWidgets('기준·대상 전환 후 늦게 온 이전 순위를 표시하지 않습니다', (tester) async {
    final service = _Service()..pending = Completer<WeeklyRanking>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FriendRanking(service: service)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('최장 거리'));
    await tester.pumpAndSettle();
    expect(find.text('1.2km'), findsOneWidget);
    service.pending!.complete(result(RankingCategory.distance, '이전 순위', 99999));
    await tester.pumpAndSettle();
    expect(find.text('이전 순위'), findsNothing);
    await tester.tap(find.byTooltip('랭킹 대상 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();
    expect(service.requests.last, (
      RankingCategory.longest,
      RankingAudience.all,
    ));
    await tester.tap(find.text('5km 기록'));
    await tester.pumpAndSettle();
    expect(service.requests.last, (RankingCategory.fiveK, RankingAudience.all));
    expect(find.text('25:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
