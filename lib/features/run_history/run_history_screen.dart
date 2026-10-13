import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/formatters/run_format.dart';
import '../run_feedback/data/run_feedback_service.dart';
import 'data/run_record_service.dart';
import 'models/run_record.dart';
import 'run_history_controller.dart';
import 'run_record_detail_screen.dart';
import 'widgets/run_record_details.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({
    required this.controller,
    this.feedbackService,
    super.key,
  });
  final RunHistoryController controller;
  final RunFeedbackService? feedbackService;

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  void _open(RunRecord record) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RunRecordDetailScreen(
        record: record,
        controller: widget.controller,
        feedbackService:
            widget.feedbackService ??
            (widget.controller.service is SupabaseRunRecordService
                ? SupabaseRunFeedbackService(
                    (widget.controller.service as SupabaseRunRecordService)
                        .client,
                  )
                : null),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      final records = state.visibleRecords;
      return Scaffold(
        appBar: AppBar(
          title: const Text('내 기록'),
          actions: [
            IconButton(
              tooltip: '새로고침',
              onPressed: state.loading || state.syncing ? null : state.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: records.length + 1,
            itemBuilder: (context, index) {
              if (index == records.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      if (state.syncing) const Text('서버 저장 중'),
                      if (state.syncError != null) ...[
                        Text(
                          state.syncError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        TextButton.icon(
                          onPressed: state.syncing ? null : state.syncPending,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('저장 재시도'),
                        ),
                      ],
                      if (state.loading) const CircularProgressIndicator(),
                      if (state.error != null) ...[
                        Text(
                          state.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        TextButton.icon(
                          onPressed: state.loading ? null : state.retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 시도'),
                        ),
                      ] else if (!state.loading &&
                          !state.syncing &&
                          records.isEmpty)
                        const Text('아직 러닝 기록이 없습니다.')
                      else if (!state.loading && state.hasMore)
                        TextButton.icon(
                          onPressed: state.loadMore,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('더 보기'),
                        ),
                    ],
                  ),
                );
              }
              final record = records[index];
              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    title: Text(formatRunDate(record.startedAt)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          if (record.pendingSync)
                            const Text(
                              '서버 저장 대기',
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                          Text(
                            '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            formatRunDuration(
                              Duration(seconds: record.durationSeconds),
                            ),
                          ),
                          Text(formatRunPace(record)),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(record),
                  ),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
