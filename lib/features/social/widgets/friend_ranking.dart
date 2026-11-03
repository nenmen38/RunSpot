import 'package:flutter/material.dart';

import '../../../shared/widgets/account_query_panel.dart';
import '../../../shared/widgets/page_layout.dart';
import '../data/ranking_service.dart';
import '../models/weekly_ranking.dart';
import 'ranking_widgets.dart';

class FriendRanking extends StatefulWidget {
  const FriendRanking({required this.service, this.revision = 0, super.key});
  final RankingService service;
  final int revision;
  @override
  State<FriendRanking> createState() => _FriendRankingState();
}

class _FriendRankingState extends State<FriendRanking> {
  RankingCategory _category = RankingCategory.distance;
  RankingAudience _audience = RankingAudience.friends;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SectionHeader(
              title: '랭킹',
              subtitle: _category == RankingCategory.fiveK
                  ? '5km 최고 기록 · 전체 기간'
                  : '이번 주 · 한국 시간 월요일부터',
              icon: Icons.leaderboard_outlined,
            ),
          ),
          PopupMenuButton<RankingAudience>(
            tooltip: '랭킹 대상 선택',
            initialValue: _audience,
            onSelected: (value) => setState(() => _audience = value),
            itemBuilder: (_) => [
              for (final audience in RankingAudience.values)
                PopupMenuItem(
                  value: audience,
                  child: Text(
                    audience == RankingAudience.friends ? '친구' : '전체',
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _audience == RankingAudience.friends ? '친구' : '전체',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final category in RankingCategory.values)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _category = category),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _category == category
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFFE5E8EB),
                        width: _category == category ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    category.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      color: _category == category
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF8B95A1),
                      fontWeight: _category == category
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      AccountQueryPanel<WeeklyRanking>(
        key: ValueKey((_category, _audience)),
        source: widget.service,
        revision: widget.revision,
        load: () => widget.service is FilteredRankingService
            ? (widget.service as FilteredRankingService).loadRanking(
                _category,
                _audience,
              )
            : widget.service.load(),
        isCurrentOwner: () => widget.service.isCurrentOwner,
        errorMessage: '랭킹을 불러오지 못했습니다.',
        builder: (context, ranking) {
          if (!ranking.canInteract) {
            return const Text('이메일 인증과 닉네임 등록 후 랭킹을 확인할 수 있습니다.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ranking.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('아직 표시할 기록이 없습니다.'),
                ),
              for (final runner in ranking.entries)
                SizedBox(height: 64, child: RankRow(runner: runner)),
            ],
          );
        },
      ),
    ],
  );
}
