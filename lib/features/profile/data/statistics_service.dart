import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/run_statistics.dart';

abstract interface class StatisticsService {
  bool get isCurrentOwner;
  Future<RunStatistics> load();
}

class SupabaseStatisticsService implements StatisticsService {
  SupabaseStatisticsService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  @override
  Future<RunStatistics> load() async {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc('my_run_statistics')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return RunStatistics.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
