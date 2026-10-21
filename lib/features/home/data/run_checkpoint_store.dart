import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../run_history/models/run_route.dart';
import '../../run_history/models/run_temperature.dart';
import '../models/run_session.dart';

class RunCheckpoint {
  const RunCheckpoint(this.summary, {required this.finished});
  final RunSummary summary;
  final bool finished;
}

abstract interface class RunCheckpointStore {
  Future<RunCheckpoint?> load();
  Future<void> save(RunCheckpoint checkpoint);
  Future<void> clear();
  Future<void> close();
}

class SqliteRunCheckpointStore implements RunCheckpointStore {
  SqliteRunCheckpointStore({
    required this.ownerId,
    required this.namespace,
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  }) : _factory = factory ?? databaseFactory,
       _path = databasePath ?? _defaultPath;
  final String ownerId;
  final String namespace;
  final DatabaseFactory _factory;
  final Future<String> Function() _path;
  Future<Database>? _database;
  bool _closed = false;

  static Future<String> _defaultPath() async => path.join(
    (await getApplicationSupportDirectory()).path,
    'active_run.sqlite',
  );

  Future<Database> _open() async {
    if (_closed) throw StateError('러닝 복구 저장소가 닫혔습니다.');
    try {
      return await (_database ??= _create());
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  Future<Database> _create() async => _factory.openDatabase(
    await _path(),
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA synchronous = FULL'),
      onCreate: (db, _) => db.execute('''CREATE TABLE active_runs (
      namespace TEXT NOT NULL, owner_id TEXT NOT NULL, payload TEXT NOT NULL,
      PRIMARY KEY(namespace,owner_id))'''),
    ),
  );

  @override
  Future<void> save(RunCheckpoint checkpoint) async {
    final summary = checkpoint.summary;
    if (!summary.distanceMeters.isFinite ||
        summary.distanceMeters < 0 ||
        summary.duration.isNegative ||
        summary.endedAt.isBefore(summary.startedAt)) {
      throw const FormatException('복구할 측정값이 올바르지 않습니다.');
    }
    final db = await _open();
    await db.insert('active_runs', {
      'namespace': namespace,
      'owner_id': ownerId,
      'payload': jsonEncode({
        'id': summary.clientRunId,
        'start': summary.startedAt.toIso8601String(),
        'end': summary.endedAt.toIso8601String(),
        'distance': summary.distanceMeters,
        'duration': summary.duration.inMicroseconds,
        'route': summary.route.toJson(),
        'temperature': summary.temperature?.toJson(),
        'finished': checkpoint.finished,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<RunCheckpoint?> load() async {
    final rows = await (await _open()).query(
      'active_runs',
      where: 'namespace = ? AND owner_id = ?',
      whereArgs: [namespace, ownerId],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
    final summary = RunSummary(
      clientRunId: json['id'] as String,
      startedAt: DateTime.parse(json['start'] as String),
      endedAt: DateTime.parse(json['end'] as String),
      distanceMeters: (json['distance'] as num).toDouble(),
      duration: Duration(microseconds: json['duration'] as int),
      route: RunRoute.fromJson(json['route']),
      temperature: json['temperature'] == null
          ? null
          : RunTemperature.fromJson(
              Map<String, dynamic>.from(json['temperature'] as Map),
            ),
    );
    if (!summary.distanceMeters.isFinite ||
        summary.distanceMeters < 0 ||
        summary.duration.isNegative ||
        summary.endedAt.isBefore(summary.startedAt) ||
        summary.duration >
            summary.endedAt.difference(summary.startedAt) +
                const Duration(seconds: 1)) {
      throw const FormatException('저장된 러닝 측정값을 확인해 주세요.');
    }
    return RunCheckpoint(summary, finished: json['finished'] as bool);
  }

  @override
  Future<void> clear() async {
    await (await _open()).delete(
      'active_runs',
      where: 'namespace = ? AND owner_id = ?',
      whereArgs: [namespace, ownerId],
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_database case final database?) await (await database).close();
  }
}
