import '../monetization/coin_frames.dart';
import '../run_transfer/external_runs_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/formatters/run_format.dart';
import '../../shared/widgets/panel.dart';
import '../run_feedback/data/run_feedback_service.dart';
import 'data/run_record_service.dart';
import 'models/run_record.dart';
import 'run_history_controller.dart';
import 'run_record_detail_screen.dart';
import 'widgets/run_record_details.dart';
import 'widgets/run_record_theme.dart';
import '../../shared/theme/app_colors.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({
    required this.controller,
    this.feedbackService,
    this.wallet,
    super.key,
  });
  final WalletController? wallet;
  final RunHistoryController controller;
  final RunFeedbackService? feedbackService;

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  bool _showHidden = false;
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
        wallet: widget.wallet,
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
      final records = _showHidden ? state.hiddenRecords : state.visibleRecords;
      return Theme(
        data: runRecordTheme(context),
        child: Scaffold(
          appBar: AppBar(
            title: Text(_showHidden ? '숨긴 기록' : '내 기록'),
            actions: [
              if (widget.controller.service
                  case final SupabaseRunRecordService service)
                PopupMenuButton<String>(
                  tooltip: '기록 옵션',
                  onSelected: (_) => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ExternalRunsScreen(client: service.client),
                    ),
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'external', child: Text('외부 기록 보관함')),
                  ],
                ),
              IconButton(
                tooltip: _showHidden ? '내 기록 보기' : '숨긴 기록 보기',
                onPressed: () => setState(() => _showHidden = !_showHidden),
                icon: Icon(
                  _showHidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: state.loading || state.syncing
                    ? null
                    : state.refresh,
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
                            style: TextStyle(color: RunRecordColors.danger),
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
                            style: TextStyle(color: RunRecordColors.danger),
                          ),
                          TextButton.icon(
                            onPressed: state.loading ? null : state.retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('다시 시도'),
                          ),
                        ] else if (!state.loading &&
                            !state.syncing &&
                            records.isEmpty)
                          Text(
                            _showHidden ? '숨긴 기록이 없습니다.' : '아직 러닝 기록이 없습니다.',
                          ),
                        if (!state.loading && state.hasMore)
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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: _RecordTile(
                        record: record,
                        onTap: () => _open(record),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onTap});

  final RunRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.directions_run, size: 20, color: AppColors.blueText),
      ),
      title: Text(
        formatRunDate(record.startedAt),
        style: text.labelMedium?.copyWith(color: RunRecordColors.label),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
              style: text.titleLarge?.copyWith(
                color: AppColors.blueText,
                fontWeight: FontWeight.w800,
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  formatRunDuration(Duration(seconds: record.durationSeconds)),
                ),
                Text(formatRunPace(record)),
              ],
            ),
            if (record.pendingSync)
              Text(
                '서버 저장 대기',
                style: TextStyle(color: RunRecordColors.warning),
              ),
            if (record.reviewPending)
              Text('검토 중', style: TextStyle(color: RunRecordColors.warning))
            else if (record.integrityStatus == 'rejected')
              Text('반려됨', style: TextStyle(color: RunRecordColors.danger)),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: RunRecordColors.label),
    );
  }
}
