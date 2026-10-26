import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../home/models/run_session.dart';
import '../../home/models/run_motion_tracker.dart';
import '../models/run_route.dart';
import '../models/run_temperature.dart';
import '../models/run_split.dart';

class RunOutboxException implements Exception {
  const RunOutboxException(this.message);
  final String message;
}

abstract interface class RunOutbox {
  String get ownerId;
  Future<void> put(RunSummary summary);
  Future<List<RunSummary>> list();
  Future<void> remove(String clientRunId);
  Future<void> close();
}

class SqliteRunOutbox implements RunOutbox {
  SqliteRunOutbox({
    required this.ownerId,
    required this.namespace,
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  }) : _factory = factory ?? databaseFactory,
       _databasePath = databasePath ?? _defaultPath;

  @override
  final String ownerId;
  final String namespace;
  final DatabaseFactory _factory;
  final Future<String> Function() _databasePath;
  Future<Database>? _database;
  bool _closed = false;

  static Future<String> _defaultPath() async => path.join(
    (await getApplicationSupportDirectory()).path,
    'run_outbox.sqlite',
  );

  Future<Database> _open() async {
    if (_closed) throw const RunOutboxException('기기 저장소가 닫혔습니다.');
    try {
      return await (_database ??= _create());
    } catch (_) {
      _database = null;
      throw const RunOutboxException('기기 저장소를 열지 못했습니다. 저장을 다시 시도해 주세요.');
    }
  }

  Future<Database> _create() async => _factory.openDatabase(
    await _databasePath(),
    options: OpenDatabaseOptions(
      version: 5,
      singleInstance: false,
      onConfigure: (db) async {
        await db.execute('PRAGMA synchronous = FULL');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE pending_runs (
            namespace TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            client_run_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL,
            distance_m REAL NOT NULL CHECK(distance_m >= 0),
            duration_us INTEGER NOT NULL CHECK(duration_us >= 0),
            route_json TEXT NOT NULL DEFAULT '[]',
            temperature_json TEXT,
            splits_json TEXT,
            motion_json TEXT,
            PRIMARY KEY(namespace, owner_id, client_run_id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE pending_runs ADD COLUMN motion_json TEXT',
          );
        }
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE pending_runs ADD COLUMN route_json TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE pending_runs ADD COLUMN splits_json TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE pending_runs ADD COLUMN temperature_json TEXT',
          );
        }
      },
    ),
  );

  @override
  Future<void> put(RunSummary summary) async {
    if (!RunSplit.matches(
          summary.splits,
          summary.distanceMeters,
          summary.duration,
        ) ||
        !summary.distanceMeters.isFinite ||
        summary.distanceMeters < 0 ||
        summary.duration.isNegative ||
        !summary.endedAt.isAfter(summary.startedAt) ||
        (summary.temperature != null &&
            !summary.temperature!.isFreshAt(summary.endedAt))) {
      throw const RunOutboxException('러닝 기록의 측정값을 확인해 주세요.');
    }
    final row = <String, Object?>{
      'namespace': namespace,
      'owner_id': ownerId,
      'client_run_id': summary.clientRunId,
      'started_at': summary.startedAt.toUtc().toIso8601String(),
      'ended_at': summary.endedAt.toUtc().toIso8601String(),
      'distance_m': summary.distanceMeters,
      'duration_us': summary.duration.inMicroseconds,
      'route_json': jsonEncode(summary.route.toJson()),
      'motion_json': summary.motionSamples == null
          ? null
          : jsonEncode(summary.motionSamples),
      'splits_json': summary.splits == null
          ? null
          : jsonEncode(summary.splits!.map((split) => split.toJson()).toList()),
      'temperature_json': summary.temperature == null
          ? null
          : jsonEncode(summary.temperature!.toJson()),
    };
    try {
      final db = await _open();
      await db.transaction((txn) async {
        final existing = await txn.query(
          'pending_runs',
          where: 'namespace = ? AND owner_id = ? AND client_run_id = ?',
          whereArgs: [namespace, ownerId, summary.clientRunId],
        );
        if (existing.isNotEmpty) {
          // 이미 보관한 기록의 값을 바꾸지 않아 재전송 내용이 항상 같습니다.
          if (!row.entries.every(
            (entry) => existing.single[entry.key] == entry.value,
          )) {
            throw const RunOutboxException('같은 러닝 기록의 측정값이 다릅니다.');
          }
          return;
        }
        await txn.insert('pending_runs', row);
      });
    } on RunOutboxException {
      rethrow;
    } catch (_) {
      throw const RunOutboxException(
        '기기에 기록을 저장하지 못했습니다. 저장 공간을 확인하고 다시 시도해 주세요.',
      );
    }
  }

  @override
  Future<List<RunSummary>> list() async {
    try {
      final db = await _open();
      final rows = await db.query(
        'pending_runs',
        where: 'namespace = ? AND owner_id = ?',
        whereArgs: [namespace, ownerId],
        orderBy: 'started_at DESC, client_run_id DESC',
      );
      return rows
          .map(
            (row) => RunSummary(
              clientRunId: row['client_run_id'] as String,
              startedAt: DateTime.parse(row['started_at'] as String),
              endedAt: DateTime.parse(row['ended_at'] as String),
              distanceMeters: (row['distance_m'] as num).toDouble(),
              duration: Duration(microseconds: row['duration_us'] as int),
              route: RunRoute.fromJson(jsonDecode(row['route_json'] as String)),
              motionSamples: row['motion_json'] == null
                  ? null
                  : RunMotionTracker.decode(
                      jsonDecode(row['motion_json'] as String),
                    ),
              splits: row['splits_json'] == null
                  ? null
                  : RunSplit.decode(jsonDecode(row['splits_json'] as String)),
              temperature: row['temperature_json'] == null
                  ? null
                  : RunTemperature.fromJson(
                      jsonDecode(row['temperature_json'] as String)
                          as Map<String, dynamic>,
                    ),
            ),
          )
          .toList();
    } catch (_) {
      throw const RunOutboxException('기기에 보관한 기록을 읽지 못했습니다. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> remove(String clientRunId) async {
    try {
      final db = await _open();
      await db.delete(
        'pending_runs',
        where: 'namespace = ? AND owner_id = ? AND client_run_id = ?',
        whereArgs: [namespace, ownerId, clientRunId],
      );
    } catch (_) {
      throw const RunOutboxException('서버 저장 확인을 기기에 반영하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final database = _database;
    if (database != null) await (await database).close();
  }
}
