import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/training/widgets/training_plan_cards.dart';

void main() {
  testWidgets('목표 카드에서 5km 훈련을 선택합니다', (tester) async {
    TrainingPlanKind? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingPlanChoices(onSelect: (kind) => selected = kind),
        ),
      ),
    );
    await tester.tap(find.text('5km 준비'));
    expect(selected, TrainingPlanKind.fiveK);
  });

  testWidgets('작은 화면과 큰 글자에서 다음 훈련 주차를 열고 기록을 연결합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TrainingPlanSchedule(
                kind: TrainingPlanKind.fiveK,
                start: DateTime(2026, 11, 22),
                completed: const {0, 1, 2},
                onSessionTap: tapped.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('완료 3 / 12회'), findsOneWidget);
    expect(find.text('3km 편안하게 · 3회 일정'), findsOneWidget);
    final connect = find.text('기록 연결').first;
    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    expect(tapped, [3]);
    expect(tester.takeException(), isNull);
  });
}
