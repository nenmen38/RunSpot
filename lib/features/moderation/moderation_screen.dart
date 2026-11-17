import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/friend_chat_content.dart';

/// 계정이 바뀌면 이전 계정의 신고와 제재 자료를 사용하지 않습니다.
class ModerationService {
  ModerationService(this.client) : owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? owner;

  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (client.auth.currentUser?.id != owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return result;
  }
}

Future<String?> moderationReason(
  BuildContext context,
  String title, {
  int maxLength = 500,
  String? explanation,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(
    title: title,
    maxLength: maxLength,
    explanation: explanation,
  ),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.maxLength,
    this.explanation,
  });
  final String title;
  final int maxLength;
  final String? explanation;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.explanation != null) Text(widget.explanation!),
          TextField(
            controller: _text,
            maxLength: widget.maxLength,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '사유'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      ValueListenableBuilder(
        valueListenable: _text,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, value.text.trim()),
          child: const Text('확인'),
        ),
      ),
    ],
  );
}

const moderationLabels = {
  'warning': '경고',
  'day': '24시간 작성 제한',
  'week': '7일 작성 제한',
  'indefinite': '무기한 작성 제한',
  'dismissed': '문제없음',
};

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({
    required this.service,
    this.mode = 'mine',
    this.targetId,
    super.key,
  });
  final ModerationService service;
  final String mode;
  final String? targetId;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _busy = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.call('moderation_list', {
        'mode': widget.mode,
        'target_id': widget.targetId,
        'before_id': more && _rows.isNotEmpty ? _rows.last['id'] : null,
      }) as List;
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(data.map((row) => Map<String, dynamic>.from(row as Map)));
        _more = data.length == 50;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _rows.clear();
          _error = '목록을 불러오지 못했습니다. 계정과 권한을 확인해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mutate(
    String method,
    Map<String, dynamic> params,
    String title, {
    int maxLength = 500,
  }) async {
    final note = await moderationReason(context, title, maxLength: maxLength);
    if (!mounted || note == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.call(method, {
        ...params,
        method == 'moderation_appeal' ? 'reason' : 'note': note,
      });
      await _load();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('처리하지 못했습니다. 연결과 계정을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _decide(Map<String, dynamic> row) async {
    final decision = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '위반으로 판단하면 해당 콘텐츠를 삭제하고 선택한 조치를 기록합니다. 작성 제한은 게시글·댓글·채팅에 적용됩니다.',
                ),
              ),
              for (final entry in moderationLabels.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || decision == null) return;
    await _mutate('moderation_decide', {
      'case_id': row['id'],
      'decision': decision,
    }, '${moderationLabels[decision]} 처리 사유');
  }

  String _time(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '기한 없음';
    return '${date.year}.${date.month}.${date.day} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _case(Map<String, dynamic> row) {
    final evidence = row['evidence'] as Map;
    final contextRows = evidence['context'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${row['nickname'] ?? '탈퇴한 사용자'} · ${row['kind'] == 'chat'
              ? '채팅'
              : row['kind'] == 'meetup'
              ? '모임 모집'
              : row['kind'] == 'comment'
              ? '댓글'
              : '게시글'}',
        ),
        if (evidence['title'] != null) Text(evidence['title'].toString()),
        Text(evidence['body']?.toString() ?? ''),
        if (evidence['run_summary'] case final Map summary)
          FriendChatRunCard(summary: summary, mine: false),
        if (row['has_photo'] == true)
          FriendChatPhoto(
            load: () async {
              final encoded = await widget.service.call('moderation_photo', {
                'case_id': row['id'],
              }) as String?;
              if (encoded == null) throw StateError('사진이 없습니다.');
              return base64Decode(encoded.replaceAll('\n', ''));
            },
          ),
        if (contextRows.isNotEmpty)
          ExpansionTile(
            title: const Text('신고 직전 대화'),
            children: [
              for (final item in contextRows)
                ListTile(
                  title: Text(
                    item['sender_id'] == row['author_id'] ? '신고 대상자' : '신고자',
                  ),
                  subtitle: Text(item['body'].toString()),
                ),
            ],
          ),
        Text('신고 사유 · ${row['reason']}'),
        Text('접수 · ${_time(row['created_at'])}'),
        Wrap(
          spacing: 8,
          children: [
            if (row['author_id'] != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ModerationScreen(
                            service: widget.service,
                            mode: 'history',
                            targetId: row['author_id'] as String,
                          ),
                        ),
                      ),
                child: const Text('사용자 위반 이력'),
              ),
            if (row['conflict'] != true && row['author_id'] != null)
              FilledButton(
                onPressed: _busy ? null : () => _decide(row),
                child: const Text('검토·조치'),
              ),
          ],
        ),
        if (row['conflict'] == true)
          const Text('본인과 관련된 신고는 다른 관리자가 처리해야 합니다.'),
      ],
    );
  }

  Widget _action(Map<String, dynamic> row) {
    final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
    final active =
        row['active'] == true &&
        (expires == null || expires.isAfter(DateTime.now()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.mode != 'mine')
          Text(row['nickname'] as String? ?? '탈퇴한 사용자'),
        Text(
          moderationLabels[row['kind']] ?? '이용 제한',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(row['reason'] as String),
        Text('조치 · ${_time(row['created_at'])}'),
        if (row['kind'] != 'warning') ...[
          const Text('제한 기능 · 게시글·댓글·채팅 작성'),
          Text('해제 · ${_time(row['expires_at'])}'),
          Text(
            row['revoked_at'] != null
                ? '취소된 조치'
                : active
                ? '제한 중'
                : '기간 종료',
          ),
        ] else if (row['revoked_at'] != null)
          const Text('취소된 경고'),
        if (row['appeal'] != null) ...[
          Text('이의신청 · ${row['appeal']}'),
          Text(switch (row['appeal_status']) {
            'accepted' => '이의신청 수용',
            'rejected' => '이의신청 기각',
            _ => '이의신청 검토 중',
          }),
        ],
        if (row['appeal_note'] != null) Text('처리 사유 · ${row['appeal_note']}'),
        if (widget.mode == 'mine' &&
            row['appeal'] == null &&
            row['revoked_at'] == null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _mutate(
                    'moderation_appeal',
                    {'action_id': row['id']},
                    '이의신청',
                    maxLength: 1000,
                  ),
            child: const Text('이의신청'),
          ),
        if (widget.mode != 'mine' &&
            row['conflict'] != true &&
            row['revoked_at'] == null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _mutate('moderation_revoke', {
                        'action_id': row['id'],
                        'accept': true,
                      }, '조치 취소 사유'),
                child: const Text('조치 취소'),
              ),
              if (row['appeal_status'] == 'pending')
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _mutate('moderation_revoke', {
                          'action_id': row['id'],
                          'accept': false,
                        }, '이의신청 기각 사유'),
                  child: const Text('이의신청 기각'),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.mode) {
        'cases' => '통합 신고 관리',
        'appeals' => '이의신청 관리',
        'history' => '사용자 위반 이력',
        _ => '이용 제한·이의신청',
      }),
      actions: [
        IconButton(
          tooltip: '새로고침',
          onPressed: _loading || _busy ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading || _busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Text(_error!),
              if (!_loading && _error == null && _rows.isEmpty)
                const Text('표시할 내역이 없습니다.'),
              for (final row in _rows)
                Card(
                  key: ValueKey(row['id']),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: widget.mode == 'cases' ? _case(row) : _action(row),
                  ),
                ),
              if (_more && !_loading && _error == null)
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
