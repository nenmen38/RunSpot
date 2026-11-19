import '../titles/badge_directory.dart';

import 'package:runquest/shared/widgets/status_view.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'chat_room_style.dart';

class ChatConversationTile extends StatelessWidget {
  const ChatConversationTile({
    required this.nickname,
    this.peerId,
    required this.preview,
    required this.sentAt,
    required this.onTap,
    this.unread = 0,
    super.key,
  });

  /// 상대가 보냈지만 내가 아직 읽지 않은 메시지 수입니다.
  final int unread;

  /// 칭호를 보여줄 친구 ID입니다.
  final String? peerId;
  final String nickname;
  final String preview;
  final DateTime? sentAt;
  final VoidCallback onTap;

  String? _timestamp(BuildContext context) {
    final time = sentAt;
    if (time == null) return null;
    final now = DateTime.now();
    if (DateUtils.isSameDay(time, now)) {
      return formatChatTime(time, MediaQuery.alwaysUse24HourFormatOf(context));
    }
    if (DateUtils.isSameDay(time, DateTime(now.year, now.month, now.day - 1))) {
      return '어제';
    }
    return time.year == now.year
        ? '${time.month}월 ${time.day}일'
        : '${time.year}년 ${time.month}월 ${time.day}일';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = _timestamp(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
    );
    return Material(
      color: colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ChatAvatar(nickname: nickname, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (peerId case final id?) UserTitle(userId: id),
                        const Spacer(),
                        if (time != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (unread > 0)
                Semantics(
                  label: '안 읽은 메시지 $unread개',
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unread > 999 ? '999+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatListPlaceholder extends StatelessWidget {
  const ChatListPlaceholder({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => onRetry == null
      ? StatusView.empty(
          icon: Icons.chat_bubble_outline_rounded,
          message: message,
        )
      : StatusView.error(message: message, onRetry: onRetry);
}
