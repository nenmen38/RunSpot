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
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';

import 'widgets/recent_runs.dart';

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '프로필',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (onSettingsTap != null)
                  IconButton(
                    tooltip: '설정',
                    onPressed: onSettingsTap,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PrivacyControls(
                    sharingController: mapController,
                    identityOnly: true,
                  ),
                  if (progressService != null) ...[
                    const SizedBox(height: 12),
                    ProfileLevelCard(service: progressService!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (statisticsService != null)
              QuickStats(service: statisticsService!),
            const SizedBox(height: 20),
            if (mapController != null)
              RecentRuns(
                controller: mapController!.runHistory,
                onHistoryTap: onHistoryTap,
              )
            else
              ListTile(
                title: const Text('내 기록'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onHistoryTap,
              ),
            const SizedBox(height: 20),
            Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '대표 업적',
                    subtitle: '러닝으로 쌓은 성취',
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
