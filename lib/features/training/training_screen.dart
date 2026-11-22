import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/data/account_rpc.dart';
import '../../shared/formatters/run_format.dart';
import '../../shared/layout/readable_width.dart';
import '../../shared/widgets/status_view.dart';
import '../run_history/widgets/run_record_details.dart';
import 'widgets/training_plan_cards.dart';
import '../run_history/data/run_record_service.dart';
import '../run_history/models/run_record.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({required this.client, super.key});
  final SupabaseClient client;
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final service = AccountRpc(widget.client);
  Map<String, dynamic>? _plan;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _call();
  }

  Future<void> _call([Map<String, dynamic> args = const {}]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await service.call('training_plan', args);
      if (mounted) {
        setState(
          () => _plan = result == null
              ? null
              : Map<String, dynamic>.from(result as Map),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '계획을 처리하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(String kind) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = await showDatePicker(
      context: context,
      helpText: '훈련 시작일 선택',
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year, today.month, today.day + 89),
    );
    if (day == null || !mounted) return;
    await _call({
      'operation': 'start',
      'kind': kind,
      'start_day': day.toIso8601String().substring(0, 10),
    });
  }

  Future<void> _complete(int index) async {
    setState(() => _busy = true);
    try {
      final runs = await SupabaseRunRecordService(widget.client)
          .list(offset: 0, limit: 100);
      if (!mounted) return;
      final start = DateTime.parse(_plan!['start_day'] as String);
      final used = {
        for (final row in _plan!['completed'] as List) row['run_id'],
      };
      final choices = runs
          .where(
            (r) =>
                !r.startedAt.toLocal().isBefore(start) && !used.contains(r.id),
          )
          .toList();
      final run = await showDialog<RunRecord>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('러닝 기록 연결'),
          children: [
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('연결할 기록이 없습니다. 러닝을 저장한 뒤 다시 확인해 주세요.'),
              ),
            for (final run in choices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, run),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${(run.distanceMeters / 1000).toStringAsFixed(2)}km · ${formatRunDuration(Duration(seconds: run.durationSeconds))}',
                  ),
                  subtitle: Text(formatRunDate(run.startedAt)),
                ),
              ),
          ],
        ),
      );
      if (run != null && mounted) {
        await _call({
          'operation': 'complete',
          'session_index': index,
          'run_id': run.id,
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '기록을 연결하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('훈련 계획을 종료할까요?'),
        content: const Text('러닝 기록은 유지되며 이 계획의 일정과 연결만 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('계획 종료'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _call({'operation': 'stop'});
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final kind = TrainingPlanKind.values
        .where((kind) => kind.id == plan?['kind'])
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 훈련 계획'),
        actions: [
          IconButton(
            tooltip: '훈련 계획 새로고침',
            onPressed: _busy ? null : _call,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ReadableWidth(
          child: plan == null && _busy
              ? const StatusView.loading(message: '훈련 계획을 불러오는 중입니다.')
              : plan == null && _error != null
              ? StatusView.error(message: _error!, onRetry: _call)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null) InlineError(message: _error!),
                    if (plan == null)
                      TrainingPlanChoices(onSelect: (kind) => _start(kind.id))
                    else if (kind != null) ...[
                      TrainingPlanSchedule(
                        kind: kind,
                        start: DateTime.parse(plan['start_day'] as String),
                        completed: {
                          for (final row in plan['completed'] as List)
                            row['index'] as int,
                        },
                        onSessionTap: _busy
                            ? null
                            : (index) {
                                final linked = (plan['completed'] as List).any(
                                  (row) => row['index'] == index,
                                );
                                if (linked) {
                                  _call({
                                    'operation': 'undo',
                                    'session_index': index,
                                  });
                                } else {
                                  _complete(index);
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _stop,
                          child: const Text('계획 종료'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '달리는 날 사이에는 쉬는 날을 두세요. 목표는 걷기를 섞어 조절하고, 실제 러닝 기록을 일정에 연결할 수 있습니다.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
