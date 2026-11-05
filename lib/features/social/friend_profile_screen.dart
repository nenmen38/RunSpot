import 'package:flutter/material.dart';

import '../../shared/widgets/account_query_panel.dart';
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
  const _ProfileContent({required this.nickname, required this.profile});

  final String nickname;
  final FriendProfile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(nickname, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (details != null) ...[
                Text(
                  '${levelTitle(details.progress.level)} · 누적 ${details.progress.totalXp} XP',
                  style: theme.textTheme.bodyMedium,
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
