import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/profile/models/run_growth.dart';
import 'package:runquest/features/profile/models/run_statistics.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';

import 'support/statistics_fakes.dart';

import 'package:runquest/features/profile/widgets/run_growth_panel.dart';

Map<String, dynamic> growthJson({bool empty = false}) => {
  'monthly_distances': [
    for (var i = 0; i < 12; i++)
      {
        'month': '2026-${(i + 1).toString().padLeft(2, '0')}',
        'distance_m': empty ? 0 : (i + 1) * 1000,
        'completed_runs': empty ? 0 : i + 1,
      },
  ],
  'longest_run': empty
      ? null
      : {'distance_m': 20000, 'ended_at': '2026-11-01T15:00:00Z'},
  'best_5k': empty
      ? null
      : {'duration_us': 1500000001, 'ended_at': '2026-11-01T15:00:00Z'},
  'best_10k': null,
};

void main() {
  test('12개월 순서와 숫자를 검증하고 최고 기록의 한국 날짜와 초 올림을 유지합니다', () {
    final growth = RunGrowth.fromJson(growthJson());
    expect(growth.months.length, 12);
    expect(growth.longest!.koreanDate, '2026.11.02');
    expect(growth.best5k!.duration, const Duration(minutes: 25, seconds: 1));
    expect(growth.best10k, isNull);
    expect(() => growth.months.clear(), throwsUnsupportedError);
    for (final field in ['distance_m', 'completed_runs', 'month']) {
      final json = growthJson();
      (json['monthly_distances'] as List)[3][field] = field == 'month'
          ? '2026-13'
          : -1;
      expect(() => RunGrowth.fromJson(json), throwsFormatException);
    }
    final skipped = growthJson();
    (skipped['monthly_distances'] as List)[3]['month'] = '2026-05';
    expect(() => RunGrowth.fromJson(skipped), throwsFormatException);
    expect(
      () => RunGrowth.fromJson({...growthJson(), 'monthly_distances': []}),
      throwsFormatException,
    );
    expect(
      () => RunGrowth.fromJson({
        ...growthJson(),
        'best_5k': {'duration_us': 0, 'ended_at': '2026-11-01T15:00:00Z'},
      }),
      throwsFormatException,
    );
  });

  testWidgets('프로필 통계 조회 응답에 성장 추이가 함께 표시됩니다', (tester) async {
    final service = FakeStatisticsService()
      ..result = RunStatistics.fromJson({
        ...statisticsJson,
        'growth': growthJson(),
      });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: QuickStats(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 기록과 성장 추이'), findsOneWidget);
    expect(find.text('20.00km'), findsOneWidget);
    expect(find.text('25:01'), findsOneWidget);
    service.failed = true;
    await tester.ensureVisible(find.text('새로고침'));
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('20.00km'), findsNothing);
    expect(find.text('개인 통계를 불러오지 못했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('좁은 화면과 큰 글자에서 월 선택·최고 기록·빈 상태를 표시합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> show(bool empty) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: RunGrowthPanel(
                  growth: RunGrowth.fromJson(growthJson(empty: empty)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(false);
    expect(find.text('2026년 12월 · 12회'), findsOneWidget);
    expect(find.text('12.00km'), findsOneWidget);
    expect(find.text('25:01'), findsOneWidget);
    expect(find.text('기록 없음'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 1월 · 1회'), findsOneWidget);
    expect(find.text('1.00km'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await show(true);
    expect(find.text('0.00km'), findsOneWidget);
    expect(find.text('기록 없음'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
