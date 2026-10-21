import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/home/data/run_checkpoint_store.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

RunSummary _summary() => RunSummary(
  clientRunId: 'c34e9422-5f84-44a2-a468-5574ee69d871',
  startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
  endedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  distanceMeters: 820,
  duration: const Duration(minutes: 4),
  route: RunRoute([
    [const LatLng(37.5, 127), const LatLng(37.501, 127)],
  ]),
);

void main() {
  sqfliteFfiInit();
  test('복구는 미측정 시간과 경로를 연결하지 않고 식별자를 유지합니다', () async {
    final saved = _summary();
    final session = RunSession.restore(saved);
    expect(session.isRunning, isFalse);
    expect(session.duration, saved.duration);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(session.duration, saved.duration);
    session.resume(testFix());
    expect(session.routeSegments, hasLength(2));
    session.pause();
    final finished = session.finish();
    expect(finished.clientRunId, saved.clientRunId);
    expect(finished.startedAt, saved.startedAt);
    expect(finished.distanceMeters, 820);
  });

  test('실제 SQLite 재개방과 계정·서버 격리 및 완료 스냅샷을 보존합니다', () async {
    final dir = await Directory.systemTemp.createTemp('runspot-active-');
    addTearDown(() => dir.delete(recursive: true));
    SqliteRunCheckpointStore store(String owner, String server) =>
        SqliteRunCheckpointStore(
          ownerId: owner,
          namespace: server,
          factory: databaseFactoryFfi,
          databasePath: () async => '${dir.path}/active.sqlite',
        );
    final first = store('owner', 'server-a');
    final summary = _summary();
    await first.save(RunCheckpoint(summary, finished: true));
    await first.close();
    final otherAccount = store('other', 'server-a');
    final otherServer = store('owner', 'server-b');
    expect(await otherAccount.load(), isNull);
    expect(await otherServer.load(), isNull);
    await otherAccount.clear();
    await otherAccount.close();
    await otherServer.close();
    final reopened = store('owner', 'server-a');
    final checkpoint = (await reopened.load())!;
    final finished = RunSession.restore(
      checkpoint.summary,
      finished: checkpoint.finished,
    ).finish();
    expect(finished.endedAt, summary.endedAt);
    expect(finished.clientRunId, summary.clientRunId);
    expect(finished.route.toJson(), summary.route.toJson());
    await reopened.clear();
    expect(await reopened.load(), isNull);
    await reopened.close();
  });

  test('지도 초기화 때 복구하며 종료 저장 뒤 복구 원본을 제거합니다', () async {
    final dir = await Directory.systemTemp.createTemp('runspot-controller-');
    addTearDown(() => dir.delete(recursive: true));
    final store = SqliteRunCheckpointStore(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/active.sqlite',
    );
    await store.save(RunCheckpoint(_summary(), finished: false));
    final location = FakeLocationService();
    final records = FakeRunRecordService();
    final history = RunHistoryController(records, outbox: FakeRunOutbox());
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
      checkpointStore: store,
    );
    await controller.start();
    expect(controller.recoveredRun, isTrue);
    expect(controller.runSession!.isRunning, isFalse);
    expect(controller.sharing, isFalse);
    final summary = await controller.finishRun();
    expect(summary!.distanceMeters, 820);
    expect(await store.load(), isNull);
    controller.dispose();
    history.dispose();
    await location.updates.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
}
