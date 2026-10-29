import 'package:flutter/material.dart';

import 'board_theme.dart';

class BoardReportDialog extends StatefulWidget {
  const BoardReportDialog({this.isComment = false, super.key});
  final bool isComment;
  @override
  State<BoardReportDialog> createState() => _BoardReportDialogState();
}

class _BoardReportDialogState extends State<BoardReportDialog> {
  static const _categories = ['욕설·비방', '스팸·광고', '음란·불법 콘텐츠', '개인정보 노출', '기타'];
  final _reason = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BoardTheme(
    child: AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(widget.isComment ? '댓글 신고' : '게시글 신고'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final category in _categories)
                  ChoiceChip(
                    label: Text(category),
                    selectedColor: BoardStyle.accentSoft,
                    backgroundColor: BoardStyle.surface,
                    labelStyle: TextStyle(
                      color: _category == category
                          ? BoardStyle.accent
                          : BoardStyle.ink,
                    ),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 450,
              decoration: InputDecoration(
                hintText: _category == '기타' ? '신고 사유를 입력해 주세요.' : '추가 설명 (선택)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: BoardStyle.accent,
            foregroundColor: Colors.white,
          ),
          onPressed:
              _category == null ||
                  (_category == '기타' && _reason.text.trim().isEmpty)
              ? null
              : () => Navigator.pop(
                  context,
                  '$_category${_reason.text.trim().isEmpty ? '' : '\n${_reason.text.trim()}'}',
                ),
          child: const Text('신고'),
        ),
      ],
    ),
  );
}
