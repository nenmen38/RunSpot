import 'dart:typed_data';

import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/titles/title_service.dart';

import '../training/training_screen.dart';

import 'package:runquest/features/profile/data/personal_records_service.dart';
import 'package:flutter/material.dart';

import '../character/character_background.dart';
import 'profile_sections.dart';

import 'package:runquest/features/character/character_outfit.dart';
import 'package:runquest/features/character/character_card_share.dart';
import 'package:runquest/features/character/character_profile_card.dart';
import 'package:runquest/features/character/runner_character_card.dart';
import 'package:runquest/features/profile/monthly_challenges.dart';
import 'package:runquest/features/profile/running_streak.dart';
import 'package:runquest/features/report/running_report.dart';
import 'package:runquest/features/report/running_report_screen.dart';
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
import 'widgets/weekly_quest_panel.dart';

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
    this.onShareToBoard,
    super.key,
  });

  /// 프로필 카드를 게시판 글에 붙여 올리려 할 때 부릅니다(게시판 탭을 열고 글쓰기에 사진을 붙입니다).
  final void Function(Uint8List jpeg)? onShareToBoard;
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

  /// 닉네임과 레벨을 읽어 내 러너 프로필 카드 공유 창을 엽니다.
  Future<void> _shareCard(BuildContext context) async {
    final client = commerceClient;
    if (client == null) return;
    var nickname = '러너';
    var level = 1;
    try {
      final row = await client
          .from('profiles')
          .select('nickname')
          .eq('id', client.auth.currentUser!.id)
          .single();
      nickname = (row['nickname'] as String?) ?? nickname;
    } catch (_) {
      // 닉네임을 못 읽어도 카드는 만들 수 있습니다.
    }
    try {
      level = (await progressService?.load())?.level ?? level;
    } catch (_) {}
    if (!context.mounted) return;
    await showCharacterCardSheet(
      context,
      data: CharacterCardData.fromWallet(
        wallet?.wallet,
        nickname: nickname,
        level: level,
        background: CharacterBackground.instance.provider,
      ),
      actions: DeviceCharacterCardActions(
        client: client,
        onOpenBoard: onShareToBoard ?? (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrivacyControls(sharingController: mapController, identityOnly: true),
          // 내 러너 캐릭터: 입은 아이템이 바로 보이고 좌우로 돌려 볼 수 있습니다.
          // 줄 전체를 눌러 접고 펼 수 있어요(상태는 기기에 저장).
          ListenableBuilder(
            listenable: ProfileSections.instance,
            builder: (context, _) {
              final open = ProfileSections.instance.isOpen(ProfileSection.card);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        ProfileSections.instance.toggle(ProfileSection.card),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '프로필 카드',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SectionToggle(
                            section: ProfileSection.card,
                            label: '프로필 카드',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Collapsible(
                    open: open,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        RunnerCharacterCard(
                          wallet: wallet,
                          // 그림 오른쪽 위 반투명 버튼: 꾸미기(옷걸이)·배경 사진.
                          showActions: true,
                          // 카드를 이미지로 저장하거나 채팅·게시판으로 보낼 수 있습니다(서버 연결이 있을 때).
                          onShare: commerceClient == null
                              ? null
                              : () => _shareCard(context),
                        ),
                        if (progressService != null) ...[
                          const SizedBox(height: 16),
                          Divider(height: 1, color: AppColors.line),
                          const SizedBox(height: 16),
                          ProfileLevelCard(service: progressService!),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
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
            // 주간 목표를 몇 주 연속 지켰는지 보여 줍니다(기록이 없으면 숨김).
            const RunningStreakCard(),
            // 이번 달 개인 챌린지(50km·주말 4번·10일)와 보상입니다.
            if (commerceClient case final client?) ...[
              const SizedBox(height: 12),
              MonthlyChallengeCard(service: SupabaseChallengeService(client)),
            ],
            if (wallet case final controller?)
              WeeklyQuestPanel(controller: controller),
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
              const SizedBox(height: 8),
              _ReportLink(client: client, wallet: wallet),
            ],
            if (mapController case final controller?) ...[
              const SizedBox(height: 12),
              RecentRuns(controller: controller.runHistory, wallet: wallet),
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

/// '러닝 리포트' 진입점입니다. 12월·1월에는 연말 결산이 도착했다고 알려 줍니다.
class _ReportLink extends StatelessWidget {
  const _ReportLink({required this.client, this.wallet});

  final SupabaseClient client;
  final WalletController? wallet;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearEnd = now.month == 12 || now.month == 1;
    final year = now.month == 1 ? now.year - 1 : now.year;
    return _ProfileLink(
      icon: yearEnd ? Icons.celebration_outlined : Icons.auto_graph,
      title: yearEnd ? '$year 연말 결산이 도착했어요 🎉' : '러닝 리포트',
      subtitle: '이번 달과 올해 달린 기록을 한눈에',
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RunningReportScreen(
            service: SupabaseRunningReportService(client),
            outfit: characterOutfit(wornCharacterItems(wallet?.wallet).values),
          ),
        ),
      ),
    );
  }
}
