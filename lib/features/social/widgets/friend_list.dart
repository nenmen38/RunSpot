import 'package:flutter/material.dart';

import '../../crew/crew_controller.dart';
import '../../crew/models/crew.dart';
import '../../crew/widgets/crew_widgets.dart';
import '../friend_controller.dart';
import '../friend_profile_screen.dart';
import '../data/block_service.dart';
import 'block_button.dart';
import 'user_interaction_sheet.dart';
import '../models/friend_entry.dart';

class FriendList extends StatefulWidget {
  const FriendList({
    required this.controller,
    required this.requests,
    this.blockService,
    this.crew,
    this.onRunInvite,
    super.key,
  });
  final FriendController controller;
  final bool requests;
  final ValueChanged<FriendEntry>? onRunInvite;
  final BlockService? blockService;

  /// 크루장에게만 친구 옆에 "크루원 초대하기" 버튼을 보여줍니다.
  final CrewController? crew;

  @override
  State<FriendList> createState() => _FriendListState();
}

class _FriendListState extends State<FriendList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crew = widget.crew;
    if (crew == null) return _list(context);
    return ListenableBuilder(
      listenable: crew,
      builder: (context, _) => _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final controller = widget.controller;
    final crew = widget.crew;
    final query = _search.text.trim().toLowerCase();
    final friends = query.isEmpty
        ? controller.friends
        : controller.friends
              .where((entry) => entry.nickname.toLowerCase().contains(query))
              .toList();
    final received = controller.received;
    final sent = controller.sent;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.requests) ...[
            _Heading('받은 요청', received.length),
            if (received.isEmpty) const _Empty('받은 요청이 없습니다.'),
            for (final entry in received)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: widget.blockService,
              ),
            const Divider(height: 24),
            _Heading('보낸 요청', sent.length),
            if (sent.isEmpty) const _Empty('보낸 요청이 없습니다.'),
            for (final entry in sent)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: widget.blockService,
              ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: _search,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '친구 목록 검색',
                  hintText: '닉네임 입력',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '친구 목록 검색어 지우기',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            _Heading(query.isEmpty ? '내 친구' : '검색 결과', friends.length),
            if (friends.isEmpty && controller.loaded)
              _Empty(query.isEmpty ? '아직 친구가 없습니다.' : '일치하는 친구가 없습니다.'),
            for (final entry in friends)
              FriendRow(
                entry: entry,
                controller: controller,
                blockService: widget.blockService,
                crew: crew,
                onProfileTap: () async {
                  FocusScope.of(context).unfocus();
                  void openProfile() => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => FriendProfileScreen(
                        friend: entry,
                        service: controller.service,
                      ),
                    ),
                  );
                  final blocks = widget.blockService;
                  if (blocks == null) {
                    openProfile();
                    return;
                  }
                  final blocked = await showUserInteraction(
                    context,
                    userId: entry.userId,
                    nickname: entry.nickname,
                    blocks: blocks,
                    friends: controller.service,
                    knownFriend: entry,
                    onProfile: openProfile,
                    onRunInvite: widget.onRunInvite == null
                        ? null
                        : () => widget.onRunInvite!(entry),
                  );
                  if (blocked && mounted) await controller.refresh();
                },
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
    this.onProfileTap,
    this.crew,
    super.key,
  });
  final FriendEntry entry;
  final FriendController controller;
  final BlockService? blockService;
  final VoidCallback? onProfileTap;

  /// 크루장이면 친구 메뉴(…)에 "크루원 초대하기"를 넣습니다.
  final CrewController? crew;

  /// 초대할 크루를 고릅니다. 내가 크루장인 크루가 하나면 바로 그 크루로 초대합니다.
  Future<void> _inviteToCrew(BuildContext context) async {
    final crew = this.crew!;
    final targets = crew
        .inviteTargets(entry.userId)
        .where((item) => !item.pending.contains(entry.userId))
        .toList();
    if (targets.isEmpty) return;
    final chosen = targets.length == 1
        ? targets.single
        : await showDialog<Crew>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text('${entry.nickname}님을 초대할 크루'),
              children: [
                for (final item in targets)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, item),
                    child: Row(
                      children: [
                        CrewBadge(icon: item.icon, size: 32),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item.name)),
                      ],
                    ),
                  ),
              ],
            ),
          );
    if (chosen == null || !context.mounted) return;
    final error = await crew.invite(entry.userId, chosen.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? '${entry.nickname}님에게 ${chosen.name} 크루 초대를 보냈어요.',
          ),
        ),
      );
  }

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
          Expanded(
            child: InkWell(
              onTap: onProfileTap,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
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
                    if (onProfileTap != null)
                      const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
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
              FriendRelation.friend => const SizedBox.shrink(),
            },
          if (entry.relation == FriendRelation.friend || blockService != null)
            PopupMenuButton<String>(
              tooltip: entry.relation == FriendRelation.friend
                  ? '친구 관리'
                  : '사용자 메뉴',
              enabled: enabled,
              onSelected: (value) async {
                if (value == 'crew') {
                  await _inviteToCrew(context);
                } else if (value == 'remove') {
                  await _confirmRemoval(context);
                } else if (blockService != null) {
                  final changed = await confirmUserBlock(
                    context,
                    service: blockService!,
                    userId: entry.userId,
                    nickname: entry.nickname,
                  );
                  if (changed) {
                    controller.queryChanged('');
                    await controller.refresh();
                  }
                }
              },
              itemBuilder: (_) => [
                // 크루장에게만, 아직 그 크루에 없는 친구에게만 보입니다.
                if (entry.relation == FriendRelation.friend &&
                    crew != null &&
                    crew!.inviteTargets(entry.userId).isNotEmpty)
                  PopupMenuItem(
                    value: 'crew',
                    enabled:
                        crew!.busy == null &&
                        !crew!.invitedEverywhere(entry.userId),
                    child: Text(
                      crew!.invitedEverywhere(entry.userId)
                          ? '크루 초대함'
                          : '크루원 초대하기',
                    ),
                  ),
                if (entry.relation == FriendRelation.friend)
                  const PopupMenuItem(value: 'remove', child: Text('친구 삭제')),
                if (blockService != null)
                  const PopupMenuItem(value: 'block', child: Text('사용자 차단')),
              ],
            ),
        ],
      ),
    );
  }
}
