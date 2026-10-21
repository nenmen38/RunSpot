import 'package:flutter/material.dart';
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
    return rows.map((row) {
      final progress = row['progress'] as int;
      final target = row['target'] as int;
      if (target <= 0 || progress < 0 || progress > target) {
        throw const FormatException('업적 응답을 확인해 주세요.');
      }
      final distance = row['metric'] == 'distance_m';
      return Achievement(
        row['title'] as String,
        distance
            ? '${(progress / 1000).toStringAsFixed(1)} / ${target ~/ 1000}km'
            : '$progress / $target회',
        Icons.military_tech_outlined,
        progress / target,
        achievedAt: row['achieved_at'] == null
            ? null
            : DateTime.parse(row['achieved_at'] as String),
      );
    }).toList();
  }
}
