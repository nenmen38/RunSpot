import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/profile/data/personal_records_service.dart';
import 'package:runquest/features/profile/widgets/personal_records_card.dart';

class _Records implements PersonalRecordsService {
  _Records(this.records);
  final List<PersonalRecord> records;
  @override
  bool get isCurrentOwner => true;
  @override
  Future<List<PersonalRecord>> load() async => records;
}

void main() {
  final now = DateTime(2026, 11, 17, 9);
  final records = [
    PersonalRecord.fromJson({
      'distance_km': 1,
      'duration_us': 280000000,
      'run_id': 'fast',
      'started_at': now.subtract(const Duration(days: 1)).toIso8601String(),
    }),
    PersonalRecord.fromJson({
      'distance_km': 5,
      'duration_us': 1500000000,
      'run_id': 'long',
      'started_at': now.subtract(const Duration(days: 30)).toIso8601String(),
    }),
  ];

  testWidgets('프로필에 1·5·10km 최고 기록과 최근 신기록을 보여줍니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalRecordsCard(service: _Records(records), now: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 최고 기록'), findsOneWidget);
    expect(find.text('04:40'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('5’00”/km'), findsOneWidget);
    // 10km는 아직 기록이 없습니다.
    expect(find.text('기록 없음'), findsOneWidget);
    // 최근 7일 안의 1km 기록에만 '신기록'을 붙입니다.
    expect(find.text('신기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이번 러닝이 최고 기록이면 완료 창에 신기록을 알립니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NewRecordBanner(service: _Records(records), runId: 'fast'),
              NewRecordBanner(service: _Records(records), runId: 'other'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1km 신기록!'), findsOneWidget);
  });
}
