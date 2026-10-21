import 'package:flutter/material.dart';

import '../friend_controller.dart';
import '../data/block_service.dart';
import 'block_button.dart';
import '../models/friend_entry.dart';

class FriendList extends StatelessWidget {
  const FriendList({
    required this.controller,
    required this.requests,
    this.blockService,
    super.key,
  });
  final FriendController controller;
  final bool requests;
  final BlockService? blockService;

  @override
  Widget build(BuildContext context) {
    final received = controller.received;
    final sent = controller.sent;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (requests) ...[
            _Heading('받은 요청', received.length),
            if (received.isEmpty) const _Empty('받은 요청이 없습니다.'),
            for (final entry in received)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: blockService,
              ),
            const Divider(height: 24),
            _Heading('보낸 요청', sent.length),
            if (sent.isEmpty) const _Empty('보낸 요청이 없습니다.'),
            for (final entry in sent)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: blockService,
              ),
          ] else ...[
            _Heading('내 친구', controller.friends.length),
            if (controller.friends.isEmpty && controller.loaded)
              const _Empty('아직 친구가 없습니다.'),
            for (final entry in controller.friends)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: blockService,
              ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text('$label $count', style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(label, textAlign: TextAlign.center),
  );
}

class FriendRow extends StatelessWidget {
  const FriendRow({
    required this.entry,
    required this.controller,
    this.blockService,
    super.key,
  });
  final FriendEntry entry;
  final FriendController controller;
  final BlockService? blockService;

  Future<void> _confirmRemoval(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('친구 삭제'),
        content: Text('${entry.nickname}님을 친구 목록에서 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.change(entry, FriendAction.remove);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = controller.busyUserId == null && !controller.loading;
    final busy = controller.busyUserId == entry.userId;
    return Padding(
      key: ValueKey('friend-${entry.userId}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            child: Icon(Icons.person_outline, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            switch (entry.relation) {
              FriendRelation.none => FilledButton.icon(
                onPressed: enabled && controller.canInteract
                    ? () => controller.change(entry, FriendAction.request)
                    : null,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('요청'),
              ),
              FriendRelation.sent => IconButton(
                onPressed: enabled
                    ? () => controller.change(entry, FriendAction.cancel)
                    : null,
                tooltip: '요청 취소',
                icon: const Icon(Icons.cancel_outlined),
              ),
              FriendRelation.received => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: enabled && controller.canInteract
                        ? () => controller.change(entry, FriendAction.accept)
                        : null,
                    tooltip: '요청 수락',
                    icon: const Icon(Icons.check),
                  ),
                  IconButton(
                    onPressed: enabled
                        ? () => controller.change(entry, FriendAction.reject)
                        : null,
                    tooltip: '요청 거절',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              FriendRelation.friend => IconButton(
                onPressed: enabled ? () => _confirmRemoval(context) : null,
                tooltip: '친구 삭제',
                icon: const Icon(Icons.person_remove_outlined),
              ),
            },
          if (blockService case final service?)
            BlockButton(
              service: service,
              userId: entry.userId,
              nickname: entry.nickname,
              onChanged: () {
                controller.queryChanged('');
                controller.refresh();
              },
            ),
        ],
      ),
    );
  }
}
