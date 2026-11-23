import 'package:flutter/material.dart';

const reportCategories = ['욕설·비방', '스팸·광고', '음란·불법 콘텐츠', '개인정보 노출', '기타'];

class ReportDialog extends StatefulWidget {
  const ReportDialog({
    required this.title,
    this.explanation,
    this.preview,
    super.key,
  });
  final String title;
  final String? explanation;
  final Widget? preview;
  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _reason = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.preview != null) Center(child: widget.preview!),
          if (widget.explanation != null) Text(widget.explanation!),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final category in reportCategories)
                ChoiceChip(
                  label: Text(category),
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
  );
}
