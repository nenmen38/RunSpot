import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';

String formatChatTime(DateTime time, bool use24Hours) {
  final minutes = time.minute.toString().padLeft(2, '0');
  if (use24Hours) return '${time.hour.toString().padLeft(2, '0')}:$minutes';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour < 12 ? '오전' : '오후';
  return '$period $hour:$minutes';
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({required this.nickname, this.size = 38, super.key});

  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = nickname.trim().characters;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.blueSoft,
        foregroundColor: AppColors.blueDark,
        child: Text(
          initials.isEmpty ? '?' : initials.first,
          style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
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
    super.key,
  });

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
    final foreground = mine ? Colors.white : theme.colorScheme.onSurface;
    const corner = Radius.circular(18);
    const groupedCorner = Radius.circular(6);

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
                          child: ChatAvatar(nickname: nickname, size: 32),
                        )
                      : null,
                ),
              Flexible(
                child: Column(
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: mine
                            ? AppColors.blueDark
                            : theme.colorScheme.surface,
                        border: mine
                            ? null
                            : Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                        borderRadius: BorderRadius.only(
                          topLeft: mine ? corner : groupedCorner,
                          topRight: mine ? groupedCorner : corner,
                          bottomLeft: corner,
                          bottomRight: corner,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: SelectableText(
                          body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            height: 1.45,
                          ),
                        ),
                      ),
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
    super.key,
  });

  final TextEditingController controller;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;

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
            Expanded(
              child: TextField(
                controller: controller,
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
