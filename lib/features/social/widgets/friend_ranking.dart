import 'package:flutter/material.dart';

import '../../../shared/widgets/page_layout.dart';
import '../data/rankings.dart';
import 'ranking_widgets.dart';
import 'share_card.dart';

class FriendRanking extends StatelessWidget {
  const FriendRanking({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });
  final int mode;
  final ValueChanged<int> onModeChanged;
  @override
  Widget build(BuildContext context) {
    final modes = ['거리', '성장', '5K', '꾸준'];
    return ListView(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < modes.length; i++) ...[
              Expanded(
                child: TinyTab(
                  label: modes[i],
                  selected: i == mode,
                  onTap: () => onModeChanged(i),
                ),
              ),
              if (i != modes.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 12),
        const SectionHeader(
          title: '친구 랭킹',
          subtitle: '이번 주 기준',
          icon: Icons.leaderboard_outlined,
        ),
        const SizedBox(height: 10),
        for (final runner in rankings)
          SizedBox(height: 64, child: RankRow(runner: runner)),
        const SizedBox(height: 10),
        const ShareCard(),
      ],
    );
  }
}
