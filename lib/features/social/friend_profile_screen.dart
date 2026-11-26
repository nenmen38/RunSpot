import 'package:flutter/material.dart';
import 'package:runquest/features/profile/reportable_avatar_header.dart';

import '../../shared/widgets/account_query_panel.dart';
import '../character/runner_character_directory.dart';
import '../../shared/widgets/page_layout.dart';
import '../../shared/widgets/panel.dart';
import '../profile/widgets/achievement_row.dart';
import '../profile/widgets/quick_stats.dart';
import '../progress/models/run_progress.dart';
import '../progress/widgets/level_progress_bar.dart';
import 'data/friend_service.dart';
import 'models/friend_entry.dart';
import 'models/friend_profile.dart';

class FriendProfileScreen extends StatelessWidget {
  const FriendProfileScreen({
    required this.friend,
    required this.service,
    super.key,
  });

  final FriendEntry friend;
  final FriendService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('친구 프로필')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            AccountQueryPanel<({FriendProfile? profile})>(
              source: service,
              load: () async =>
                  (profile: await service.loadProfile(friend.userId)),
              isCurrentOwner: () => service.isCurrentOwner,
              errorMessage: '친구 프로필을 불러오지 못했습니다.',
              builder: (context, result) => _ProfileContent(
                userId: friend.userId,
                nickname: result.profile?.nickname ?? friend.nickname,
                profile: result.profile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.userId,
    required this.nickname,
    required this.profile,
  });

  final String userId;
  final String nickname;
  final FriendProfile? profile;

  @override
  Widget build(BuildContext context) {
    final details = profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportableAvatarHeader(userId: userId, nickname: nickname, size: 56),
              const SizedBox(height: 12),
              // 친구가 꾸민 러너 캐릭터를 좌우로 돌려 볼 수 있습니다.
              UserRunnerCharacter(userId: userId, height: 220),
              const SizedBox(height: 12),
              if (details != null) ...[
                Text(
                  '${levelTitle(details.progress.level)} · 누적 ${details.progress.totalXp} XP',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                LevelProgressBar(progress: details.progress),
              ] else
                const Text('공개된 활동 정보가 없습니다.'),
            ],
          ),
        ),
        if (details != null) ...[
          const SizedBox(height: 12),
          RunStatCards(stats: details.statistics),
          const SizedBox(height: 20),
          Panel(
            child: Column(
              children: [
                const SectionHeader(
                  title: '대표 업적',
                  subtitle: '러닝으로 쌓은 성취',
                  icon: Icons.military_tech_outlined,
                ),
                for (final achievement in details.achievements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: AchievementRow(achievement: achievement),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
