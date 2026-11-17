import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/profile/weekly_goal.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';

class _Store implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('주간 목표를 정하면 이번 주 거리 진행 막대를 보여주고 기억합니다', (tester) async {
    final store = _Store();
    final goal = WeeklyGoal(store: store);
    Widget bar(int meters) => MaterialApp(
      home: Scaffold(
        body: WeeklyGoalBar(weeklyDistanceMeters: meters, goal: goal),
      ),
    );
    await tester.pumpWidget(bar(12400));
    await tester.tap(find.text('주간 목표 정하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20km'));
    await tester.pumpAndSettle();
    expect(find.text('이번 주 20km 중 12.4km'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('7.6km 남았어요.'), findsOneWidget);

    await tester.pumpWidget(bar(21000));
    expect(find.text('달성!'), findsOneWidget);

    final again = WeeklyGoal(store: store);
    await again.load();
    expect(again.kilometers, 20);

    // 목표를 지우면 다시 정하기 버튼이 나옵니다.
    await tester.tap(find.text('이번 주 20km 중 21.0km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목표 지우기'));
    await tester.pumpAndSettle();
    expect(find.text('주간 목표 정하기'), findsOneWidget);
  });
}
