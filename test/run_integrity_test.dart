import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/widgets/run_record_details.dart';
import 'package:runquest/features/run_history/widgets/run_splits_panel.dart';
import 'package:runquest/features/run_history/models/run_integrity.dart';
import 'package:runquest/features/run_history/models/run_split.dart';

void main() {
  testWidgets('서버 보류 상태를 표시하고 승인 후 불필요한 경고를 숨깁니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    RunRecord record(bool held) => RunRecord.fromJson({
      'id': 'record',
      'client_run_id': 'run',
      'started_at': '2026-10-26T00:00:00Z',
      'ended_at': '2026-10-26T01:00:00Z',
      'distance_m': 2000,
      'duration_sec': 600,
      'review_pending': held,
      'integrity_status': held ? 'pending' : 'verified',
      'split_data': [
        {'distance_m': 1000, 'duration_us': 500000000},
        {'distance_m': 1000, 'duration_us': 100000000},
      ],
    });
    Future<void> show(bool held) async {
      final item = record(held);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  RunRecordDetails(record: item),
                  RunSplitsPanel(
                    splits: item.splits,
                    reviewResolved: item.integrityStatus != 'pending',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await show(true);
    expect(find.text('검토 중 · 랭킹·경험치 보류'), findsOneWidget);
    expect(find.text('속도 확인 필요'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await show(false);
    expect(find.text('검토 중 · 랭킹·경험치 보류'), findsNothing);
    expect(find.text('속도 확인 필요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('전체 평균이 정상이어도 빠른 구간을 찾습니다', () {
    const slow = RunSplit(
      distanceMeters: 1000,
      duration: Duration(seconds: 500),
    );
    const vehicle = RunSplit(
      distanceMeters: 1000,
      duration: Duration(seconds: 100),
    );
    expect(2000 / 600, lessThan(6.5));
    expect(RunIntegrity.suspicious(slow), isFalse);
    expect(RunIntegrity.suspicious(vehicle), isTrue);
  });
  test('기존 속도 경계와 짧은 마지막 구간의 흔들림을 구분합니다', () {
    expect(
      RunIntegrity.suspicious(
        const RunSplit(distanceMeters: 650, duration: Duration(seconds: 100)),
      ),
      isFalse,
    );
    expect(
      RunIntegrity.suspicious(
        const RunSplit(distanceMeters: 651, duration: Duration(seconds: 100)),
      ),
      isTrue,
    );
    expect(
      RunIntegrity.suspicious(
        const RunSplit(distanceMeters: 1, duration: Duration.zero),
      ),
      isFalse,
    );
    expect(
      RunIntegrity.suspicious(
        const RunSplit(distanceMeters: 300, duration: Duration.zero),
      ),
      isTrue,
    );
  });
}
