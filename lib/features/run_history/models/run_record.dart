import '../../home/models/run_session.dart';

class RunRecord {
  const RunRecord({
    required this.id,
    required this.clientRunId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    this.pendingSync = false,
  });

  final String id;
  final String clientRunId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int distanceMeters;
  final int durationSeconds;
  final bool pendingSync;

  factory RunRecord.pending(RunSummary summary) => RunRecord(
    id: summary.clientRunId,
    clientRunId: summary.clientRunId,
    startedAt: summary.startedAt,
    endedAt: summary.endedAt,
    distanceMeters: summary.distanceMeters.round(),
    durationSeconds: summary.duration.inSeconds,
    pendingSync: true,
  );

  int? get paceSeconds => distanceMeters > 0 && durationSeconds > 0
      ? (durationSeconds * 1000 / distanceMeters).round()
      : null;

  factory RunRecord.fromJson(Map<String, dynamic> row) => RunRecord(
    id: row['id'] as String,
    clientRunId: row['client_run_id'] as String,
    startedAt: DateTime.parse(row['started_at'] as String),
    endedAt: DateTime.parse(row['ended_at'] as String),
    distanceMeters: (row['distance_m'] as num).toInt(),
    durationSeconds: (row['duration_sec'] as num).toInt(),
  );
}
