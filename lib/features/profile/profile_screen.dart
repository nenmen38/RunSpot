import 'package:flutter/material.dart';
import 'package:runquest/features/profile/data/achievements.dart';
import 'package:runquest/features/profile/privacy_controls.dart';
import 'package:runquest/features/profile/widgets/achievement_row.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '프로필', subtitle: '통계와 업적 공개 범위 설정'),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '내 프로필',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Lv.12 코스 탐색가',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.ios_share, color: AppColors.blue),
                  ],
                ),
                const SizedBox(height: 12),
                const PrivacyControls(),
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
          const QuickStats(),
          const SizedBox(height: 10),
          Expanded(
            child: Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '대표 업적',
                    subtitle: '프로필에 표시돼요',
                    icon: Icons.military_tech_outlined,
                  ),
                  const SizedBox(height: 10),
                  for (final item in achievements)
                    Expanded(child: AchievementRow(achievement: item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
