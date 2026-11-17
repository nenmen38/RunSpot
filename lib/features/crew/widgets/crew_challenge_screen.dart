import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/data/account_rpc.dart';
import '../models/crew.dart';

class CrewChallengeScreen extends StatefulWidget {
  const CrewChallengeScreen({
    required this.client,
    required this.crew,
    super.key,
  });
  final SupabaseClient client;
  final Crew crew;
  @override
  State<CrewChallengeScreen> createState() => _CrewChallengeScreenState();
}

class _CrewChallengeScreenState extends State<CrewChallengeScreen> {
  late final service = AccountRpc(widget.client);
  List<dynamic> _rows = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _call();
  }

  Future<void> _call([Map<String, dynamic> params = const {}]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await service.call('crew_challenge', {
        'crew_id': widget.crew.id,
        ...params,
      }) as List;
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PostgrestException
              ? e.message
              : '공동 목표를 불러오지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    var km = 100;
    var days = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('크루 공동 목표'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: km,
                items: [10, 50, 100, 300, 500, 1000]
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text('$v km')),
                    )
                    .toList(),
                onChanged: (v) => setDialog(() => km = v!),
              ),
              DropdownButton<int>(
                value: days,
                items: [7, 14, 30, 60, 90]
                    .map((v) => DropdownMenuItem(value: v, child: Text('$v 일')))
                    .toList(),
                onChanged: (v) => setDialog(() => days = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await _call({
        'operation': 'create',
        'challenge_id': const Uuid().v4(),
        'target_km': km,
        'days': days,
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.crew.name} 공동 목표'),
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
        const Text(
          '참여 이후의 공개·검증 완료 기록 중 300m 이상 달린 거리를 합산합니다. 크루에는 전체 합계만 표시됩니다. 참여 취소·크루 탈퇴 시 본인 기여분이 제외됩니다.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (widget.crew.isOwner)
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('새 공동 목표'),
          ),
        if (_rows.isEmpty && !_busy) const Text('등록된 공동 목표가 없습니다.'),
        for (final row in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${((row['distance_m'] as num) / 1000).toStringAsFixed(1)} / ${row['target_km']} km',
                  ),
                  LinearProgressIndicator(
                    value:
                        ((row['distance_m'] as num) /
                                ((row['target_km'] as num) * 1000))
                            .clamp(0, 1)
                            .toDouble(),
                  ),
                  Text(
                    '${DateTime.parse(row['ends_at'] as String).toLocal().toString().substring(0, 16)}까지',
                  ),
                  if (DateTime.parse(row['ends_at'] as String)
                      .isAfter(DateTime.now()))
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _call({
                              'operation': row['joined'] == true
                                  ? 'leave'
                                  : 'join',
                              'challenge_id': row['id'],
                            }),
                      child: Text(
                        row['joined'] == true ? '참여 취소' : '합산에 동의하고 참여',
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
