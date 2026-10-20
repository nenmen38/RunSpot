import 'package:flutter/material.dart';

import '../../../shared/widgets/account_query_panel.dart';
import '../../../shared/widgets/page_layout.dart';
import '../data/ranking_service.dart';
import '../models/weekly_ranking.dart';
import 'ranking_widgets.dart';

class FriendRanking extends StatelessWidget {
  const FriendRanking({required this.service, this.revision = 0, super.key});
  final RankingService service;
  final int revision;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 12),
      const SectionHeader(
        title: '친구 랭킹',
        subtitle: '이번 주 누적 거리 · 한국 시간 월요일부터',
        icon: Icons.leaderboard_outlined,
      ),
      const SizedBox(height: 10),
      AccountQueryPanel<WeeklyRanking>(
        source: service,
        revision: revision,
        load: service.load,
        isCurrentOwner: () => service.isCurrentOwner,
        errorMessage: '친구 랭킹을 불러오지 못했습니다.',
        builder: (context, ranking) {
          if (!ranking.canInteract) {
            return const Text('이메일 인증과 닉네임 등록 후 랭킹을 확인할 수 있습니다.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ranking.entries.isEmpty) const Text('표시할 주간 순위가 없습니다.'),
              for (final runner in ranking.entries)
                SizedBox(height: 64, child: RankRow(runner: runner)),
              const SizedBox(height: 10),
              const Text(
                '본인과 공개 범위가 허용된 친구만 표시합니다.\n서버 저장 완료 기록 기준 · 같은 거리는 공동 순위\n측정 거리 비교이며 기록 검증 완료를 의미하지 않습니다.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          );
        },
      ),
    ],
  );
}
