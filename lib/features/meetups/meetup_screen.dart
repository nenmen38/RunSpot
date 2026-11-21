import '../../shared/data/account_rpc.dart';
import '../../shared/formatters/run_format.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class MeetupScreen extends StatefulWidget {
  const MeetupScreen({required this.service, required this.onGroup, super.key});
  final AccountRpc service;
  final Future<void> Function() onGroup;
  @override
  State<MeetupScreen> createState() => _MeetupScreenState();
}

class _MeetupScreenState extends State<MeetupScreen> {
  final _region = TextEditingController();
  final List<Map<String, dynamic>> _rows = [];
  int? _pace;
  bool _mine = false;
  bool _busy = false;
  bool _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _region.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.call('meetup_list', {
        'region_filter': _region.text.trim(),
        'pace_filter': _pace,
        'only_mine': _mine,
        'page_offset': more ? _rows.length : 0,
      }) as List;
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(data.map((row) => Map<String, dynamic>.from(row as Map)));
        _more = data.length == 30;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _rows.clear();
          _error = '모임을 불러오지 못했습니다. 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(Map<String, dynamic> row, String operation) async {
    if (_busy) return;
    if (operation == 'cancel') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('모임을 취소할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('돌아가기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('모임 취소'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.call('meetup_action', {
        'meetup_id': row['id'],
        'operation': operation,
      });
      if (!mounted) return;
      if (operation == 'prepare') await widget.onGroup();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('처리하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _report(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모임 신고'),
        content: TextField(
          controller: reason,
          maxLength: 500,
          decoration: const InputDecoration(labelText: '신고 사유'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: const Text('신고'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (text == null || !mounted) return;
    try {
      await widget.service.call('report_meetup', {
        'meetup_id': row['id'],
        'reason': text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _calendar(
    Map<String, dynamic> row,
    BuildContext buttonContext,
  ) async {
    final start = DateTime.parse(row['starts_at'] as String).toUtc();
    final end = start.add(
      Duration(
        seconds:
            (row['distance_km'] as int) * (row['pace_seconds'] as int) + 900,
      ),
    );
    String stamp(DateTime d) =>
        '${d.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    String escape(String s) => s
        .replaceAll('\\', '\\\\')
        .replaceAll('\r', '')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
    final data =
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//RunSpot//Meetups//KO\r\nBEGIN:VEVENT\r\nUID:${row['id']}@runspot\r\nDTSTAMP:${stamp(DateTime.now().toUtc())}\r\nDTSTART:${stamp(start)}\r\nDTEND:${stamp(end)}\r\nSUMMARY:${escape(row['title'] as String)}\r\nLOCATION:${escape(row['place'] as String)}\r\nBEGIN:VALARM\r\nTRIGGER:-PT30M\r\nACTION:DISPLAY\r\nDESCRIPTION:러닝 모임 출발 준비\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(_foldCalendar(data)),
            mimeType: 'text/calendar',
          ),
        ],
        fileNameOverrides: ['runspot-meetup.ics'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('동네 러닝 모임'),
      actions: [
        IconButton(
          tooltip: '새로고침',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '모임 모집',
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _CreateMeetup(service: widget.service),
                    ),
                  );
                  if (mounted) _load();
                },
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _region,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: '지역 검색',
                  hintText: '예: 경산시 하양읍',
                  counterText: '',
                  suffixIcon: IconButton(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (_) => _load(),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _pace,
                      hint: const Text('모든 페이스'),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('모든 페이스'),
                        ),
                        for (final pace in [240, 300, 360, 420, 480, 540])
                          DropdownMenuItem(
                            value: pace,
                            child: Text(
                              '${formatPaceDuration(Duration(seconds: pace))}/km 전후 30초',
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() => _pace = value);
                              _load();
                            },
                    ),
                  ),
                  FilterChip(
                    label: const Text('참가한 모임'),
                    selected: _mine,
                    onSelected: _busy
                        ? null
                        : (value) {
                            setState(() => _mine = value);
                            _load();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_rows.isEmpty && !_busy && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('조건에 맞는 모임이 없습니다. 지역을 바꾸거나 첫 모임을 모집해 보세요.'),
                ),
              for (final row in _rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${row['region']} · ${row['place']}'),
                        Text(
                          DateTime.parse(row['starts_at'] as String)
                              .toLocal()
                              .toString()
                              .substring(0, 16),
                        ),
                        Text(
                          '${row['distance_km']}km · ${formatPaceDuration(Duration(seconds: row['pace_seconds'] as int))}/km · ${row['member_count']}/${row['capacity']}명',
                        ),
                        Text('주최 ${row['host_name']}'),
                        if (row['is_host'] != true)
                          TextButton(
                            onPressed: _busy ? null : () => _report(row),
                            child: const Text('신고'),
                          ),
                        if (row['cancelled'] == true)
                          const Text('취소된 모임')
                        else
                          Wrap(
                            spacing: 8,
                            children: [
                              if (row['is_host'] == true) ...[
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _action(row, 'prepare'),
                                  child: const Text('출발 준비'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _action(row, 'cancel'),
                                  child: const Text('모임 취소'),
                                ),
                              ] else if (row['joined'] == true)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _action(row, 'leave'),
                                  child: const Text('참가 취소'),
                                )
                              else
                                FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _action(row, 'join'),
                                  child: const Text('참가하기'),
                                ),
                              if (row['joined'] == true) ...[
                                Builder(
                                  builder: (buttonContext) => TextButton(
                                    onPressed: () async {
                                      try {
                                        await _calendar(row, buttonContext);
                                      } catch (_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('일정을 공유하지 못했습니다.'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('캘린더로 보내기'),
                                  ),
                                ),
                                if (row['group_id'] != null)
                                  TextButton(
                                    onPressed: widget.onGroup,
                                    child: const Text('함께 달리기 열기'),
                                  ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (_more && !_busy)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('더 보기'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CreateMeetup extends StatefulWidget {
  const _CreateMeetup({required this.service});
  final AccountRpc service;
  @override
  State<_CreateMeetup> createState() => _CreateMeetupState();
}

class _CreateMeetupState extends State<_CreateMeetup> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _region = TextEditingController();
  final _place = TextEditingController();
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  int _distance = 5;
  int _pace = 360;
  int _capacity = 6;
  bool _busy = false;
  String? _error;
  String _request = const Uuid().v4();
  @override
  void dispose() {
    _title.dispose();
    _region.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.service.call('meetup_create', {
        'request_id': _request,
        'title': _title.text.trim(),
        'region': _region.text.trim(),
        'place': _place.text.trim(),
        'starts_at': _start.toUtc().toIso8601String(),
        'distance_km': _distance,
        'pace_seconds': _pace,
        'capacity': _capacity,
      });
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '등록하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label, int length) =>
      TextFormField(
        controller: controller,
        maxLength: length,
        enabled: !_busy,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '입력해 주세요.' : null,
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('러닝 모임 모집')),
    body: Form(
      key: _form,
      onChanged: () => _request = const Uuid().v4(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field(_title, '모임 이름', 80),
          _field(_region, '지역', 40),
          _field(_place, '공개된 만남 장소', 150),
          const Text('참가하면 주최자와 함께 달리기 참여자에게 닉네임과 완료 기록이 공유됩니다.'),
          ListTile(
            title: const Text('출발 시각'),
            subtitle: Text(_start.toString().substring(0, 16)),
            onTap: _busy
                ? null
                : () async {
                    final day = await showDatePicker(
                      context: context,
                      initialDate: _start,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 89)),
                    );
                    if (day == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_start),
                    );
                    if (time != null && mounted) {
                      setState(() {
                        _start = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          time.hour,
                          time.minute,
                        );
                        _request = const Uuid().v4();
                      });
                    }
                  },
          ),
          DropdownButtonFormField<int>(
            initialValue: _distance,
            decoration: const InputDecoration(labelText: '목표 거리'),
            items: [
              for (final value in [1, 3, 5, 10, 15, 20])
                DropdownMenuItem(value: value, child: Text('${value}km')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _distance = value!),
          ),
          DropdownButtonFormField<int>(
            initialValue: _pace,
            decoration: const InputDecoration(labelText: '목표 페이스'),
            items: [
              for (final value in [
                240,
                270,
                300,
                330,
                360,
                390,
                420,
                450,
                480,
                540,
              ])
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    '${formatPaceDuration(Duration(seconds: value))}/km',
                  ),
                ),
            ],
            onChanged: _busy ? null : (value) => setState(() => _pace = value!),
          ),
          DropdownButtonFormField<int>(
            initialValue: _capacity,
            decoration: const InputDecoration(labelText: '정원'),
            items: [
              for (final value in [2, 4, 6, 10, 20, 30])
                DropdownMenuItem(value: value, child: Text('$value명')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _capacity = value!),
          ),
          if (_error != null) Text(_error!),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '등록 중' : '모집하기'),
          ),
        ],
      ),
    ),
  );
}

// 캘린더 표준의 줄 길이를 UTF-8 바이트 기준으로 맞추고 한글 문자를 나누지 않습니다.
String _foldCalendar(String text) {
  final out = StringBuffer();
  for (final line in text.split('\r\n')) {
    if (line.isEmpty) continue;
    var length = 0;
    for (final rune in line.runes) {
      final character = String.fromCharCode(rune);
      final bytes = utf8.encode(character).length;
      if (length + bytes > 75) {
        out.write('\r\n ');
        length = 1;
      }
      out.write(character);
      length += bytes;
    }
    out.write('\r\n');
  }
  return out.toString();
}
