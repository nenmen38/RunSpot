import 'package:flutter/material.dart';

class BoardReportDialog extends StatefulWidget {
  const BoardReportDialog({super.key});
  @override
  State<BoardReportDialog> createState() => _BoardReportDialogState();
}

class _BoardReportDialogState extends State<BoardReportDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('게시글 신고'),
    content: TextField(
      controller: _reason,
      minLines: 3,
      maxLines: 5,
      maxLength: 500,
      decoration: const InputDecoration(hintText: '신고 사유를 입력해 주세요.'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('신고'),
      ),
    ],
  );
}
