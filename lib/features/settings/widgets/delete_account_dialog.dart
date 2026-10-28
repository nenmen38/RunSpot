import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 지워지는 자료를 안내하고 '탈퇴'를 직접 입력해야 진행합니다.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({required this.onDelete, super.key});

  final Future<void> Function() onDelete;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  static const _confirmWord = '탈퇴';
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete().timeout(const Duration(seconds: 30));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is PostgrestException && error.code == '42501'
            ? error.message
            : '탈퇴하지 못했습니다. 네트워크를 확인한 뒤 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('회원 탈퇴'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '탈퇴하면 계정과 프로필, 러닝 기록·경로, 친구, 업적·경험치, '
            '게시글·댓글·좋아요·사진이 모두 삭제되며 되돌릴 수 없어요.',
          ),
          const SizedBox(height: 12),
          const Text("계속하려면 아래에 '탈퇴'를 입력해 주세요."),
          TextField(
            controller: _input,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: _confirmWord),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('취소'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        onPressed: _busy || _input.text.trim() != _confirmWord ? null : _delete,
        child: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('탈퇴'),
      ),
    ],
  );
}
