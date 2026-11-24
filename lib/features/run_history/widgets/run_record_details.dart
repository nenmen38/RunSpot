import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/widgets/metric_values.dart';
import '../../../shared/theme/app_colors.dart';
import '../../settings/body_weight.dart';
import '../models/run_calories.dart';
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
      : '${formatPaceDuration(Duration(seconds: pace))} /km';
}

class RunRecordDetails extends StatelessWidget {
  const RunRecordDetails({
    required this.record,
    this.weight,
    this.showDistance = true,
    super.key,
  });
  final RunRecord record;
  final bool showDistance;

  /// 칼로리 계산에 쓰는 체중 설정입니다. 없으면 앱 공용 설정을 씁니다.
  final BodyWeight? weight;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (record.pendingSync) ...[
        Text('서버 저장 대기', style: TextStyle(color: RunRecordColors.warning)),
        const SizedBox(height: 8),
      ],
      if (record.reviewPending) ...[
        Text(
          '검토 중 · 랭킹·경험치 보류',
          style: TextStyle(color: RunRecordColors.warning, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ] else if (record.integrityStatus == 'rejected') ...[
        Text(
          '반려됨',
          style: TextStyle(color: RunRecordColors.danger, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        formatRunDate(record.startedAt),
        style: TextStyle(color: RunRecordColors.label, fontSize: 13),
      ),
      if (showDistance) ...[
        const SizedBox(height: 12),
        Text(
          '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
          style: TextStyle(
            color: AppColors.blueText,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
      ],
      SizedBox(height: showDistance ? 20 : 12),
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
          // 러닝을 마치면 페이스로 추정한 칼로리를 바로 보여줍니다.
          Expanded(
            child: ListenableBuilder(
              listenable: weight ?? BodyWeight.instance,
              builder: (context, _) {
                final kcal = estimateRunCalories(
                  distanceMeters: record.distanceMeters.toDouble(),
                  durationSeconds: record.durationSeconds,
                  splits: record.splits,
                  weightKg: (weight ?? BodyWeight.instance).kg,
                );
                return MetricValue(
                  label: '칼로리',
                  value: kcal == null ? '--' : '$kcal kcal',
                );
              },
            ),
          ),
        ],
      ),
      if (record.temperature != null) ...[
        const SizedBox(height: 16),
        Text(
          record.temperature!.label,
          style: TextStyle(color: RunRecordColors.label, fontSize: 13),
        ),
      ],
    ],
  );
}
