import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/data/account_rpc.dart';
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
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 89)),
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
          title: const Text('실제로 수행한 기록 연결'),
          children: [
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('연결할 기록이 없습니다. 러닝을 저장한 뒤 다시 확인해 주세요.'),
              ),
            for (final run in choices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, run),
                child: Text(
                  '${run.startedAt.toLocal().toString().substring(0, 16)} · ${(run.distanceMeters / 1000).toStringAsFixed(2)}km · ${run.durationSeconds ~/ 60}분',
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

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final completed = {
      if (plan != null)
        for (final row in plan['completed'] as List) row['index'],
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 훈련 계획'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _call,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          const Text(
            '주 3회, 4주 일정 · 달리는 날 사이에는 휴식일을 두세요. 목표는 걷기를 섞어 조절할 수 있으며 실제 수행한 기록을 직접 연결합니다.',
          ),
          const SizedBox(height: 16),
          if (plan == null && !_busy && _error == null) ...[
            for (final kind in ['habit', '5k', '10k'])
              Card(
                child: ListTile(
                  title: Text(
                    kind == 'habit'
                        ? '처음 시작하는 러닝 습관'
                        : kind == '5k'
                        ? '5km 목표 일정'
                        : '10km 목표 일정',
                  ),
                  subtitle: Text(
                    kind == 'habit'
                        ? '10~25분 걷기·달리기'
                        : '현재 체력에 맞춰 목표 거리를 조절하세요.',
                  ),
                  onTap: () => _start(kind),
                ),
              ),
          ],
          if (plan != null) ...[
            Text(
              '완료 ${completed.length}/12회',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (var i = 0; i < 12; i++)
              Builder(
                builder: (context) {
                  final week = i ~/ 3;
                  final date = DateTime.parse(plan['start_day'] as String)
                      .add(Duration(days: week * 7 + (i % 3) * 2));
                  final target = plan['kind'] == 'habit'
                      ? '${10 + week * 5}분 걷기·달리기'
                      : plan['kind'] == '5k'
                      ? '${[2, 3, 4, 5][week]}km 편안하게'
                      : '${[5, 6, 8, 10][week]}km 편안하게';
                  return Card(
                    child: ListTile(
                      title: Text('${week + 1}주 ${i % 3 + 1}회 · $target'),
                      subtitle: Text('${date.month}/${date.day} 예정'),
                      leading: Icon(
                        completed.contains(i)
                            ? Icons.check_circle
                            : Icons.directions_run,
                      ),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => completed.contains(i)
                                  ? _call({
                                      'operation': 'undo',
                                      'session_index': i,
                                    })
                                  : _complete(i),
                        child: Text(completed.contains(i) ? '연결 해제' : '기록 연결'),
                      ),
                    ),
                  );
                },
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('훈련 계획을 종료할까요?'),
                          content: const Text(
                            '러닝 기록은 유지되며 이 계획의 일정과 연결만 삭제됩니다.',
                          ),
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
                      if (yes == true && mounted) {
                        await _call({'operation': 'stop'});
                      }
                    },
              child: const Text('계획 종료'),
            ),
          ],
        ],
      ),
    );
  }
}
