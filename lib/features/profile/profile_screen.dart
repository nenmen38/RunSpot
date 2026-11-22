import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/titles/title_service.dart';

import '../training/training_screen.dart';

import 'package:runquest/features/profile/data/personal_records_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../monetization/partner_offers.dart';
import '../monetization/profile_cosmetics.dart';

import '../home/live_map_controller.dart';

import 'data/achievement_service.dart';

import 'package:runquest/features/profile/data/statistics_service.dart';
import 'package:runquest/features/profile/privacy_controls.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';
import 'package:runquest/features/progress/data/progress_service.dart';
import 'package:runquest/features/progress/widgets/profile_level_card.dart';
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';

import 'profile_detail_screens.dart';
import 'widgets/recent_runs.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.onHistoryTap,
    this.onSettingsTap,
    this.progressService,
    this.personalRecordsService,
    this.titleService,
    this.wallet,
    this.statisticsService,
    this.mapController,
    this.achievementService,
    this.commerceClient,
    super.key,
  });
  final VoidCallback onHistoryTap;
  final VoidCallback? onSettingsTap;
  final ProgressService? progressService;

  /// 있으면 1km·5km·10km 개인 최고 기록을 보여줍니다.
  final PersonalRecordsService? personalRecordsService;

  /// 있으면 달려서 얻은 칭호 카드를 보여줍니다.
  final TitleService? titleService;

  /// 칭호 모양 미리보기에 씁니다.
  final WalletController? wallet;
  final StatisticsService? statisticsService;
  final LiveMapController? mapController;
  final AchievementService? achievementService;
  final SupabaseClient? commerceClient;

  @override
  Widget build(BuildContext context) {
    final identity = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrivacyControls(sharingController: mapController, identityOnly: true),
          if (progressService != null) ...[
            const SizedBox(height: 12),
            ProfileLevelCard(service: progressService!),
          ],
        ],
      ),
    );
    return PageFrame(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '프로필',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(onPressed: onHistoryTap, child: const Text('내 기록')),
                if (onSettingsTap != null)
                  IconButton(
                    tooltip: '설정',
                    onPressed: onSettingsTap,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (commerceClient case final client?)
              ProfileCosmetics(client: client, child: identity)
            else
              identity,
            if (statisticsService case final service?) ...[
              const SizedBox(height: 12),
              WeeklyGoalSummary(service: service),
            ],
            if (commerceClient case final client?) ...[
              const SizedBox(height: 8),
              _ProfileLink(
                icon: Icons.calendar_month_outlined,
                title: '나의 훈련 계획',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => TrainingScreen(client: client),
                  ),
                ),
              ),
            ],
            if (mapController case final controller?) ...[
              const SizedBox(height: 12),
              RecentRuns(controller: controller.runHistory),
            ],
            if (statisticsService != null ||
                personalRecordsService != null ||
                titleService != null ||
                achievementService != null) ...[
              const SizedBox(height: 12),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (statisticsService != null ||
                        personalRecordsService != null)
                      _ProfileLink(
                        icon: Icons.insights_outlined,
                        title: '러닝 통계',
                        subtitle: [
                          if (statisticsService != null) '성장 추이',
                          if (personalRecordsService != null) '개인 최고 기록',
                        ].join(' · '),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ProfileStatisticsScreen(
                              statistics: statisticsService,
                              personalRecords: personalRecordsService,
                            ),
                          ),
                        ),
                      ),
                    if ((statisticsService != null ||
                            personalRecordsService != null) &&
                        (titleService != null || achievementService != null))
                      const Divider(height: 1, indent: 14, endIndent: 14),
                    if (titleService != null || achievementService != null)
                      _ProfileLink(
                        icon: Icons.military_tech_outlined,
                        title: '칭호와 업적',
                        subtitle: [
                          if (titleService != null) '칭호 착용',
                          if (achievementService != null) '업적 달성 현황',
                        ].join(' · '),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ProfileAchievementsScreen(
                              titles: titleService,
                              achievements: achievementService,
                              wallet: wallet,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (commerceClient case final client?)
              PartnerOffers(client: client),
          ],
        ),
      ),
    );
  }
}

class _ProfileLink extends StatelessWidget {
  const _ProfileLink({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
