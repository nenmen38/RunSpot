import 'package:flutter/material.dart';

import '../../chat/friend_chat.dart';
import '../data/block_service.dart';
import '../data/friend_service.dart';
import '../models/friend_entry.dart';
import 'block_button.dart';

Future<bool> showUserInteraction(
  BuildContext context, {
  required String userId,
  required String nickname,
  required BlockService blocks,
  FriendService? friends,
  FriendEntry? knownFriend,
  VoidCallback? onRunInvite,
  VoidCallback? onProfile,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => _UserMenu(
        userId: userId,
        nickname: nickname,
        blocks: blocks,
        friends: friends,
        knownFriend: knownFriend,
        onRunInvite: onRunInvite,
        onProfile: onProfile,
      ),
    ) ??
    false;

class _UserMenu extends StatefulWidget {
  const _UserMenu({
    required this.userId,
    required this.nickname,
    required this.blocks,
    this.friends,
    this.knownFriend,
    this.onRunInvite,
    this.onProfile,
  });
  final String userId;
  final String nickname;
  final BlockService blocks;
  final FriendService? friends;
  final FriendEntry? knownFriend;
  final VoidCallback? onRunInvite;
  final VoidCallback? onProfile;
  @override
  State<_UserMenu> createState() => _UserMenuState();
}

class _UserMenuState extends State<_UserMenu> {
  FriendEntry? _friend;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _friend = widget.knownFriend;
    _load();
  }

  Future<void> _load() async {
    final service = widget.friends;
    if (service == null || !service.isCurrentOwner) return;
    try {
      final entries = await service.search(widget.nickname);
      if (mounted && service.isCurrentOwner) {
        setState(
          () => _friend = entries
              .where((e) => e.userId == widget.userId)
              .firstOrNull,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '친구 정보를 불러오지 못했습니다.');
    }
  }

  Future<void> _change(FriendAction action) async {
    final entry = _friend;
    if (entry == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.friends!.change(entry, action);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '요청을 처리하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friend = _friend;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(widget.nickname),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (widget.onProfile case final open?)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('프로필'),
                onTap: () {
                  Navigator.pop(context);
                  open();
                },
              ),
            if (friend?.relation == FriendRelation.friend) ...[
              if (widget.friends case final SupabaseFriendService service)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('대화'),
                  onTap: _busy
                      ? null
                      : () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          openFriendChat(
                            navigator.context,
                            service.client,
                            widget.userId,
                            widget.nickname,
                          );
                        },
                ),
              if (widget.onRunInvite case final invite?)
                ListTile(
                  leading: const Icon(Icons.directions_run),
                  title: const Text('함께 달리기'),
                  onTap: _busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          invite();
                        },
                ),
            ],
            if (friend != null) ...[
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text(switch (friend.relation) {
                  FriendRelation.none => '친구 요청',
                  FriendRelation.sent => '친구 요청 취소',
                  FriendRelation.received => '친구 요청 수락',
                  FriendRelation.friend => '친구 삭제',
                }),
                onTap: _busy
                    ? null
                    : () => _change(switch (friend.relation) {
                        FriendRelation.none => FriendAction.request,
                        FriendRelation.sent => FriendAction.cancel,
                        FriendRelation.received => FriendAction.accept,
                        FriendRelation.friend => FriendAction.remove,
                      }),
              ),
              if (friend.relation == FriendRelation.received)
                ListTile(
                  title: const Text('친구 요청 거절'),
                  onTap: _busy ? null : () => _change(FriendAction.reject),
                ),
            ],
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('사용자 차단'),
              onTap: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final changed = await confirmUserBlock(
                        context,
                        service: widget.blocks,
                        userId: widget.userId,
                        nickname: widget.nickname,
                      );
                      if (!context.mounted) return;
                      if (changed) {
                        Navigator.pop(context, true);
                      } else {
                        setState(() => _busy = false);
                      }
                    },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
