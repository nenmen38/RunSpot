import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../../run_history/models/run_record.dart';
import '../data/run_feedback_service.dart';
import 'feedback_paragraphs.dart';

/// 장식보다 피드백 본문과 실제 기록의 가독성에 집중합니다.
class RunFeedbackCard extends StatelessWidget {
  const RunFeedbackCard({
    required this.state,
    required this.description,
    required this.busy,
    required this.onRefresh,
    this.onGenerate,
    this.record,
    this.createdLabel,
    this.nextLabel,
    this.error,
    super.key,
  });

  final RunFeedbackState? state;
  final String description;
  final bool busy;
  final VoidCallback? onRefresh;
  final VoidCallback? onGenerate;
  final RunRecord? record;
  final String? createdLabel;
  final String? nextLabel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final status = state?.status;
    final ready = status == FeedbackStatus.ready;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '러닝 피드백',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: '피드백 상태 확인',
                onPressed: onRefresh,
                style: IconButton.styleFrom(foregroundColor: AppColors.gray),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 2),
            const Text(
              'AI 분석 완료',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.blueDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (ready)
            FeedbackParagraphs(text: description)
          else
            Text(
              description,
              style: const TextStyle(
                fontSize: 16,
                height: 1.8,
                color: Color(0xFF333D4B),
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          if (record case final run?
              when ready ||
                  status == FeedbackStatus.available ||
                  status == FeedbackStatus.processing) ...[
            const SizedBox(height: 24),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 20),
            _RecordMetrics(record: run),
          ],
          if (createdLabel case final created?) ...[
            const SizedBox(height: 20),
            Text(
              created,
              style: const TextStyle(fontSize: 12, color: AppColors.gray),
            ),
          ],
          if (nextLabel case final next?) ...[
            const SizedBox(height: 16),
            Text(
              '다음 요청: $next',
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.gray,
              ),
            ),
          ],
          if (error case final message?) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFFB42318),
              ),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 16),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.blue,
                backgroundColor: AppColors.line,
              ),
            ),
          ],
          if (status == FeedbackStatus.available) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onGenerate,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'AI 피드백 요청',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordMetrics extends StatelessWidget {
  const _RecordMetrics({required this.record});
  final RunRecord record;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vertical =
          constraints.maxWidth < 260 ||
          MediaQuery.textScalerOf(context).scale(12) > 17;
      final width = vertical
          ? constraints.maxWidth
          : (constraints.maxWidth - 16) / 3;
      return Wrap(
        spacing: 8,
        runSpacing: 16,
        children: [
          _metric(
            width,
            '거리',
            '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
          ),
          _metric(
            width,
            '활동 시간',
            formatRunDuration(Duration(seconds: record.durationSeconds)),
          ),
          _metric(
            width,
            '평균 페이스',
            '${formatPaceDuration(record.paceSeconds == null ? null : Duration(seconds: record.paceSeconds!))} /km',
          ),
        ],
      );
    },
  );

  Widget _metric(double width, String label, String value) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.gray),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ),
  );
}
