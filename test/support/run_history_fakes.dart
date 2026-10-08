import 'dart:async';

import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_record_service.dart';
import 'package:runquest/features/run_history/models/run_record.dart';

class FakeRunRecordService implements RunRecordService {
  final records = <RunRecord>[];
  final attempts = <RunSummary>[];
  final offsets = <int>[];
  Object? saveFailure;
  Object? listFailure;
  Completer<void>? pendingSave;

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
    );
    records.insert(0, record);
    return record;
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
