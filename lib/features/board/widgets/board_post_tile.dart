import 'package:runquest/features/titles/badge_directory.dart';
import 'package:runquest/features/profile/avatar_directory.dart';
import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../models/board_post.dart';
import 'board_photo.dart';
import 'board_theme.dart';

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

TextStyle get _metaStyle => TextStyle(
  color: BoardStyle.secondary,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  height: 1.5,
);

/// 작성자 이름 옆에 붙이는 크루 아이콘과 크루 이름입니다.
class BoardCrewBadge extends StatelessWidget {
  const BoardCrewBadge({required this.crew, super.key});

  final BoardCrew crew;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(crew.icon.icon, size: 14, color: crew.icon.color),
        const SizedBox(width: 2),
        Text(
          crew.name,
          style: TextStyle(
            color: BoardStyle.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// 말머리마다 다른 색을 써서 목록에서 한눈에 구분되게 합니다.
({Color background, Color foreground}) boardTopicColors(BoardTopic topic) {
  final dark = AppColors.dark;
  Color soft(Color color) => color.withValues(alpha: dark ? .22 : .12);
  final color = switch (topic) {
    BoardTopic.course => const Color(0xFF12A37A),
    BoardTopic.tip => AppColors.blue,
    BoardTopic.food => const Color(0xFFF2780C),
    BoardTopic.free => const Color(0xFF7C5CFF),
    BoardTopic.question => const Color(0xFFE0447C),
  };
  return (
    background: soft(color),
    // 어두운 화면에서는 글자를 조금 밝게 해 읽히게 합니다.
    foreground: dark ? Color.lerp(color, Colors.white, .35)! : color,
  );
}

class BoardPostTile extends StatelessWidget {
  const BoardPostTile({
    required this.post,
    required this.onTap,
    this.onAuthorTap,
    super.key,
  });

  final BoardPost post;
  final VoidCallback onTap;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final raceDate = post.raceDate;
    final photos = post.visibleImageUrls;
    final topic = post.topic;
    final preview = (post.racePlace ?? post.body).replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: BoardStyle.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (raceDate != null) ...[
                      _RaceDate(date: raceDate),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (topic != null) ...[
                            BoardTopicChip(topic: topic),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            post.title,
                            maxLines:
                                MediaQuery.textScalerOf(context).scale(16) > 22
                                ? null
                                : 2,
                            overflow: TextOverflow.ellipsis,
                            style: BoardStyle.section.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if (preview.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: BoardStyle.meta.copyWith(
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      ExcludeSemantics(
                        child: Stack(
                          children: [
                            BoardPhoto(url: photos.first, size: 72),
                            // 사진이 여러 장이면 몇 장 더 있는지 붙입니다.
                            if (photos.length > 1)
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+${photos.length - 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: post.isMine ? null : onAuthorTap,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            BoardAuthorAvatar(
                              nickname: post.nickname,
                              postId: post.id,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: ListenableBuilder(
                                listenable: BadgeDirectory.instance,
                                builder: (context, _) => Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: post.nickname,
                                        style: TextStyle(
                                          color: BoardStyle.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      // 칭호가 있을 때만 이름 옆에 붙입니다.
                                      if (BadgeDirectory.instance
                                              .post(post.id)
                                              ?.title !=
                                          null)
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: PostAuthorTitle(
                                            postId: post.id,
                                          ),
                                        ),
                                      if (post.crew case final crew?)
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: BoardCrewBadge(crew: crew),
                                        ),
                                      TextSpan(
                                        text:
                                            ' · ${formatBoardDateTime(post.createdAt)}',
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _metaStyle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (post.likeCount > 0)
                      _Count(
                        icon: post.liked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: post.liked ? AppColors.red : null,
                        count: post.likeCount,
                        label: '좋아요',
                      ),
                    if (post.commentCount > 0)
                      _Count(
                        icon: Icons.chat_bubble_outline,
                        count: post.commentCount,
                        label: '댓글',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BoardTopicChip extends StatelessWidget {
  const BoardTopicChip({required this.topic, super.key});

  final BoardTopic topic;

  @override
  Widget build(BuildContext context) {
    final colors = boardTopicColors(topic);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        topic.label,
        style: TextStyle(
          color: colors.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 대회 날짜 달력 칸입니다. 일주일 안으로 다가오면 D-day를 빨간색으로 강조합니다.
class _RaceDate extends StatelessWidget {
  const _RaceDate({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final countdown = raceCountdown(date);
    final now = DateTime.now();
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final soon = days >= 0 && days <= 7;
    return Container(
      width: 60,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: BoardStyle.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 3),
            color: soon ? AppColors.red : BoardStyle.accent,
            child: Text(
              '${date.month}월',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: BoardStyle.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  countdown,
                  style: TextStyle(
                    color: soon ? AppColors.red : BoardStyle.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 글쓴이 닉네임 첫 글자가 든 작은 동그라미입니다.
class BoardAuthorAvatar extends StatelessWidget {
  const BoardAuthorAvatar({
    required this.nickname,
    this.postId,
    this.commentId,
    this.size = 20,
    super.key,
  });

  final String nickname;

  /// 글쓴이 사진은 글 ID로, 댓글 작성자 사진은 댓글 ID로 찾습니다(게시판은 사용자 ID를 주지 않습니다).
  final String? postId;
  final String? commentId;
  final double size;

  @override
  Widget build(BuildContext context) => UserAvatar(
    nickname: nickname,
    postId: postId,
    commentId: commentId,
    size: size,
  );
}

class _Count extends StatelessWidget {
  const _Count({
    required this.icon,
    required this.count,
    required this.label,
    this.color,
  });

  final IconData icon;
  final int count;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $count개',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color ?? BoardStyle.secondary),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: _metaStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}
