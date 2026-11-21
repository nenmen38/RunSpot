import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_history/models/run_calories.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_split.dart';
import 'package:runquest/features/run_history/widgets/run_record_details.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/features/settings/body_weight.dart';

class _Store implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('페이스로 칼로리를 추정하고 빠를수록 같은 시간에 더 많이 씁니다', () {
    // 5km를 25분(분속 200m)에 달리면 65kg 기준 약 353kcal입니다.
    expect(
      estimateRunCalories(
        distanceMeters: 5000,
        durationSeconds: 1500,
        weightKg: 65,
      ),
      353,
    );
    // 체중이 무거우면 더 많이 씁니다.
    expect(
      estimateRunCalories(
        distanceMeters: 5000,
        durationSeconds: 1500,
        weightKg: 80,
      ),
      435,
    );
    // 걷는 속도(3km 36분)는 걷기 식으로 계산합니다.
    expect(
      estimateRunCalories(
        distanceMeters: 3000,
        durationSeconds: 2160,
        weightKg: 65,
      ),
      138,
    );
    // 구간 기록이 있으면 구간마다 계산해 더합니다.
    final mixed = estimateRunCalories(
      distanceMeters: 2000,
      durationSeconds: 900,
      weightKg: 65,
      splits: const [
        RunSplit(distanceMeters: 1000, duration: Duration(minutes: 4)),
        RunSplit(distanceMeters: 1000, duration: Duration(minutes: 11)),
      ],
    )!;
    // 4분 달린 1km(약 70kcal) + 11분 걸은 1km(약 45kcal)
    expect(mixed, 115);
    expect(
      estimateRunCalories(
        distanceMeters: 0,
        durationSeconds: 100,
        weightKg: 65,
      ),
      isNull,
    );
  });

  testWidgets('체중을 설정한 경우에만 러닝 칼로리를 계산합니다', (tester) async {
    final weight = BodyWeight(store: _Store());
    final record = RunRecord(
      id: 'r',
      clientRunId: 'c',
      startedAt: DateTime.utc(2026, 11, 19, 6),
      endedAt: DateTime.utc(2026, 11, 19, 6, 25),
      distanceMeters: 5000,
      durationSeconds: 1500,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunRecordDetails(record: record, weight: weight),
        ),
      ),
    );
    expect(find.text('칼로리'), findsOneWidget);
    expect(weight.kg, isNull);
    expect(find.text('--'), findsOneWidget);
    expect(find.textContaining('추정값'), findsNothing);

    await weight.set(80);
    await tester.pump();
    expect(find.text('435 kcal'), findsOneWidget);
    expect(find.textContaining('추정값'), findsNothing);

    // 범위를 벗어난 체중은 저장하지 않습니다.
    await weight.set(500);
    expect(weight.kg, 80);
  });
}
