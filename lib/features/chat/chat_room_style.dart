import '../monetization/cosmetics.dart';
import '../profile/avatar_directory.dart';

import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'swipe_to_reply.dart';

String formatChatTime(DateTime time, bool use24Hours) {
  final minutes = time.minute.toString().padLeft(2, '0');
  if (use24Hours) return '${time.hour.toString().padLeft(2, '0')}:$minutes';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour < 12 ? '오전' : '오후';
  return '$period $hour:$minutes';
}

/// 대화에 쓰는 동그란 얼굴입니다. [userId]가 있으면 프로필 사진을, 없으면 닉네임 첫 글자를 보여줍니다.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    required this.nickname,
    this.userId,
    this.size = 38,
    super.key,
  });

  final String nickname;
  final String? userId;
  final double size;

  @override
  Widget build(BuildContext context) =>
      UserAvatar(nickname: nickname, userId: userId, size: size);
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.body,
    required this.nickname,
    required this.mine,
    required this.showAvatar,
    required this.showTime,
    required this.sentAt,
    required this.showDay,
    this.unread = false,
    this.unreadCount,
    this.showName = false,
    this.replyPreview,
    this.content,
    this.onLongPress,
    this.onReply,
    this.bubble,
    this.senderId,
    super.key,
  });

  /// 보낸 사람 ID입니다. 있으면 말풍선 옆 얼굴에 프로필 사진을 보여줍니다.
  final String? senderId;

  /// 보낸 사람이 착용한 말풍선 아이템입니다. 있으면 그 색으로 그립니다.
  final CosmeticItem? bubble;

  /// 내가 보낸 메시지를 상대가 아직 읽지 않았으면 true입니다.
  final bool unread;

  /// 단톡에서 이 메시지를 아직 안 읽은 사람 수입니다. 있으면 [unread] 대신 씁니다.
  final int? unreadCount;

  /// 다른 사람 말풍선 위에 이름을 보여줄지 여부입니다(단톡).
  final bool showName;
  final String? replyPreview;
  final Widget? content;
  final VoidCallback? onLongPress;
  final VoidCallback? onReply;

  final String body;
  final String nickname;
  final bool mine;
  final bool showAvatar;
  final bool showTime;
  final DateTime? sentAt;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = sentAt;
    // 안 읽은 사람 수입니다. 단톡은 숫자를, 1:1은 내 메시지에만 '1'을 붙입니다.
    final unreadLabel = (unreadCount ?? 0) > 0
        ? '$unreadCount'
        : unreadCount == null && mine && unread
        ? '1'
        : null;
    final themed = bubbleDecoration(bubble);
    final foreground = mine || themed != null
        ? Colors.white
        : theme.colorScheme.onSurface;
    const corner = Radius.circular(18);
    const groupedCorner = Radius.circular(6);

    final message = GestureDetector(
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: themed != null
              ? themed.color
              : mine
              ? AppColors.blueDark
              : theme.colorScheme.surface,
          gradient: themed?.gradient,
          border: mine || themed != null
              ? null
              : Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.only(
            topLeft: mine ? corner : groupedCorner,
            topRight: mine ? groupedCorner : corner,
            bottomLeft: corner,
            bottomRight: corner,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replyPreview case final preview?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '↪ $preview',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: .8),
                    ),
                  ),
                ),
              content ??
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      height: 1.45,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );

    return Column(
      children: [
        if (showDay && time != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Text(
                  '${time.year}년 ${time.month}월 ${time.day}일',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: showAvatar ? 8 : 3),
          child: Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                SizedBox(
                  width: 40,
                  child: showAvatar
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: ChatAvatar(
                            nickname: nickname,
                            userId: senderId,
                            size: 32,
                          ),
                        )
                      : null,
                ),
              Flexible(
                child: Column(
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // 단톡에서는 다른 사람 말풍선 위에 이름을 붙입니다.
                    if (showName && !mine && showAvatar)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 3),
                        child: Text(
                          nickname,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (mine && unreadLabel != null)
                          _UnreadMark(unreadLabel, right: true),
                        Flexible(
                          child: onReply == null
                              ? message
                              : SwipeToReply(
                                  onReply: onReply!,
                                  incoming: !mine,
                                  child: message,
                                ),
                        ),
                        if (!mine && unreadLabel != null)
                          _UnreadMark(unreadLabel, right: false),
                      ],
                    ),
                    if (showTime && time != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 5),
                        child: Text(
                          formatChatTime(
                            time,
                            MediaQuery.alwaysUse24HourFormatOf(context),
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (mine)
                const SizedBox(width: 12)
              else
                const SizedBox(width: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.sending,
    required this.canSend,
    required this.onSend,
    this.onAttach,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onAttach != null)
              IconButton(
                tooltip: '첨부',
                onPressed: canSend && !sending ? onAttach : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: '메시지 입력',
                  counterText: '',
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: shape,
                  enabledBorder: shape,
                  focusedBorder: shape.copyWith(
                    borderSide: const BorderSide(
                      color: AppColors.blueDark,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => IconButton.filled(
                tooltip: sending ? '보내는 중' : '보내기',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.blueDark,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: !sending && canSend && value.text.trim().isNotEmpty
                    ? onSend
                    : null,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카카오톡처럼 말풍선 옆에 붙는 안 읽은 사람 수입니다.
class _UnreadMark extends StatelessWidget {
  const _UnreadMark(this.label, {required this.right});

  final String label;
  final bool right;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      right: right ? 4 : 0,
      left: right ? 0 : 4,
      bottom: 2,
    ),
    child: Semantics(
      label: '$label명 읽지 않음',
      child: ExcludeSemantics(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.unreadMark,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}
