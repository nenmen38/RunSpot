import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'models/run_feedback_heart_summary.dart';

/// 취소는 null, 동의는 심박 포함 여부를 반환합니다. 심박 전송은 매번 기본 해제합니다.
Future<bool?> showFeedbackConsent(
  BuildContext context, {
  RunFeedbackHeartSummary? heartSummary,
}) {
  var includeHeart = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('피드백을 생성할까요?'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heartSummary != null) ...[
                  Material(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '심박도 함께 분석',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '평균·최대·구간별 심박 요약을 뜀터 서버와 Google Gemini에 전송하는 데 동의합니다.',
                        style: TextStyle(fontSize: 12, color: AppColors.gray),
                      ),
                      value: includeHeart,
                      onChanged: (value) =>
                          setState(() => includeHeart = value == true),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '심박 요약은 이번 피드백 생성에 사용합니다. 생성된 피드백은 내 러닝 기록에 저장됩니다. 선택하지 않아도 기본 피드백을 받을 수 있습니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.gray),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  '72시간마다 1회 · 생성 실패 시에도 적용',
                  style: TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, includeHeart),
            child: const Text('생성하기'),
          ),
        ],
      ),
    ),
  );
}
