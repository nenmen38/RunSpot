import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/home_widget_sync.dart';
import 'package:runquest/features/profile/weekly_goal.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/run_history_fakes.dart';

RunRecord _run(String id, DateTime ended, int meters) => RunRecord(
  id: id,
  clientRunId: id,
  startedAt: ended.subtract(const Duration(minutes: 30)),
  endedAt: ended,
  distanceMeters: meters,
  durationSeconds: 1800,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('이번 주(월요일 0시부터) 기록만 더하고 목표 진행률을 셉니다', () {
    // 2026-11-26은 목요일이므로 이번 주는 11-23(월) 0시부터입니다.
    final now = DateTime(2026, 11, 26, 9);
    final data = HomeWidgetData.from(
      [
        _run('a', DateTime(2026, 11, 23, 0, 30), 5000),
        _run('b', DateTime(2026, 11, 25, 20), 3400),
        _run('old', DateTime(2026, 11, 22, 23, 50), 10000),
      ],
      goalKm: 20,
      now: now,
    );
    expect(data.weekMeters, 8400);
    expect(data.runs, 2);
    expect(data.weekKm, '8.4');
    expect(data.percent, 42);
    expect(
      HomeWidgetData.from(
        [_run('a', now, 30000)],
        goalKm: 20,
        now: now,
      ).percent,
      100,
    );
    expect(HomeWidgetData.from(const [], now: now).percent, 0);
  });

  test('기록이나 목표가 바뀌면 위젯에 보내고 같은 내용은 다시 보내지 않습니다', () async {
    const channel = MethodChannel('test/home_widget');
    final calls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments as Map<Object?, Object?>);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    )..records = [_run('a', DateTime.now(), 5230)];
    final goal = WeeklyGoal.instance..kilometers = 10;
    addTearDown(() => goal.kilometers = null);
    final sync = HomeWidgetSync(
      history: history,
      goal: goal,
      channel: channel,
      enabled: true,
    );
    await sync.push();
    await sync.push();
    expect(calls, hasLength(1));
    expect(calls.single, {
      'weekKm': '5.2',
      'goalKm': 10,
      'percent': 52,
      'runs': 1,
    });
    goal.kilometers = 5;
    await sync.push();
    expect(calls.last['percent'], 100);
    sync.dispose();
  });

  test('위젯이 없는 환경에서는 조용히 넘어갑니다', () async {
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final sync = HomeWidgetSync(
      history: history,
      channel: const MethodChannel('test/no_widget'),
      enabled: true,
    );
    await expectLater(sync.push(), completes);
    sync.dispose();
  });
}
