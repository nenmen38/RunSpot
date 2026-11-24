import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/data/achievement_service.dart';
import '../../titles/title_service.dart';
import '../../run_history/models/run_record.dart';

typedef ShareHighlights = ({
  String? title,
  String? achievement,
  String? milestone,
});
typedef ShareHighlightChoices = ({
  List<String> titles,
  List<String> achievements,
  List<String>? milestones,
});

Future<ShareHighlightChoices> loadShareHighlights(
  SupabaseClient client,
  RunRecord record,
) async {
  final session = client.auth.currentSession;
  if (session == null) throw const AuthException('로그인이 필요합니다.');
  Future<Map?> loadMilestones() async {
    if (record.pendingSync) return const {};
    try {
      return await client
              .rpc(
                'my_run_share_milestones',
                params: {'requested_run': record.id},
              )
              .setHeader('Authorization', 'Bearer ${session.accessToken}')
          as Map;
    } on PostgrestException catch (error) {
      // 성과 기능을 제공하지 않는 서버에서도 칭호와 업적은 선택할 수 있습니다.
      if (error.code == 'PGRST202') return null;
      rethrow;
    }
  }

  final titles = SupabaseTitleService(client);
  final achievements = SupabaseAchievementService(client);
  final (titleState, earned, milestones) = await (
    titles.load(),
    achievements.load(),
    loadMilestones(),
  ).wait;
  if (client.auth.currentSession?.user.id != session.user.id) {
    throw const AuthException('계정이 변경되었습니다.');
  }
  return (
    milestones: milestones == null
        ? null
        : [
            if (milestones['first_5k'] == true) '첫 5km 완주',
            if (milestones['monthly_runs'] case final int count when count > 0)
              '${record.startedAt.toUtc().add(const Duration(hours: 9)).month}월 $count번째 러닝',
            if (milestones['together'] == true) '함께 달린 러닝',
          ],
    titles: [
      for (final title in titleState.titles)
        if (title.earned) title.title.label,
    ],
    achievements: [
      for (final achievement in earned)
        if (achievement.achievedAt != null) achievement.title,
    ],
  );
}
