import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/badge_pill.dart';

import '../models/board_post.dart';
import 'board_photo.dart';

String formatBoardTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.year}.${time.month}.${time.day}';
}

/// 게시글·댓글은 작성한 날짜와 시각을 그대로 보여줍니다.
String formatBoardDateTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}.${time.month}.${time.day} '
      '${two(time.hour)}:${two(time.minute)}';
}

String formatRaceDate(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.year}.${date.month}.${date.day} (${weekdays[date.weekday - 1]})';
}

/// 대회 날짜까지 남은 날을 D-day 형식으로 표시합니다.
String raceCountdown(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final days = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(today).inDays;
  return days == 0 ? 'D-DAY' : 'D-$days';
}

const _metaStyle = TextStyle(
  color: AppColors.gray,
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

class BoardPostTile extends StatelessWidget {
  const BoardPostTile({required this.post, required this.onTap, super.key});

  final BoardPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raceDate = post.raceDate;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (raceDate != null) ...[
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${raceDate.month}.${raceDate.day}',
                      style: const TextStyle(
                        color: AppColors.blueDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      raceCountdown(raceDate),
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.topic != null) ...[
                    BadgePill(text: post.topic!.label),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    post.racePlace ?? post.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${post.nickname} · ${formatBoardDateTime(post.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _metaStyle,
                        ),
                      ),
                      if (post.likeCount > 0) ...[
                        Icon(
                          post.liked ? Icons.favorite : Icons.favorite_border,
                          size: 13,
                          color: post.liked ? AppColors.red : AppColors.gray,
                        ),
                        const SizedBox(width: 2),
                        Text('${post.likeCount}', style: _metaStyle),
                        const SizedBox(width: 8),
                      ],
                      if (post.commentCount > 0) ...[
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 13,
                          color: AppColors.gray,
                        ),
                        const SizedBox(width: 2),
                        Text('${post.commentCount}', style: _metaStyle),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (post.visibleImageUrls.isNotEmpty) ...[
              const SizedBox(width: 10),
              BoardPhoto(url: post.visibleImageUrls.first, size: 64),
            ],
          ],
        ),
      ),
    );
  }
}
