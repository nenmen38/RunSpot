import 'package:flutter/material.dart';

import '../data/block_service.dart';

Future<bool> confirmUserBlock(
  BuildContext context, {
  required BlockService service,
  required String userId,
  required String nickname,
  bool blocked = false,
  VoidCallback? onConfirmed,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(blocked ? '차단 해제' : '사용자 차단'),
      content: Text(
        blocked
            ? '$nickname님의 차단을 해제할까요? 친구 관계는 복원되지 않습니다.'
            : '$nickname님을 차단할까요? 친구 관계와 대기 요청을 삭제하고 서로 위치와 랭킹을 볼 수 없게 됩니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(blocked ? '해제' : '차단'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted || !service.isCurrentOwner) {
    return false;
  }
  onConfirmed?.call();
  try {
    await service.change(userId, blocked: !blocked);
    return context.mounted && service.isCurrentOwner;
  } catch (_) {
    if (context.mounted && service.isCurrentOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단 설정을 변경하지 못했습니다. 다시 시도해 주세요.')),
      );
    }
    return false;
  }
}

class BlockButton extends StatefulWidget {
  const BlockButton({
    required this.service,
    required this.userId,
    required this.nickname,
    this.blocked = false,
    this.onChanged,
    super.key,
  });
  final BlockService service;
  final String userId;
  final String nickname;
  final bool blocked;
  final VoidCallback? onChanged;

  @override
  State<BlockButton> createState() => _BlockButtonState();
}

class _BlockButtonState extends State<BlockButton> {
  bool _busy = false;
  bool _confirming = false;

  Future<void> _change() async {
    final service = widget.service;
    if (_busy || _confirming) return;
    setState(() => _confirming = true);
    try {
      final changed = await confirmUserBlock(
        context,
        service: service,
        userId: widget.userId,
        nickname: widget.nickname,
        blocked: widget.blocked,
        onConfirmed: () {
          if (mounted) setState(() => _busy = true);
        },
      );
      if (mounted && changed) widget.onChanged?.call();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.blocked ? '차단 해제' : '사용자 차단',
    onPressed: _busy || _confirming || !widget.service.isCurrentOwner
        ? null
        : _change,
    icon: _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.blocked ? Icons.lock_open : Icons.block),
  );
}
