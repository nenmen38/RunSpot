import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/models/run_session.dart';
import '../models/run_record.dart';
import '../models/run_route.dart';

abstract interface class RunRecordService {
  String get ownerId;
  bool get isCurrentOwner;
  Future<RunRecord> save(RunSummary summary);
  Future<List<RunRecord>> list({required int offset, required int limit});
  Future<RunRoute> loadRoute(String runId);
}

class SupabaseRunRecordService implements RunRecordService {
  SupabaseRunRecordService(this.client)
    : ownerId =
          client.auth.currentUser?.id ??
          (throw const AuthException('로그인이 필요합니다.'));

  final SupabaseClient client;
  @override
  final String ownerId;

  @override
  bool get isCurrentOwner => client.auth.currentSession?.user.id == ownerId;

  Session _requireOwner() {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != ownerId) {
      throw const AuthException('로그인이 필요합니다.');
    }
    return session;
  }

  @override
  Future<RunRecord> save(RunSummary summary) async {
    final session = _requireOwner();
    // 계정 전환 중에도 측정한 계정의 세션으로만 요청을 전송합니다.
    final row = await client
        .rpc(
          summary.motionSamples == null
              ? 'save_my_run_with_splits'
              : 'save_my_run_with_motion',
          params: {
            if (summary.motionSamples != null)
              'motion_samples': summary.motionSamples,
            'client_id': summary.clientRunId,
            'start_time': summary.startedAt.toUtc().toIso8601String(),
            'end_time': summary.endedAt.toUtc().toIso8601String(),
            'distance_metres': summary.distanceMeters.round(),
            'active_seconds': summary.duration.inSeconds,
            'route_segments': summary.route.toJson(),
            'split_data': summary.splits
                ?.map((split) => split.toJson())
                .toList(),
            'temperature_c': summary.temperature?.celsius,
            'temperature_observed_at': summary.temperature?.observedAt
                .toIso8601String(),
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    return RunRecord.fromJson(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<RunRoute> loadRoute(String runId) async {
    final session = _requireOwner();
    final route = await client
        .rpc('my_run_route', params: {'requested_run_id': runId})
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    return RunRoute.fromJson(route);
  }

  @override
  Future<List<RunRecord>> list({
    required int offset,
    required int limit,
  }) async {
    final session = _requireOwner();
    final rows = await client
        .from('runs')
        .select(
          'id,client_run_id,started_at,ended_at,distance_m,duration_sec,temperature_c,temperature_observed_at,split_data,review_pending,integrity_status,motion_evidence',
        )
        .eq('user_id', session.user.id)
        .order('started_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    return rows.map(RunRecord.fromJson).toList();
  }
}
