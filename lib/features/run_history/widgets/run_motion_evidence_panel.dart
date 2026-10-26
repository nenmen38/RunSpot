import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import 'run_record_theme.dart';
import '../models/run_motion_evidence.dart';

class RunMotionEvidencePanel extends StatelessWidget {
  const RunMotionEvidencePanel({
    required this.evidence,
    this.showAccuracy = false,
    super.key,
  });
  final List<RunMotionEvidence> evidence;
  final bool showAccuracy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '속도 확인 구간',
        style: TextStyle(color: RunRecordColors.warning, fontSize: 12),
      ),
      for (final item in evidence)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${formatRunDuration(Duration(seconds: item.startSeconds.round()))}–'
            '${formatRunDuration(Duration(seconds: item.endSeconds.round()))} · '
            '${item.speedKmh.toStringAsFixed(1)} km/h'
            '${showAccuracy ? ' · 정확도 ${item.accuracyMeters.toStringAsFixed(0)}m' : ''}',
            style: const TextStyle(
              color: RunRecordColors.warning,
              fontSize: 12,
            ),
          ),
        ),
    ],
  );
}
