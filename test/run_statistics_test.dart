import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/profile/models/run_statistics.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';
import 'package:runquest/features/social/models/weekly_ranking.dart';
import 'package:runquest/features/social/widgets/friend_ranking.dart';

import 'support/statistics_fakes.dart';

void main() {
  test('평균 페이스는 총 시간과 총 거리의 비율로 계산합니다', () {
    final stats = RunStatistics.fromJson(statisticsJson);
    expect(stats.averagePace, const Duration(minutes: 6, seconds: 15));
    expect(
      RunStatistics.fromJson({
        ...statisticsJson,
        'pace_distance_m': 0,
        'pace_duration_sec': 0,
      }).averagePace,
      isNull,
    );
    expect(
      () => RunStatistics.fromJson({...statisticsJson, 'completed_runs': -1}),
      throwsFormatException,
    );
    expect(
      () =>
          RunStatistics.fromJson({...statisticsJson, 'weekly_distance_m': 1.5}),
      throwsFormatException,
    );
  });

  test('공동 순위와 본인 표시는 서버 결과를 따릅니다', () {
    final ranking = WeeklyRanking.fromJson({
      ...rankingJson,
      'entries': [
        {'rank': 1, 'nickname': '친구', 'distance_m': 5000, 'is_me': false},
        {'rank': 1, 'nickname': '러너', 'distance_m': 5000, 'is_me': true},
      ],
    });
    expect(ranking.entries.map((e) => e.rank), [1, 1]);
    expect(ranking.entries.last.name, '러너 (나)');
    expect(() => ranking.entries.clear(), throwsUnsupportedError);
    expect(
      () => WeeklyRanking.fromJson({...rankingJson, 'can_interact': false}),
      throwsFormatException,
    );
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('실제 통계 표시와 실패 재시도, 기록 없는 상태를 처리합니다', (tester) async {
    final service = FakeStatisticsService()..failed = true;
    await show(tester, QuickStats(service: service));
    expect(find.text('개인 통계를 불러오지 못했습니다.'), findsOneWidget);
    service.failed = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('12.0km'), findsOneWidget);
    expect(find.text('6:15'), findsOneWidget);
    expect(find.text('23회'), findsOneWidget);
    service.result = RunStatistics.fromJson({
      ...statisticsJson,
      'weekly_distance_m': 0,
      'completed_runs': 0,
      'pace_distance_m': 0,
      'pace_duration_sec': 0,
    });
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('--:--'), findsOneWidget);
    expect(find.text('0회'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('랭킹 갱신 실패 시 이전 친구 정보를 지우고 재시도합니다', (tester) async {
    final service = FakeRankingService();
    await show(tester, FriendRanking(service: service));
    expect(find.text('친구러너'), findsOneWidget);
    expect(find.text('내닉네임 (나)'), findsOneWidget);
    service.failed = true;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('친구러너'), findsNothing);
    expect(find.text('친구 랭킹을 불러오지 못했습니다.'), findsOneWidget);
    service.failed = false;
    service.result = WeeklyRanking.fromJson({
      ...rankingJson,
      'can_interact': false,
      'entries': [],
    });
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('이메일 인증과 닉네임 등록 후 랭킹을 확인할 수 있습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('계정 교체 전 진행 중이던 통계 응답은 표시하지 않습니다', (tester) async {
    final pending = Completer<RunStatistics>();
    final first = FakeStatisticsService()..onLoad = () => pending.future;
    Widget page(FakeStatisticsService service) => MaterialApp(
      home: Scaffold(body: QuickStats(service: service)),
    );
    await tester.pumpWidget(page(first));
    final second = FakeStatisticsService()
      ..result = RunStatistics.fromJson({
        ...statisticsJson,
        'completed_runs': 1,
      });
    await tester.pumpWidget(page(second));
    await tester.pumpAndSettle();
    pending.complete(first.result);
    await tester.pumpAndSettle();
    expect(find.text('1회'), findsOneWidget);
    expect(find.text('23회'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('백그라운드에서는 조회를 멈추고 복귀 시 다시 조회합니다', (tester) async {
    final service = FakeStatisticsService();
    await show(tester, QuickStats(service: service));
    expect(service.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(service.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(service.calls, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('친구 관계 갱신 시 이전 랭킹 응답을 폐기합니다', (tester) async {
    final pending = Completer<WeeklyRanking>();
    final service = FakeRankingService()..onLoad = () => pending.future;
    Widget page(int revision) => MaterialApp(
      home: Scaffold(
        body: FriendRanking(service: service, revision: revision),
      ),
    );
    await tester.pumpWidget(page(0));
    service.onLoad = null;
    service.result = WeeklyRanking.fromJson({...rankingJson, 'entries': []});
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    pending.complete(WeeklyRanking.fromJson(rankingJson));
    await tester.pumpAndSettle();
    expect(find.text('친구러너'), findsNothing);
    expect(find.text('표시할 주간 순위가 없습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
