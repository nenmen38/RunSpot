import '../../monetization/coin_frames.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../run_history/run_history_controller.dart';
import '../../run_history/run_record_detail_screen.dart';
import '../../run_history/data/run_record_service.dart';
import '../../run_feedback/data/run_feedback_service.dart';
import '../../run_history/widgets/run_record_details.dart';
import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/panel.dart';

class RecentRuns extends StatefulWidget {
  const RecentRuns({required this.controller, this.wallet, super.key});
  final RunHistoryController controller;
  final WalletController? wallet;
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
      final record = widget.controller.visibleRecords.firstOrNull;
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('최근 러닝', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (widget.controller.loading && record == null)
              const LinearProgressIndicator(minHeight: 2)
            else if (record == null)
              Text(
                widget.controller.error == null
                    ? '첫 러닝을 시작해 보세요.'
                    : '기록을 불러오지 못했습니다.',
                style: TextStyle(color: AppColors.gray),
              ),
            if (record != null)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(formatRunDate(record.startedAt)),
                      Text(
                        formatRunDuration(
                          Duration(seconds: record.durationSeconds),
                        ),
                      ),
                      Text(formatRunPace(record)),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => RunRecordDetailScreen(
                        record: record,
                        controller: widget.controller,
                        wallet: widget.wallet,
                        feedbackService:
                            widget.controller.service
                                is SupabaseRunRecordService
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
              ),
          ],
        ),
      );
    },
  );
}
