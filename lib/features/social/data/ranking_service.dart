import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/weekly_ranking.dart';

abstract interface class RankingService {
  bool get isCurrentOwner;
  Future<WeeklyRanking> load();
}

class SupabaseRankingService implements RankingService {
  SupabaseRankingService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  @override
  Future<WeeklyRanking> load() async {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc('friend_weekly_ranking')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return WeeklyRanking.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
