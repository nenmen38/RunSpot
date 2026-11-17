import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/data/account_rpc.dart';
import 'run_file_codec.dart';

class ExternalRunsScreen extends StatefulWidget {
  const ExternalRunsScreen({required this.client, super.key});
  final SupabaseClient client;
  @override
  State<ExternalRunsScreen> createState() => _ExternalRunsScreenState();
}

class _ExternalRunsScreenState extends State<ExternalRunsScreen> {
  late final service = AccountRpc(widget.client);
  List<dynamic> _rows = [];
  bool _busy = false;
  bool _more = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    await _work(() async {
      final rows = await service.call('external_runs', {
        'page_offset': more ? _rows.length : 0,
      }) as List;
      if (mounted) {
        setState(() {
          _rows = more ? [..._rows, ...rows] : rows;
          _more = rows.length == 30;
        });
      }
    });
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is FormatException
              ? e.message
              : '처리하지 못했습니다. 파일·권한·연결을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    await _work(() async {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '런스팟 기록',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 1000000) {
        throw const FormatException('1MB 이하 파일을 선택해 주세요.');
      }
      final payload = RunFileCodec.decode(
        utf8.decode(await file.readAsBytes()),
      );
      if (!mounted) return;
      final yes = await _confirm(
        '${payload['started_at']}\n${payload['distance_m']}m · ${payload['duration_sec']}초\n이동 경로를 포함한 기록을 본인 계정의 개인 보관함에 업로드합니다.',
      );
      if (!yes || !mounted) return;
      final rows = await service.call('external_runs', {
        'operation': 'import',
        'payload': payload,
      }) as List;
      if (mounted) {
        setState(() {
          _rows = rows;
          _more = rows.length == 30;
          _message = '가져왔습니다. 동일 파일은 중복 저장하지 않습니다.';
        });
      }
    });
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('기록 가져오기'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('계속'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _importHealth() async {
    if (!await _confirm(
          '건강 앱·헬스 커넥트에서 최근 30일의 달리기를 읽습니다. 안드로이드는 운동 조회에 필요한 거리·걸음·총 칼로리 읽기 권한도 요청합니다. 다음 화면에서 고른 날짜·거리·시간만 개인 보관함에 업로드하며 심박·경로·걸음·칼로리는 업로드하지 않습니다.',
        ) ||
        !mounted) {
      return;
    }
    await _work(() async {
      final health = Health();
      await health.configure();
      final types = [
        HealthDataType.WORKOUT,
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.STEPS,
          HealthDataType.TOTAL_CALORIES_BURNED,
        ],
      ];
      await health.requestAuthorization(
        types,
        permissions: [for (final _ in types) HealthDataAccess.READ],
      );
      if (!mounted || widget.client.auth.currentUser?.id != service.owner) {
        return;
      }
      final points = await health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: DateTime.now().subtract(const Duration(days: 30)),
        endTime: DateTime.now(),
      );
      final rows = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final point in points) {
        final value = point.value;
        if (value is! WorkoutHealthValue ||
            value.workoutActivityType != HealthWorkoutActivityType.RUNNING ||
            !seen.add('${point.sourcePlatform.name}:${point.uuid}')) {
          continue;
        }
        final distance = value.totalDistance;
        if (distance == null ||
            value.totalDistanceUnit != HealthDataUnit.METER ||
            !point.dateTo.isAfter(point.dateFrom)) {
          continue;
        }
        rows.add({
          'source': point.sourcePlatform.name,
          'source_id': point.uuid,
          'started_at': point.dateFrom.toUtc().toIso8601String(),
          'ended_at': point.dateTo.toUtc().toIso8601String(),
          'distance_m': distance,
          'duration_sec': point.dateTo.difference(point.dateFrom).inSeconds,
          'route': <dynamic>[],
        });
      }
      if (!mounted) return;
      final selected = <int>{};
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('가져올 달리기 선택'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (rows.isEmpty)
                    const Text('읽을 수 있는 달리기가 없습니다. 권한과 건강 앱 동기화를 확인해 주세요.'),
                  for (var i = 0; i < rows.length; i++)
                    CheckboxListTile(
                      value: selected.contains(i),
                      onChanged: (v) => setDialog(() {
                        if (v == true) {
                          selected.add(i);
                        } else {
                          selected.remove(i);
                        }
                      }),
                      title: Text('${rows[i]['started_at']}'),
                      subtitle: Text('${rows[i]['distance_m']}m'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('선택 기록 가져오기'),
              ),
            ],
          ),
        ),
      );
      if (yes != true || !mounted) return;
      var count = 0;
      for (final i in selected) {
        if (!mounted) return;
        final imported = await service.call('external_runs', {
          'operation': 'import',
          'payload': rows[i],
        }) as List;
        count++;
        if (mounted) {
          setState(() {
            _rows = imported;
            _more = imported.length == 30;
            _message = '$count개 처리했습니다. 동일 건강 기록은 중복 저장하지 않습니다.';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('외부 기록 보관함'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '본인만 볼 수 있는 외부 기록입니다. 측정 검증을 할 수 없어 순위·보상·크루 목표에는 반영하지 않습니다.',
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _importFile,
              child: const Text('기록 파일 가져오기'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _importHealth,
              child: const Text('건강 앱에서 가져오기'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
        for (final row in _rows)
          ListTile(
            title: Text(
              '${((row['distance_m'] as num) / 1000).toStringAsFixed(2)}km · ${(row['duration_sec'] as int) ~/ 60}분',
            ),
            subtitle: Text(
              '${DateTime.parse(row['started_at'] as String).toLocal().toString().substring(0, 16)} · ${row['source'] == 'file' ? '기록 파일' : '건강 앱'}',
            ),
            trailing: IconButton(
              tooltip: '기록 삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () async {
                      final yes = await _confirm(
                        '이 외부 기록을 보관함에서 삭제합니다. 원본 건강 데이터와 파일은 유지됩니다.',
                      );
                      if (yes && mounted) {
                        await _work(() async {
                          final rows = await service.call('external_runs', {
                            'operation': 'delete',
                            'requested_id': row['id'],
                          }) as List;
                          if (mounted) setState(() => _rows = rows);
                        });
                      }
                    },
            ),
          ),
        if (_more)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('더 보기'),
          ),
      ],
    ),
  );
}
