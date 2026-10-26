import '../../home/models/run_session.dart';
import 'run_route.dart';
import 'run_temperature.dart';
import 'run_split.dart';
import 'run_motion_evidence.dart';

class RunRecord {
  const RunRecord({
    required this.id,
    required this.clientRunId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    this.pendingSync = false,
    this.route,
    this.temperature,
    this.splits,
    this.motionEvidence,
    this.reviewPending = false,
    this.integrityStatus = 'pending',
  });

  final String id;
  final String clientRunId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int distanceMeters;
  final int durationSeconds;
  final bool pendingSync;
  final RunRoute? route;
  final RunTemperature? temperature;
  final List<RunSplit>? splits;
  final List<RunMotionEvidence>? motionEvidence;
  final bool reviewPending;
  final String integrityStatus;

  factory RunRecord.pending(RunSummary summary) => RunRecord(
    id: summary.clientRunId,
    clientRunId: summary.clientRunId,
    startedAt: summary.startedAt,
    endedAt: summary.endedAt,
    distanceMeters: summary.distanceMeters.round(),
    durationSeconds: summary.duration.inSeconds,
    pendingSync: true,
    route: summary.route,
    temperature: summary.temperature,
    splits: summary.splits,
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
    temperature: RunTemperature.fromJson(row),
    splits: RunSplit.decode(row['split_data']),
    motionEvidence: RunMotionEvidence.decode(row['motion_evidence']),
    reviewPending: row['review_pending'] == true,
    integrityStatus: row['integrity_status'] as String? ?? 'pending',
  );
}
