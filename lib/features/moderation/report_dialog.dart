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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(12);
    final outline = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final field = InputDecoration(
      filled: true,
      fillColor: colors.surface,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
    final needsDetail = _category == '기타';
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsOverflowButtonSpacing: 8,
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.preview != null) ...[
              Center(
                child: ClipRRect(borderRadius: radius, child: widget.preview!),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.explanation != null) ...[
              Text(widget.explanation!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
            ],
            Text('신고 분류', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: field,
              hint: const Text('분류 선택'),
              icon: const Icon(Icons.expand_more_rounded),
              borderRadius: radius,
              dropdownColor: colors.surface,
              elevation: 3,
              isExpanded: true,
              items: [
                for (final category in reportCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: 20),
            Text(
              needsDetail ? '상세 설명 (필수)' : '상세 설명 (선택)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 450,
              decoration: field.copyWith(hintText: '신고 사유를 입력해 주세요.'),
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
              _category == null || (needsDetail && _reason.text.trim().isEmpty)
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
}
