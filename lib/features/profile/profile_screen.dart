import 'package:flutter/material.dart';

import '../home/live_map_controller.dart';

import 'data/achievement_service.dart';
import 'models/achievement.dart';
import '../../shared/widgets/account_query_panel.dart';

import 'package:runquest/features/profile/data/statistics_service.dart';
import 'package:runquest/features/profile/privacy_controls.dart';
import 'package:runquest/features/profile/widgets/achievement_row.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';
import 'package:runquest/features/progress/data/progress_service.dart';
import 'package:runquest/features/progress/widgets/profile_level_card.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.onHistoryTap,
    this.onSettingsTap,
    this.progressService,
    this.statisticsService,
    this.mapController,
    this.achievementService,
    super.key,
  });
  final VoidCallback onHistoryTap;
  final VoidCallback? onSettingsTap;
  final ProgressService? progressService;
  final StatisticsService? statisticsService;
  final LiveMapController? mapController;
  final AchievementService? achievementService;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppTopBar(title: '프로필', subtitle: '통계와 업적 공개 범위 설정'),
            if (onSettingsTap != null)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(
                  Icons.settings_outlined,
                  color: AppColors.blue,
                ),
                title: const Text('설정'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onSettingsTap,
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.history, color: AppColors.blue),
              title: const Text('내 기록'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onHistoryTap,
            ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: AppColors.blueSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_run,
                          color: AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '내 프로필',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Icon(Icons.ios_share, color: AppColors.blue),
                    ],
                  ),
                  if (progressService != null) ...[
                    const SizedBox(height: 12),
                    ProfileLevelCard(service: progressService!),
                  ],
                  const SizedBox(height: 12),
                  PrivacyControls(sharingController: mapController),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('로그아웃'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (statisticsService != null)
              QuickStats(service: statisticsService!),
            const SizedBox(height: 10),
            Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '대표 업적',
                    subtitle: '프로필에 표시돼요',
                    icon: Icons.military_tech_outlined,
                  ),
                  const SizedBox(height: 10),
                  if (achievementService case final service?)
                    AccountQueryPanel<List<Achievement>>(
                      source: service,
                      load: service.load,
                      isCurrentOwner: () => service.isCurrentOwner,
                      errorMessage: '업적을 불러오지 못했습니다.',
                      builder: (context, items) => Column(
                        children: [
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: AchievementRow(achievement: item),
                            ),
                        ],
                      ),
                    )
                  else
                    const Text('업적을 조회할 수 없습니다.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
