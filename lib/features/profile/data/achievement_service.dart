import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/achievement.dart';

abstract interface class AchievementService {
  bool get isCurrentOwner;
  Future<List<Achievement>> load();
}

class SupabaseAchievementService implements AchievementService {
  SupabaseAchievementService(this.client)
    : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;
  @override
  Future<List<Achievement>> load() async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final rows =
        await client
                .rpc('my_achievements')
                .setHeader('Authorization', 'Bearer ${session.accessToken}')
            as List;
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return rows.map(Achievement.fromJson).toList();
  }
}
