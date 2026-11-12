import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'chat_room_style.dart';

class ChatConversationTile extends StatelessWidget {
  const ChatConversationTile({
    required this.nickname,
    required this.preview,
    required this.sentAt,
    required this.onTap,
    super.key,
  });

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
                        Expanded(
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.blueSoft,
              foregroundColor: AppColors.blueDark,
              child: Icon(
                onRetry == null
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.sync_problem_rounded,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
