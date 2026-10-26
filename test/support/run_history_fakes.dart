import 'dart:async';

import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/data/run_record_service.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';

class FakeRunRecordService implements RunRecordService {
  FakeRunRecordService({this.ownerId = 'owner'});
  @override
  final String ownerId;
  @override
  bool isCurrentOwner = true;
  final records = <RunRecord>[];
  final attempts = <RunSummary>[];
  final offsets = <int>[];
  Object? saveFailure;
  Object? listFailure;
  Completer<void>? pendingSave;
  Object? responseFailure;
  Object? routeFailure;
  final routes = <String, RunRoute>{};
  final routeRequests = <String>[];

  @override
  Future<RunRecord> save(RunSummary summary) async {
    attempts.add(summary);
    await pendingSave?.future;
    if (saveFailure != null) throw saveFailure!;
    final existing = records.where(
      (row) => row.clientRunId == summary.clientRunId,
    );
    if (existing.isNotEmpty) return existing.first;
    final record = RunRecord(
      id: summary.clientRunId,
      clientRunId: summary.clientRunId,
      startedAt: summary.startedAt,
      endedAt: summary.endedAt,
      distanceMeters: summary.distanceMeters.round(),
      durationSeconds: summary.duration.inSeconds,
      temperature: summary.temperature,
      splits: summary.splits,
    );
    records.insert(0, record);
    routes[record.id] = summary.route;
    if (responseFailure != null) throw responseFailure!;
    return record;
  }

  @override
  Future<void> setHidden(String runId, bool hidden) async {
    final index = records.indexWhere((record) => record.id == runId);
    if (index >= 0) records[index] = records[index].withHidden(hidden);
  }

  @override
  Future<RunRoute> loadRoute(String runId) async {
    routeRequests.add(runId);
    if (routeFailure != null) throw routeFailure!;
    return routes[runId] ?? const RunRoute.empty();
  }

  @override
  Future<List<RunRecord>> list({
    required int offset,
    required int limit,
  }) async {
    offsets.add(offset);
    if (listFailure != null) throw listFailure!;
    return records.skip(offset).take(limit).toList();
  }
}

class FakeRunOutbox implements RunOutbox {
  FakeRunOutbox({this.ownerId = 'owner', Map<String, RunSummary>? rows})
    : rows = rows ?? {};
  @override
  final String ownerId;
  final Map<String, RunSummary> rows;
  Object? putFailure;
  Object? listFailure;
  Object? removeFailure;
  bool closed = false;

  @override
  Future<void> put(RunSummary summary) async {
    if (putFailure != null) throw putFailure!;
    rows.putIfAbsent(summary.clientRunId, () => summary);
  }

  @override
  Future<List<RunSummary>> list() async {
    if (listFailure != null) throw listFailure!;
    return rows.values.toList();
  }

  @override
  Future<void> remove(String clientRunId) async {
    if (removeFailure != null) throw removeFailure!;
    rows.remove(clientRunId);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
