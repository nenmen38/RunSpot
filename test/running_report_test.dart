import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/report/running_report.dart';
import 'package:runquest/features/report/running_report_screen.dart';
import 'package:runquest/features/run_share/data/run_share_service.dart';

Map<String, dynamic> reportJson({String period = 'year', int runs = 3}) => {
  'period': period,
  'starts': period == 'year' ? '2026-01-01' : '2026-11-01',
  'runs': runs,
  'distance_m': runs == 0 ? 0 : 128400,
  'duration_sec': 45600,
  'active_days': 41,
  'previous_distance_m': 100000,
  'longest': runs == 0
      ? null
      : {'distance_m': 21100, 'ended_at': '2026-10-12T00:30:00Z'},
  'fastest_pace_sec': 312,
  'buckets': period == 'year'
      ? [0, 5000, 15000, 8000, 9000, 12000, 7000, 0, 20000, 30000, 22400, 0]
      : [5000, 8000, 0, 3000, 0],
  'favorite_weekday': 6,
  'favorite_time': 'morning',
  'companions': 2,
};

class FakeReportService implements RunningReportService {
  final requests = <(ReportPeriod, DateTime)>[];
  int runs = 3;

  @override
  Future<RunningReport> load(ReportPeriod period, DateTime starts) async {
    requests.add((period, starts));
    return RunningReport.fromJson(
      reportJson(period: period.name, runs: runs)
        ..['starts'] =
            '${starts.year}-${starts.month.toString().padLeft(2, '0')}-01',
    );
  }
}

class FakeShare implements RunShareService {
  Uint8List? shared;
  @override
  Future<RunShareResult> share(
    Uint8List png,
    Rect origin, {
    required bool Function() isCurrentOwner,
  }) async {
    shared = png;
    return RunShareResult.handedOff;
  }
}

void main() {
  test('리포트를 읽고 가장 많이 달린 칸을 찾습니다', () {
    final report = RunningReport.fromJson(reportJson());
    expect(report.period, ReportPeriod.year);
    expect(report.kilometers, 128.4);
    expect(report.bestBucket, 10);
    expect(report.bucketLabel(10), '10월');
    expect(report.longestAt, isNotNull);
    expect(defaultReport(DateTime(2026, 12, 3)).period, ReportPeriod.year);
    expect(defaultReport(DateTime(2027, 1, 3)).starts, DateTime(2026));
    expect(defaultReport(DateTime(2026, 11, 3)).starts, DateTime(2026, 11));
  });

  testWidgets('12월에는 연말 결산을 먼저 보여 주고 카드를 넘겨 공유합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeReportService();
    final share = FakeShare();
    await tester.pumpWidget(
      MaterialApp(
        home: RunningReportScreen(
          service: service,
          shareService: share,
          now: DateTime(2026, 12, 5),
          outfit: const CharacterOutfit(hat: Colors.blue),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.requests.single, (ReportPeriod.year, DateTime(2026)));
    expect(find.text('2026년 나의 러닝'), findsOneWidget);
    // 다음 해로는 못 갑니다.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );

    await tester.drag(
      find.byKey(const ValueKey('report-pages')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('128.4 km'), findsOneWidget);
    expect(find.textContaining('마라톤 풀코스 3.0번'), findsOneWidget);
    expect(find.textContaining('작년보다 +28.4km'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.drag(
        find.byKey(const ValueKey('report-pages')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('리포트 공유하기'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('리포트 공유하기'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(share.shared, isNotNull);
  });

  testWidgets('월간으로 바꾸면 이번 달 리포트를, 기록이 없으면 안내를 보여 줍니다', (tester) async {
    final service = FakeReportService();
    await tester.pumpWidget(
      MaterialApp(
        home: RunningReportScreen(
          service: service,
          now: DateTime(2026, 11, 20),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.requests.single, (ReportPeriod.month, DateTime(2026, 11)));
    expect(find.text('11월의 나의 러닝'), findsOneWidget);

    service.runs = 0;
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(service.requests.last, (ReportPeriod.month, DateTime(2026, 10)));
    expect(find.textContaining('아직 러닝 기록이 없어요'), findsOneWidget);

    service.runs = 3;
    await tester.tap(find.text('연간'));
    await tester.pumpAndSettle();
    expect(service.requests.last, (ReportPeriod.year, DateTime(2026)));
    expect(find.text('2026년 나의 러닝'), findsOneWidget);
  });
}
