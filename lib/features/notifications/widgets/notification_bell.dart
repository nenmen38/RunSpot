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

  Future<void> _open(BuildContext context) async {
    unawaited(controller.open());
    final postId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NotificationSheet(controller: controller),
    );
    if (postId != null) onOpenPost(postId);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final count = controller.unreadCount;
      return IconButton.filled(
        tooltip: count == 0 ? '알림' : '알림 $count개',
        onPressed: () => _open(context),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '알림',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(child: _body()),
            ],
          );
        },
      ),
    ),
  );

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
          '아직 알림이 없어요.\n내 글에 좋아요나 댓글이 달리면 알려 드릴게요.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: controller.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _NotificationTile(item: controller.items[index]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) => ListTile(
    tileColor: item.read ? null : AppColors.blueSoft,
    leading: Icon(
      item.kind == NotificationKind.like
          ? Icons.favorite
          : Icons.chat_bubble_outline,
      color: item.kind == NotificationKind.like
          ? Colors.redAccent
          : AppColors.blue,
    ),
    title: Text(item.message, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${item.postTitle} · ${formatBoardTime(item.createdAt.toLocal())}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => Navigator.of(context).pop(item.postId),
  );
}
