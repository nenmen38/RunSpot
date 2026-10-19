import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/run_progress.dart';

abstract interface class ProgressService {
  bool get isCurrentOwner;
  Future<RunProgress> load();

  /// 보상 대상이 아닌 기록이면 null을 반환합니다.
  Future<RunReward?> loadReward(String runId);
}

class SupabaseProgressService implements ProgressService {
  SupabaseProgressService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Session _session() {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return client.auth.currentSession!;
  }

  @override
  Future<RunProgress> load() async {
    final session = _session();
    final result = await client
        .rpc('my_progress')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _session();
    return RunProgress.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<RunReward?> loadReward(String runId) async {
    final session = _session();
    final result = await client
        .rpc('my_run_reward', params: {'requested_run_id': runId})
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _session();
    return RunReward.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
