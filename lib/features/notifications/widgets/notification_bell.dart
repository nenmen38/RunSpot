import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../../board/widgets/board_post_tile.dart';
import '../models/app_notification.dart';
import '../notification_controller.dart';

/// 홈 화면 오른쪽 위의 확성기 버튼입니다. 누를 때만 알림창을 엽니다.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    required this.controller,
    required this.onOpenPost,
    super.key,
  });

  final NotificationController controller;
  final void Function(String postId) onOpenPost;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final count = controller.unreadCount;
      return IconButton.filled(
        tooltip: count == 0 ? '알림' : '알림 $count개',
        onPressed: () => showNotificationSheet(context, controller, onOpenPost),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
        ),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.campaign_outlined),
        ),
      );
    },
  );
}

Future<void> showNotificationSheet(
  BuildContext context,
  NotificationController controller,
  void Function(String) onOpenPost,
) async {
  unawaited(controller.open());
  final postId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NotificationSheet(controller: controller),
  );
  if (context.mounted && postId != null) onOpenPost(postId);
}

/// 푸시 권한과 관계없이 홈에 대기 중인 초대 내용을 표시합니다.
class GroupInviteBanner extends StatelessWidget {
  const GroupInviteBanner({
    required this.controller,
    required this.onOpenPost,
    super.key,
  });
  final NotificationController controller;
  final void Function(String) onOpenPost;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.service.isCurrentOwner ||
          controller.pendingInvites.isEmpty) {
        return const SizedBox.shrink();
      }
      final invite = controller.pendingInvites.first;
      return Material(
        color: AppColors.blueSoft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.directions_run, color: AppColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  invite.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () =>
                    showNotificationSheet(context, controller, onOpenPost),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 알림 목록입니다. 알림을 누르면 그 글 ID를 돌려주며 창을 닫습니다.
/// 목록은 확성기 버튼이 창을 열면서 불러옵니다.
class NotificationSheet extends StatelessWidget {
  const NotificationSheet({required this.controller, super.key});

  final NotificationController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '알림',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          controller.items.isEmpty ||
                              controller.loading ||
                              controller.clearing ||
                              controller.responding != null
                          ? null
                          : () => _clearAll(context),
                      child: const Text('모두 지우기'),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _clearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림 모두 지우기'),
        content: const Text('받은 알림을 모두 지울까요? 지운 알림은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('모두 지우기'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.clearAll();
  }

  Widget _body() {
    if (controller.loading && controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.error!, textAlign: TextAlign.center),
            TextButton(onPressed: controller.open, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (controller.items.isEmpty) {
      return const Center(
        child: Text(
          '아직 알림이 없어요.\n내 글 반응이나 함께 달리기 초대가 오면 알려 드릴게요.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.respondError case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(message, style: const TextStyle(color: AppColors.red)),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: controller.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _NotificationTile(
              item: controller.items[index],
              controller: controller,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.controller});

  final AppNotification item;
  final NotificationController controller;

  @override
  Widget build(BuildContext context) {
    final invite = item.isInvite;
    final busy = controller.loading || controller.responding != null;
    return ListTile(
      tileColor: item.read ? null : AppColors.blueSoft,
      leading: Icon(
        switch (item.kind) {
          NotificationKind.like => Icons.favorite,
          NotificationKind.groupInvite => Icons.directions_run,
          NotificationKind.crewInvite => Icons.groups,
          _ => Icons.chat_bubble_outline,
        },
        color: item.kind == NotificationKind.like
            ? Colors.redAccent
            : AppColors.blue,
      ),
      title: Text(item.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.detail} · ${formatBoardTime(item.createdAt.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 대기 중인 초대는 알림창에서 바로 수락하거나 거절합니다.
          if (invite && item.canRespond)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => controller.respond(item, accept: false),
                    child: const Text('거절'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => controller.respond(item, accept: true),
                    child: controller.responding == item.id
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('수락'),
                  ),
                ],
              ),
            ),
        ],
      ),
      onTap: item.postId == null
          ? null
          : () => Navigator.of(context).pop(item.postId),
    );
  }
}
