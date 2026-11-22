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
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '속도 확인 필요',
            style: TextStyle(color: RunRecordColors.warning, fontSize: 12),
          ),
        ),
      const SizedBox(height: 16),
      if (splits == null || splits!.isEmpty)
        Text('기록 없음', style: TextStyle(color: RunRecordColors.label))
      else ...[
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                MediaQuery.textScalerOf(context).scale(14) * 20 >
                constraints.maxWidth;
            return Column(
              children: [
                if (!compact) ...[
                  const _SplitRow(values: _SplitRow.labels, heading: true),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < splits!.length; i++) ...[
                  _SplitRow(
                    compact: compact,
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
                    Divider(height: 16, color: AppColors.line),
                ],
              ],
            );
          },
        ),
      ],
    ],
  );

  String _pace(RunSplit split) =>
      split.pace == null ? '--' : formatPaceDuration(split.pace);
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.values,
    this.heading = false,
    this.flagged = false,
    this.compact = false,
  });
  final List<String> values;
  final bool heading;
  final bool flagged;
  final bool compact;
  static const labels = ['구간 끝(km)', '시간', '페이스', 'km/h'];

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: heading ? 10 : 6, horizontal: 8),
    decoration: heading
        ? BoxDecoration(
            color: RunRecordColors.tableHeading,
            borderRadius: BorderRadius.circular(8),
          )
        : null,
    child: compact
        ? Column(
            children: [
              for (final offset in [0, 2])
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = offset; i < offset + 2; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labels[i],
                                style: TextStyle(color: RunRecordColors.label),
                              ),
                              _value(i),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          )
        : Row(
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: _value(
                    i,
                    align: i == 0 ? TextAlign.left : TextAlign.right,
                  ),
                ),
            ],
          ),
  );

  Widget _value(int index, {TextAlign? align}) => Text(
    values[index],
    textAlign: align,
    style: TextStyle(
      fontSize: heading ? 12 : 14,
      color: flagged
          ? RunRecordColors.warning
          : heading
          ? RunRecordColors.label
          : AppColors.ink,
      fontWeight: heading ? FontWeight.w600 : FontWeight.w700,
    ),
  );
}
