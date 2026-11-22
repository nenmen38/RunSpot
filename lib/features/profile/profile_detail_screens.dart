import 'package:flutter/material.dart';

import '../../shared/layout/readable_width.dart';
import '../../shared/widgets/account_query_panel.dart';
import '../../shared/widgets/page_layout.dart';
import '../../shared/widgets/panel.dart';
import '../monetization/coin_frames.dart';
import '../monetization/cosmetics.dart';
import '../titles/title_service.dart';
import '../titles/titles_card.dart';
import 'data/achievement_service.dart';
import 'data/personal_records_service.dart';
import 'data/statistics_service.dart';
import 'models/achievement.dart';
import 'widgets/achievement_row.dart';
import 'widgets/personal_records_card.dart';
import 'widgets/quick_stats.dart';

class ProfileStatisticsScreen extends StatelessWidget {
  const ProfileStatisticsScreen({
    this.statistics,
    this.personalRecords,
    super.key,
  });

  final StatisticsService? statistics;
  final PersonalRecordsService? personalRecords;

  @override
  Widget build(BuildContext context) => _ProfileDetailPage(
    title: '러닝 통계',
    children: [
      if (statistics case final service?) QuickStats(service: service),
      if (personalRecords case final service?) ...[
        if (statistics != null) const SizedBox(height: 12),
        PersonalRecordsCard(service: service),
      ],
    ],
  );
}

class ProfileAchievementsScreen extends StatelessWidget {
  const ProfileAchievementsScreen({
    this.titles,
    this.achievements,
    this.wallet,
    super.key,
  });

  final TitleService? titles;
  final AchievementService? achievements;
  final WalletController? wallet;

  @override
  Widget build(BuildContext context) => _ProfileDetailPage(
    title: '칭호와 업적',
    children: [
      if (titles case final service?)
        if (wallet case final current?)
          ListenableBuilder(
            listenable: current,
            builder: (context, _) => TitlesCard(
              service: service,
              titleStyle: current.equippedIn(CosmeticSlot.titleStyle),
            ),
          )
        else
          TitlesCard(service: service),
      if (achievements case final service?) ...[
        if (titles != null) const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              const SectionHeader(
                title: '대표 업적',
                subtitle: '러닝으로 쌓은 성취',
                icon: Icons.military_tech_outlined,
              ),
              const SizedBox(height: 10),
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
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _ProfileDetailPage extends StatelessWidget {
  const _ProfileDetailPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: children,
        ),
      ),
    ),
  );
}
