import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/data/run_checkpoint_store.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/home/models/run_split_tracker.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_split.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const splits = [
    RunSplit(distanceMeters: 1000, duration: Duration(seconds: 300)),
    RunSplit(distanceMeters: 250, duration: Duration(seconds: 100)),
  ];
  RunSummary summary({List<RunSplit>? data = splits}) => RunSummary(
    clientRunId: 'run',
    startedAt: DateTime.utc(2026, 10, 26),
    endedAt: DateTime.utc(2026, 10, 26, 0, 10),
    distanceMeters: 1250,
    duration: const Duration(seconds: 400),
    splits: data,
  );

  test('여러 경계를 통과해도 거리 비율로 보간하며 마지막 구간을 보존합니다', () {
    final tracker = RunSplitTracker();
    tracker.advance(500, const Duration(seconds: 150));
    tracker.advance(2250, const Duration(seconds: 675));
    final result = tracker.snapshot(2250, const Duration(seconds: 700));
    expect(result.map((split) => split.distanceMeters), [1000, 1000, 250]);
    expect(result.map((split) => split.duration.inSeconds), [300, 300, 100]);
    expect(result.first.speedKmh, 12);
    expect(result.last.pace, const Duration(seconds: 400));
  });
  test('정확히 1km에서 멈춰도 활동 시간 합계가 누락되지 않습니다', () {
    final tracker = RunSplitTracker()
      ..advance(1000, const Duration(seconds: 300));
    expect(
      tracker
          .snapshot(1000, const Duration(seconds: 310))
          .single
          .duration
          .inSeconds,
      310,
    );
    expect(RunSplitTracker().snapshot(0, const Duration(seconds: 10)), isEmpty);
  });
  test('복구 전후 구간의 거리·시간을 중복하지 않습니다', () {
    final tracker = RunSplitTracker.restore(
      splits,
      1250,
      const Duration(seconds: 400),
    );
    tracker.advance(2000, const Duration(seconds: 700));
    expect(
      tracker
          .snapshot(2000, const Duration(seconds: 700))
          .map((split) => split.duration.inSeconds),
      [300, 400],
    );
    final restored = RunSession.restore(summary()).finish();
    expect(
      restored.splits!.map((split) => split.toJson()),
      splits.map((split) => split.toJson()),
    );
    expect(RunSession.restore(summary(data: null)).finish().splits, isNull);
  });
  test('전송 대기와 진행 중 복구 저장소에 구간을 보존하고 변경 재시도를 거절합니다', () async {
    final dir = await Directory.systemTemp.createTemp('runspot-splits-');
    addTearDown(() => dir.delete(recursive: true));
    SqliteRunOutbox outbox() => SqliteRunOutbox(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/outbox.sqlite',
    );
    final first = outbox();
    await first.put(summary());
    await first.close();
    final second = outbox();
    addTearDown(second.close);
    expect(
      (await second.list()).single.splits!.map((split) => split.toJson()),
      splits.map((split) => split.toJson()),
    );
    await expectLater(
      second.put(summary(data: null)),
      throwsA(isA<RunOutboxException>()),
    );
    final store = SqliteRunCheckpointStore(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/active.sqlite',
    );
    await store.save(RunCheckpoint(summary(), finished: false));
    await store.close();
    final reopened = SqliteRunCheckpointStore(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/active.sqlite',
    );
    addTearDown(reopened.close);
    expect((await reopened.load())!.summary.splits!.length, 2);
    final pending = RunRecord.pending(summary());
    expect(pending.splits!.length, 2);
  });
  test('구간 저장 이전의 기기 기록을 손실 없이 올립니다', () async {
    final dir = await Directory.systemTemp.createTemp('runspot-split-upgrade-');
    addTearDown(() => dir.delete(recursive: true));
    final file = '${dir.path}/outbox.sqlite';
    final db = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) => db.execute(
          '''CREATE TABLE pending_runs (
        namespace TEXT, owner_id TEXT, client_run_id TEXT, started_at TEXT,
        ended_at TEXT, distance_m REAL, duration_us INTEGER, route_json TEXT, temperature_json TEXT)''',
        ),
      ),
    );
    await db.insert('pending_runs', {
      'namespace': 'server',
      'owner_id': 'owner',
      'client_run_id': 'old',
      'started_at': summary().startedAt.toIso8601String(),
      'ended_at': summary().endedAt.toIso8601String(),
      'distance_m': 1250.0,
      'duration_us': 400000000,
      'route_json': '[]',
    });
    await db.close();
    final store = SqliteRunOutbox(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => file,
    );
    addTearDown(store.close);
    final old = (await store.list()).single;
    expect(old.clientRunId, 'old');
    expect(old.splits, isNull);
    await store.put(old);
  });
}
