import 'package:flutter/material.dart';
import 'package:runquest/features/social/data/rankings.dart';
import 'package:runquest/features/social/widgets/ranking_widgets.dart';
import 'package:runquest/features/social/widgets/share_card.dart';
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';

class SocialScreen extends StatelessWidget {
  const SocialScreen({
    required this.rankingMode,
    required this.onModeChanged,
    super.key,
  });

  final int rankingMode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final modes = ['거리', '성장', '5K', '꾸준'];
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '소셜', subtitle: '친구와 기록을 비교해요'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < modes.length; i++) ...[
                Expanded(
                  child: TinyTab(
                    label: modes[i],
                    selected: i == rankingMode,
                    onTap: () => onModeChanged(i),
                  ),
                ),
                if (i != modes.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '친구 랭킹',
                    subtitle: '이번 주 기준',
                    icon: Icons.leaderboard_outlined,
                  ),
                  const SizedBox(height: 10),
                  for (final runner in rankings)
                    Expanded(child: RankRow(runner: runner)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const ShareCard(),
        ],
      ),
    );
  }
}
