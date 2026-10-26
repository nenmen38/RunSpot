import 'dart:async';

import '../health/data/run_health_service.dart';
import '../health/widgets/run_health_panel.dart';
import 'widgets/run_splits_panel.dart';

import 'package:flutter/material.dart';

import '../../shared/maps/run_map.dart';

import '../run_feedback/data/run_feedback_service.dart';
import '../run_feedback/run_feedback_panel.dart';
import '../run_share/run_share_screen.dart';
import 'data/run_record_service.dart';
import 'models/run_record.dart';
import 'models/run_route.dart';
import 'run_history_controller.dart';
import 'widgets/run_record_details.dart';
import 'widgets/run_record_theme.dart';
import 'widgets/saved_run_map.dart';

class RunRecordDetailScreen extends StatefulWidget {
  const RunRecordDetailScreen({
    required this.record,
    required this.controller,
    this.mapBridgeFactory,
    this.feedbackService,
    this.healthService,
    super.key,
  });
  final RunRecord record;
  final RunHistoryController controller;
  final MapBridgeFactory? mapBridgeFactory;
  final RunFeedbackService? feedbackService;
  final RunHealthService? healthService;

  @override
  State<RunRecordDetailScreen> createState() => _RunRecordDetailScreenState();
}

class _RunRecordDetailScreenState extends State<RunRecordDetailScreen> {
  RunRoute? _route;
  late final RunHealthService _health =
      widget.healthService ?? DeviceRunHealthService();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final route = await widget.controller.loadRoute(widget.record);
      if (mounted) setState(() => _route = route);
    } catch (_) {
      if (mounted) setState(() => _error = '경로를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Theme(
      data: runRecordTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('러닝 기록'),
          actions: [
            IconButton(
              tooltip: '러닝 기록 공유',
              icon: const Icon(Icons.ios_share),
              onPressed: !widget.controller.service.isCurrentOwner
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RunShareScreen(
                          record: widget.controller.visibleRecords.firstWhere(
                            (record) =>
                                record.clientRunId == widget.record.clientRunId,
                            orElse: () => widget.record,
                          ),
                          isCurrentOwner: () =>
                              widget.controller.service.isCurrentOwner,
                          loadRoute: () =>
                              widget.controller.loadRoute(widget.record),
                          ownerChanges:
                              widget.controller.service
                                  is SupabaseRunRecordService
                              ? (widget.controller.service
                                        as SupabaseRunRecordService)
                                    .client
                                    .auth
                                    .onAuthStateChange
                              : null,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        body: !widget.controller.service.isCurrentOwner
            ? const Center(child: Text('로그인 상태를 확인해 주세요.'))
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '이동 경로',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(Icons.lock_outline, size: 16),
                        SizedBox(width: 4),
                        Text('나만 보기'),
                      ],
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      height: 320,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    SizedBox(
                      height: 320,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_route!.isEmpty)
                    const SizedBox(
                      height: 160,
                      child: Center(child: Text('저장된 경로가 없습니다.')),
                    )
                  else
                    SavedRunMap(
                      route: _route!,
                      mapBridgeFactory: widget.mapBridgeFactory,
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: RunRecordDetails(
                      record: widget.controller.visibleRecords.firstWhere(
                        (record) =>
                            record.clientRunId == widget.record.clientRunId,
                        orElse: () => widget.record,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: RunSplitsPanel(
                      motionEvidence: widget.controller.visibleRecords
                          .firstWhere(
                            (record) =>
                                record.clientRunId == widget.record.clientRunId,
                            orElse: () => widget.record,
                          )
                          .motionEvidence,
                      reviewResolved:
                          widget.controller.visibleRecords
                              .firstWhere(
                                (record) =>
                                    record.clientRunId ==
                                    widget.record.clientRunId,
                                orElse: () => widget.record,
                              )
                              .integrityStatus !=
                          'pending',
                      splits: widget.controller.visibleRecords
                          .firstWhere(
                            (record) =>
                                record.clientRunId == widget.record.clientRunId,
                            orElse: () => widget.record,
                          )
                          .splits,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: RunHealthPanel(
                      service: _health,
                      start: widget.record.startedAt,
                      end: widget.record.endedAt,
                      isCurrentOwner: () =>
                          widget.controller.service.isCurrentOwner,
                    ),
                  ),
                  if (!widget.record.pendingSync &&
                      widget.feedbackService != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: RunFeedbackPanel(
                        key: ValueKey(widget.record.id),
                        runId: widget.record.id,
                        service: widget.feedbackService!,
                      ),
                    ),
                ],
              ),
      ),
    ),
  );
}
