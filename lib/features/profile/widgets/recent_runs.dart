import 'dart:async';

import 'package:flutter/material.dart';

import '../../run_history/run_history_controller.dart';
import '../../run_history/run_record_detail_screen.dart';
import '../../run_history/data/run_record_service.dart';
import '../../run_feedback/data/run_feedback_service.dart';
import '../../run_history/widgets/run_record_details.dart';
import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';

class RecentRuns extends StatefulWidget {
  const RecentRuns({
    required this.controller,
    required this.onHistoryTap,
    super.key,
  });
  final RunHistoryController controller;
  final VoidCallback onHistoryTap;
  @override
  State<RecentRuns> createState() => _RecentRunsState();
}

class _RecentRunsState extends State<RecentRuns> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final records = widget.controller.visibleRecords.take(3);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '최근 러닝',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: widget.onHistoryTap,
                child: const Text('내 기록'),
              ),
            ],
          ),
          if (widget.controller.loading && records.isEmpty)
            const LinearProgressIndicator(minHeight: 2)
          else if (records.isEmpty)
            Text(
              widget.controller.error == null
                  ? '첫 러닝을 시작해 보세요.'
                  : '기록을 불러오지 못했습니다.',
              style: const TextStyle(color: AppColors.gray),
            ),
          for (final record in records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${formatRunDate(record.startedAt)} · ${formatRunDuration(Duration(seconds: record.durationSeconds))}',
              ),
              trailing: Text(
                formatRunPace(record),
                style: const TextStyle(
                  color: AppColors.blueDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RunRecordDetailScreen(
                    record: record,
                    controller: widget.controller,
                    feedbackService:
                        widget.controller.service is SupabaseRunRecordService
                        ? SupabaseRunFeedbackService(
                            (widget.controller.service
                                    as SupabaseRunRecordService)
                                .client,
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
