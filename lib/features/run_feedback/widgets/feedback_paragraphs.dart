import 'package:flutter/material.dart';

/// 원문은 유지하고 문장과 기존 줄바꿈을 기준으로 읽기 좋은 문단을 나눕니다.
class FeedbackParagraphs extends StatelessWidget {
  const FeedbackParagraphs({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
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
            style: const TextStyle(
              fontSize: 16,
              height: 1.7,
              color: Color(0xFF333D4B),
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
