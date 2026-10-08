import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../models/run_record.dart';

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
        const Text('서버 저장 대기', style: TextStyle(color: Colors.deepOrange)),
        const SizedBox(height: 8),
      ],
      Text('시작 ${formatRunDate(record.startedAt)}'),
      Text('종료 ${formatRunDate(record.endedAt)}'),
      const SizedBox(height: 16),
      _metric('거리', '${(record.distanceMeters / 1000).toStringAsFixed(2)} km'),
      _metric(
        '시간',
        formatRunDuration(Duration(seconds: record.durationSeconds)),
      ),
      _metric('평균 페이스', formatRunPace(record)),
    ],
  );

  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
