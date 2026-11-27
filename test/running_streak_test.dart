import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:runquest/features/profile/running_streak.dart';

void main() {
  tearDown(RunningStreakStore.instance.unbind);

  test('연속 기록 문구는 목표가 있으면 남은 거리를, 없으면 한 번 달리기를 알려 줍니다', () {
    final goal = RunningStreak.fromJson({
      'weeks': 3,
      'goal_based': true,
      'this_week_done': false,
      'this_week_m': 6200,
      'goal_m': 10000,
    });
    expect(goal.label, '🔥 3주 연속 목표 달성');
    expect(goal.hint, '이번 주 3.8km 더 달리면 4주 연속이에요');
    final plain = RunningStreak.fromJson({
      'weeks': 2,
      'goal_based': false,
      'this_week_done': true,
    });
    expect(plain.label, '🔥 2주 연속 달리는 중');
    expect(plain.hint, '이번 주도 달렸어요!');
  });

  testWidgets('연속 기록이 있으면 프로필 카드에 보여 주고 없으면 숨깁니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RunningStreakCard())),
    );
    expect(find.byKey(const ValueKey('running-streak')), findsNothing);

    var weeks = 0;
    RunningStreakStore.instance.bindLoader(
      () async =>
          RunningStreak(weeks: weeks, goalBased: true, thisWeekDone: true),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('running-streak')), findsNothing);

    weeks = 4;
    await RunningStreakStore.instance.refresh();
    await tester.pumpAndSettle();
    expect(find.text('🔥 4주 연속 목표 달성'), findsOneWidget);
    expect(find.text('이번 주 목표도 달성했어요!'), findsOneWidget);
  });

  test('러닝 응원 알림을 누르면 열 수 있는 알림으로 받습니다', () {
    const owner = '00000000-0000-0000-0000-0000000000aa';
    final destination = PushDestination.parse({
      'kind': 'comeback',
      'target_id': owner,
      'recipient_id': owner,
    }, owner);
    expect(destination?.kind, 'comeback');
  });
}
