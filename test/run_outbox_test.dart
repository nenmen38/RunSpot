import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/run_history_fakes.dart';

RunSummary summary({String id = 'run', double distance = 1234.5678}) =>
    RunSummary(
      clientRunId: id,
      startedAt: DateTime.parse('2026-10-09T09:00:00.123456+09:00'),
      endedAt: DateTime.utc(2026, 10, 9, 1, 0, 0, 456, 789),
      distanceMeters: distance,
      duration: const Duration(minutes: 25, microseconds: 123456),
    );

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  final stores = <SqliteRunOutbox>[];

  SqliteRunOutbox open({String owner = 'owner', String namespace = 'project'}) {
    final store = SqliteRunOutbox(
      ownerId: owner,
      namespace: namespace,
      factory: databaseFactoryFfi,
      databasePath: () async => databasePath,
    );
    stores.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('runspot-outbox-test-');
    databasePath = path.join(directory.path, 'records.sqlite');
  });

  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });

  test('디스크를 닫고 다시 열어도 식별자와 측정 정밀도가 유지됩니다', () async {
    final original = summary();
    final store = open();
    await store.put(original);
    await store.close();
    final restored = (await open().list()).single;
    expect(restored.clientRunId, original.clientRunId);
    expect(restored.startedAt, original.startedAt);
    expect(restored.endedAt, original.endedAt);
    expect(restored.startedAt.isUtc, isTrue);
    expect(restored.distanceMeters, original.distanceMeters);
    expect(restored.duration, original.duration);
  });

  test('같은 기록은 한 번 보관하며 다른 측정값으로 덮어쓰지 않습니다', () async {
    final store = open();
    await store.put(summary());
    await store.put(summary());
    expect(await store.list(), hasLength(1));
    await expectLater(
      store.put(summary(distance: 999)),
      throwsA(isA<RunOutboxException>()),
    );
    expect((await store.list()).single.distanceMeters, 1234.5678);
    await store.remove('run');
    expect(await store.list(), isEmpty);
  });

  test('같은 파일에서도 계정과 서버가 다르면 조회와 삭제가 격리됩니다', () async {
    final owner = open();
    final other = open(owner: "other' OR 1=1 --");
    final project = open(namespace: 'other-project');
    await owner.put(summary());
    expect(await other.list(), isEmpty);
    expect(await project.list(), isEmpty);
    await other.remove('run');
    await project.remove('run');
    expect(await owner.list(), hasLength(1));
    await other.put(summary(distance: 50));
    await project.put(summary(distance: 60));
    expect((await owner.list()).single.distanceMeters, 1234.5678);
    expect((await other.list()).single.distanceMeters, 50);
    expect((await project.list()).single.distanceMeters, 60);
  });

  test('저장소를 열지 못하면 저장 완료로 처리하지 않습니다', () async {
    databasePath = directory.path;
    await expectLater(
      open().put(summary()),
      throwsA(isA<RunOutboxException>()),
    );
  });

  test('오프라인 종료 후 저장소 재개방으로 복구하고 서버 성공 후에만 삭제합니다', () async {
    final service = FakeRunRecordService()
      ..saveFailure = const SocketException('오프라인');
    final first = RunHistoryController(service, outbox: open());
    final result = await first.save(summary());
    expect(result.pendingSync, isTrue);
    first.dispose();
    await Future<void>.delayed(Duration.zero);
    service.saveFailure = null;
    final reopened = open();
    final second = RunHistoryController(service, outbox: reopened);
    await second.setActive(true);
    expect(service.records, hasLength(1));
    expect(await reopened.list(), isEmpty);
    expect(second.visibleRecords.single.pendingSync, isFalse);
    expect(
      service.attempts.first.clientRunId,
      service.attempts.last.clientRunId,
    );
    expect(service.attempts.first.duration, service.attempts.last.duration);
    expect(
      service.attempts.first.distanceMeters,
      service.attempts.last.distanceMeters,
    );
    second.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
