import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../models/run_split.dart';
import '../models/run_motion_evidence.dart';
import 'run_motion_evidence_panel.dart';
import 'run_record_theme.dart';
import '../models/run_integrity.dart';
import '../../../shared/theme/app_colors.dart';

class RunSplitsPanel extends StatelessWidget {
  const RunSplitsPanel({
    required this.splits,
    this.reviewResolved = false,
    this.motionEvidence,
    super.key,
  });
  final List<RunSplit>? splits;
  final bool reviewResolved;
  final List<RunMotionEvidence>? motionEvidence;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('구간별 기록', style: Theme.of(context).textTheme.titleMedium),
      if (!reviewResolved && motionEvidence?.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: RunMotionEvidencePanel(evidence: motionEvidence!),
        ),
      if (!reviewResolved &&
          motionEvidence == null &&
          splits?.any(RunIntegrity.suspicious) == true)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '속도 확인 필요',
            style: TextStyle(color: RunRecordColors.warning, fontSize: 12),
          ),
        ),
      const SizedBox(height: 16),
      if (splits == null || splits!.isEmpty)
        const Text('기록 없음', style: TextStyle(color: RunRecordColors.label))
      else ...[
        const _SplitRow(values: ['km', '시간', '페이스', 'km/h'], heading: true),
        const SizedBox(height: 8),
        for (var i = 0; i < splits!.length; i++) ...[
          _SplitRow(
            flagged:
                !reviewResolved &&
                motionEvidence == null &&
                RunIntegrity.suspicious(splits![i]),
            values: [
              (splits!
                          .take(i + 1)
                          .fold<double>(
                            0,
                            (sum, split) => sum + split.distanceMeters,
                          ) /
                      1000)
                  .toStringAsFixed(2),
              formatRunDuration(splits![i].duration),
              _pace(splits![i]),
              splits![i].pace == null
                  ? '--'
                  : splits![i].speedKmh.toStringAsFixed(1),
            ],
          ),
          if (i < splits!.length - 1)
            const Divider(height: 16, color: AppColors.line),
        ],
      ],
    ],
  );

  String _pace(RunSplit split) {
    final seconds = split.pace?.inSeconds;
    return seconds == null
        ? '--'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.values,
    this.heading = false,
    this.flagged = false,
  });
  final List<String> values;
  final bool heading;
  final bool flagged;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: heading ? 10 : 6, horizontal: 8),
    decoration: heading
        ? BoxDecoration(
            color: RunRecordColors.tableHeading,
            borderRadius: BorderRadius.circular(8),
          )
        : null,
    child: Row(
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Text(
              values[i],
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                fontSize: heading ? 12 : 14,
                color: flagged
                    ? RunRecordColors.warning
                    : heading
                    ? RunRecordColors.label
                    : AppColors.ink,
                fontWeight: heading ? FontWeight.w600 : FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}
