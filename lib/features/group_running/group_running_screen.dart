import 'package:flutter/material.dart';

import '../social/friend_controller.dart';
import 'group_controller.dart';
import 'models/running_group.dart';

class GroupRunningScreen extends StatelessWidget {
  const GroupRunningScreen({
    required this.controller,
    required this.friends,
    super.key,
  });
  final GroupController controller;
  final FriendController friends;

  Future<void> _accept(BuildContext context, RunningGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('함께 달리기 참여'),
        content: const Text(
          '참여자에게 닉네임과 완료 거리·시간이 공유됩니다. 경로와 현재 위치는 공유하지 않습니다. GPS 준비 후 방장이 출발을 예약하면 앱이 열린 상태에서 자동으로 러닝을 시작합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('동의하고 참여'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.change('accept', groupId: group.id);
  }

  Future<void> _invite(BuildContext context, RunningGroup group) async {
    await friends.refresh();
    if (!context.mounted || !controller.service.isCurrentOwner) return;
    final candidates = friends.friends
        .where(
          (friend) =>
              !group.members.any((member) => member.userId == friend.userId),
        )
        .toList();
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('초대할 친구')),
            if (candidates.isEmpty)
              const ListTile(title: Text('초대할 수 있는 친구가 없습니다.')),
            for (final friend in candidates)
              ListTile(
                title: Text(friend.nickname),
                onTap: () => Navigator.pop(context, friend.userId),
              ),
          ],
        ),
      ),
    );
    if (target != null) {
      await controller.change('invite', groupId: group.id, targetId: target);
    }
  }

  String _state(String state) => switch (state) {
    'lobby' => '참여 대기',
    'scheduled' => '출발 예약',
    'running' => '러닝 중',
    'finished' => '그룹 완료',
    'cancelled' => '그룹 취소',
    'expired' => '만료',
    _ => '상태 확인 필요',
  };
  String _memberState(String status) => switch (status) {
    'invited' => '초대 대기',
    'accepted' => '참여',
    'declined' => '거절',
    'cancelled' => '초대 취소',
    'left' => '나감',
    'finished' => '완료',
    _ => '확인 필요',
  };

  Widget _group(BuildContext context, RunningGroup group) {
    final host = group.hostId == controller.service.ownerId;
    final seconds = controller.secondsUntil(group);
    final prepared = controller.preparedGroupId == group.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${host ? '내 그룹' : '함께 달리기'} · ${_state(group.state)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (group.state == 'scheduled' && seconds != null)
              Text(
                '${seconds.clamp(0, 10)}초 뒤 공동 출발',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            for (final member in group.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${member.nickname}${member.userId == group.hostId ? ' · 방장' : ''}',
                ),
                subtitle: Text(
                  member.distance != null
                      ? '${(member.distance! / 1000).toStringAsFixed(2)}km · ${member.seconds}초'
                      : '${_memberState(member.status)}${member.ready ? ' · GPS 준비 완료' : ''}',
                ),
                trailing:
                    host && group.state == 'lobby' && member.status == 'invited'
                    ? IconButton(
                        tooltip: '초대 취소',
                        onPressed: controller.busy
                            ? null
                            : () => controller.change(
                                'cancel_invite',
                                groupId: group.id,
                                targetId: member.userId,
                              ),
                        icon: const Icon(Icons.close),
                      )
                    : null,
              ),
            if (group.myStatus == 'invited' && group.state == 'lobby')
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: controller.busy
                        ? null
                        : () => _accept(context, group),
                    child: const Text('초대 수락'),
                  ),
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => controller.change('reject', groupId: group.id),
                    child: const Text('거절'),
                  ),
                ],
              ),
            if (group.myStatus == 'accepted' && group.state == 'lobby') ...[
              const Text('출발 전 GPS를 준비하고 앱을 열어 두세요. 준비 중에도 위치는 그룹에 전송하지 않습니다.'),
              if (host) const Text('그룹을 만들면 참여자에게 닉네임과 완료 거리·시간을 공유합니다.'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: controller.busy || prepared
                        ? null
                        : () => controller.prepare(group.id),
                    child: Text(prepared ? 'GPS 준비됨' : 'GPS 준비'),
                  ),
                  if (host)
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => _invite(context, group),
                      child: const Text('친구 초대'),
                    ),
                  if (host)
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.change('start', groupId: group.id),
                      child: const Text('10초 뒤 출발'),
                    ),
                ],
              ),
            ],
            if (group.myStatus == 'accepted' &&
                (group.state == 'running' || group.state == 'scheduled'))
              Text(
                controller.map.runSession?.isRunning == true
                    ? '개인 측정 중입니다. 홈에서 일시 정지하거나 종료하세요.'
                    : prepared
                    ? '공동 출발을 기다리고 있습니다.'
                    : '공동 출발을 놓쳤거나 GPS 준비가 해제되었습니다. 개인 러닝을 시작하거나 새 그룹에 참여하세요.',
              ),
            if (group.myStatus == 'accepted' && group.active)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => controller.change(
                          host ? 'cancel' : 'leave',
                          groupId: group.id,
                        ),
                  child: Text(host ? '그룹 취소' : '그룹 나가기'),
                ),
              ),
            if (group.state == 'cancelled')
              const Text('개인 러닝 측정과 저장은 홈에서 계속할 수 있습니다.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('함께 달리기')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => !controller.service.isCurrentOwner
          ? const Center(child: Text('다시 로그인해 주세요.'))
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '친구와 최대 8명이 함께 출발하고 각자의 완료 기록을 비교합니다. 최근 그룹 20개를 표시합니다.',
                  ),
                  FilledButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => controller.change('create'),
                    icon: const Icon(Icons.group_add),
                    label: const Text('그룹 만들기'),
                  ),
                  if (controller.busy || controller.loading)
                    const LinearProgressIndicator(),
                  if (controller.error != null)
                    Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (controller.groups.isEmpty && !controller.loading)
                    const Text('참여 중이거나 초대받은 그룹이 없습니다.'),
                  for (final group in controller.groups) _group(context, group),
                ],
              ),
            ),
    ),
  );
}
