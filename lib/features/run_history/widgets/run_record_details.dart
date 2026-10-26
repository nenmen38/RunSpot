import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/widgets/metric_values.dart';
import '../../../shared/theme/app_colors.dart';
import '../models/run_record.dart';
import 'run_record_theme.dart';

String formatRunDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String formatRunPace(RunRecord record) {
  final pace = record.paceSeconds;
  return pace == null
      ? '--'
      : '${pace ~/ 60}:${(pace % 60).toString().padLeft(2, '0')} /km';
}

class RunRecordDetails extends StatelessWidget {
  const RunRecordDetails({required this.record, super.key});
  final RunRecord record;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (record.pendingSync) ...[
        const Text(
          '서버 저장 대기',
          style: TextStyle(color: RunRecordColors.warning),
        ),
        const SizedBox(height: 8),
      ],
      if (record.reviewPending) ...[
        const Text(
          '검토 중 · 랭킹·경험치 보류',
          style: TextStyle(color: RunRecordColors.warning, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ] else if (record.integrityStatus == 'rejected') ...[
        const Text(
          '반려됨',
          style: TextStyle(color: RunRecordColors.danger, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        formatRunDate(record.startedAt),
        style: const TextStyle(color: RunRecordColors.label, fontSize: 13),
      ),
      const SizedBox(height: 12),
      Text(
        '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
        style: const TextStyle(
          color: AppColors.blueDark,
          fontSize: 36,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: MetricValue(
              label: '시간',
              value: formatRunDuration(
                Duration(seconds: record.durationSeconds),
              ),
            ),
          ),
          Expanded(
            child: MetricValue(label: '평균 페이스', value: formatRunPace(record)),
          ),
        ],
      ),
      if (record.temperature != null) ...[
        const SizedBox(height: 16),
        Text(
          record.temperature!.label,
          style: const TextStyle(color: RunRecordColors.label, fontSize: 13),
        ),
      ],
    ],
  );
}
