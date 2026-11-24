import 'package:flutter/material.dart';

import '../search_history.dart';
import '../theme/app_colors.dart';

/// 네이버 검색창의 최근 검색어 목록과 같은 모양입니다.
/// 제목·전체 삭제 / 시계 아이콘·검색어·날짜·지우기 / 맨 아래 자동저장 끄기·켜기.
class RecentSearches extends StatelessWidget {
  const RecentSearches({
    required this.history,
    required this.onSearch,
    super.key,
  });

  final SearchHistory history;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    if (!history.loaded) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final gray = TextStyle(color: AppColors.gray, fontSize: 13);
    final items = history.enabled ? history.items : const <SearchHistoryItem>[];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '최근 검색어',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gray,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('전체 삭제'),
                ),
            ],
          ),
          if (!history.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '검색어 저장 기능이 꺼져 있습니다.',
                textAlign: TextAlign.center,
                style: gray,
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '최근 검색어 내역이 없습니다.',
                textAlign: TextAlign.center,
                style: gray,
              ),
            )
          else
            for (final item in items)
              InkWell(
                key: ValueKey('recent-${item.query}'),
                onTap: () => onSearch(item.query),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 18, color: AppColors.gray),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                      Text(
                        '${item.at.month.toString().padLeft(2, '0')}.'
                        '${item.at.day.toString().padLeft(2, '0')}.',
                        style: gray.copyWith(fontSize: 12),
                      ),
                      IconButton(
                        tooltip: '${item.query} 검색어 삭제',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => history.remove(item.query),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          Divider(height: 20, color: AppColors.line),
          // 맨 아래 줄: 왼쪽 자동저장 끄기/켜기.
          Row(
            children: [
              TextButton(
                key: const ValueKey('recent-toggle'),
                onPressed: () => history.setEnabled(!history.enabled),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gray,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(history.enabled ? '자동저장 끄기' : '자동저장 켜기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최근 검색어 전체 삭제'),
        content: const Text('최근 검색어를 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) await history.clear();
  }
}
