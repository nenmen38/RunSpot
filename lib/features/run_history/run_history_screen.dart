import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/formatters/run_format.dart';
import 'models/run_record.dart';
import 'run_history_controller.dart';
import 'widgets/run_record_details.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({required this.controller, super.key});
  final RunHistoryController controller;

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  void _open(RunRecord record) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('러닝 기록'),
      content: SingleChildScrollView(child: RunRecordDetails(record: record)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: const Text('내 기록'),
          actions: [
            IconButton(
              tooltip: '새로고침',
              onPressed: state.loading ? null : state.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: state.records.length + 1,
            itemBuilder: (context, index) {
              if (index == state.records.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
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
                      ] else if (!state.loading && state.records.isEmpty)
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
              final record = state.records[index];
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
