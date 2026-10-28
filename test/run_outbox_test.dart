import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as path;
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_history/models/run_temperature.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/run_history_fakes.dart';

RunSummary summary({
  String id = 'run',
  double distance = 1234.5678,
  RunRoute? route,
  RunTemperature? temperature,
}) => RunSummary(
  clientRunId: id,
  startedAt: DateTime.parse('2026-10-09T09:00:00.123456+09:00'),
  endedAt: DateTime.utc(2026, 10, 9, 1, 0, 0, 456, 789),
  distanceMeters: distance,
  duration: const Duration(minutes: 25, microseconds: 123456),
  temperature: temperature,
  route:
      route ??
      RunRoute([
        [const LatLng(37.5665123456, 126.978), const LatLng(37.567, 126.9785)],
        [const LatLng(37.568, 126.979)],
      ]),
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
    final original = summary(
      temperature: RunTemperature(
        celsius: 23.5,
        observedAt: DateTime.utc(2026, 10, 9, 1),
      ),
    );
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
    expect(restored.route.toJson(), original.route.toJson());
    expect(restored.temperature!.toJson(), original.temperature!.toJson());
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
    await expectLater(
      store.put(summary(route: const RunRoute.empty())),
      throwsA(isA<RunOutboxException>()),
    );
    await expectLater(
      store.put(
        summary(
          temperature: RunTemperature(
            celsius: 20,
            observedAt: summary().endedAt,
          ),
        ),
      ),
      throwsA(isA<RunOutboxException>()),
    );
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
    final original = summary(
      temperature: RunTemperature(celsius: 0, observedAt: summary().endedAt),
    );
    final result = await first.save(original);
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
      second.visibleRecords.single.temperature!.toJson(),
      original.temperature!.toJson(),
    );
    expect(
      service.attempts.first.clientRunId,
      service.attempts.last.clientRunId,
    );
    expect(service.attempts.first.duration, service.attempts.last.duration);
    expect(
      service.attempts.first.route.toJson(),
      service.attempts.last.route.toJson(),
    );
    expect(service.routes.values.single.toJson(), summary().route.toJson());
    expect(
      service.attempts.first.distanceMeters,
      service.attempts.last.distanceMeters,
    );
    second.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('이전 버전 전송 대기 기록은 경로 없이 보존하여 업그레이드합니다', () async {
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE pending_runs (namespace TEXT, owner_id TEXT, client_run_id TEXT, started_at TEXT, ended_at TEXT, distance_m REAL, duration_us INTEGER, PRIMARY KEY(namespace,owner_id,client_run_id))',
          );
        },
      ),
    );
    final original = summary();
    await old.insert('pending_runs', {
      'namespace': 'project',
      'owner_id': 'owner',
      'client_run_id': original.clientRunId,
      'started_at': original.startedAt.toUtc().toIso8601String(),
      'ended_at': original.endedAt.toUtc().toIso8601String(),
      'distance_m': original.distanceMeters,
      'duration_us': original.duration.inMicroseconds,
    });
    await old.close();
    final restored = (await open().list()).single;
    expect(restored.clientRunId, original.clientRunId);
    expect(restored.duration, original.duration);
    expect(restored.route.isEmpty, isTrue);
    expect(restored.temperature, isNull);
  });

  test('경로가 있는 2버전 저장소도 기온 없이 그대로 업그레이드합니다', () async {
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            "CREATE TABLE pending_runs (namespace TEXT, owner_id TEXT, client_run_id TEXT, started_at TEXT, ended_at TEXT, distance_m REAL, duration_us INTEGER, route_json TEXT NOT NULL DEFAULT '[]', PRIMARY KEY(namespace,owner_id,client_run_id))",
          );
        },
      ),
    );
    final original = summary();
    await old.insert('pending_runs', {
      'namespace': 'project',
      'owner_id': 'owner',
      'client_run_id': original.clientRunId,
      'started_at': original.startedAt.toIso8601String(),
      'ended_at': original.endedAt.toIso8601String(),
      'distance_m': original.distanceMeters,
      'duration_us': original.duration.inMicroseconds,
      'route_json': '[[[37.0,127.0]]]',
    });
    await old.close();
    final restored = (await open().list()).single;
    expect(restored.temperature, isNull);
    expect(restored.route.toJson(), [
      [
        [37.0, 127.0],
      ],
    ]);
    await open().put(restored);
  });

  test('서버 크기 제한으로 거절된 기록도 기기 원본과 다른 대기 기록을 보존합니다', () async {
    final large = summary(
      route: RunRoute(
        List.generate(50001, (_) => [const LatLng(37.56, 126.97)]),
      ),
    );
    final store = open();
    final service = FakeRunRecordService()
      ..saveFailure = const PostgrestException(
        message: '경로 데이터가 너무 큽니다.',
        code: '22023',
      );
    final controller = RunHistoryController(service, outbox: store);
    expect((await controller.save(large)).pendingSync, isTrue);
    expect((await controller.save(summary(id: 'second'))).pendingSync, isTrue);
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    final restored = await open().list();
    expect(restored, hasLength(2));
    expect(
      restored.firstWhere((row) => row.clientRunId == 'run').route.segments,
      hasLength(50001),
    );
    expect(
      restored.firstWhere((row) => row.clientRunId == 'second').route.toJson(),
      summary().route.toJson(),
    );
  });

  test('탈퇴 시 이 계정과 서버의 보관 기록만 지웁니다', () async {
    final mine = open();
    final other = open(owner: 'other');
    await mine.put(summary(id: 'a'));
    await mine.put(summary(id: 'b'));
    await other.put(summary(id: 'c'));
    await mine.clear();
    expect(await mine.list(), isEmpty);
    expect((await other.list()).single.clientRunId, 'c');
  });
}
