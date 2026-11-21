import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../../../shared/formatters/run_format.dart';

/// 저장된 피드백의 페이스 표기를 통일하고 문장과 줄바꿈을 기준으로 문단을 나눕니다.
class FeedbackParagraphs extends StatelessWidget {
  const FeedbackParagraphs({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .replaceAllMapped(
          RegExp(
            r"""\b(\d{1,8})\s*(?:분|[:'’′])\s*([0-5]?\d)\s*(?:초|["”″])?\s*/\s*km\b""",
          ),
          (match) =>
              '${formatPaceDuration(Duration(minutes: int.parse(match[1]!), seconds: int.parse(match[2]!)))}/km',
        )
        .trim()
        .split(RegExp(r'(?<=[.!?。！？])\s+|\n+'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Text(
            paragraphs[i],
            style: TextStyle(
              fontSize: 16,
              height: 1.7,
              color: AppColors.ink,
              fontWeight: FontWeight.w500,
            ),
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),
        ],
      ],
    );
  }
}
