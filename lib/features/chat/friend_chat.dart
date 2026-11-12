import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'chat_list_style.dart';
import 'chat_room_style.dart';

class FriendChatService {
  FriendChatService(this.client) : ownerId = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? ownerId;

  Future<List<Map<String, dynamic>>> load({String? peer, int? before}) async {
    final rows = await _call('friend_chat_read', {
      'peer_id': peer,
      'before_id': before,
    }) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> send(String peer, String body, String requestId) async {
    await _call('friend_chat_send', {
      'peer_id': peer,
      'message_body': body,
      'request_id': requestId,
    });
  }

  Future<dynamic> _call(String function, Map<String, dynamic> params) async {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != ownerId) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    final result = await client
        .rpc(function, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .timeout(const Duration(seconds: 12));
    if (client.auth.currentUser?.id != ownerId) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return result;
  }
}

Future<void> openFriendChat(
  BuildContext context,
  SupabaseClient client,
  String peer,
  String nickname,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => FriendChatView(
      service: FriendChatService(client),
      peer: peer,
      nickname: nickname,
    ),
  ),
);

class FriendChatView extends StatefulWidget {
  const FriendChatView({
    super.key,
    required this.service,
    this.peer,
    this.nickname,
  });

  final FriendChatService service;
  final String? peer;
  final String? nickname;

  @override
  State<FriendChatView> createState() => _FriendChatViewState();
}

class _FriendChatViewState extends State<FriendChatView>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  Timer? _poll;
  bool _loading = false;
  bool _sending = false;
  bool _older = true;
  bool _loaded = false;
  String? _loadError;
  String? _sendError;
  ({String body, String id})? _pendingMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void _resume() {
    _poll?.cancel();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (ModalRoute.of(context)?.isCurrent != false) unawaited(_load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state != AppLifecycleState.inactive) {
      _poll?.cancel();
    }
  }

  Future<void> _load({bool older = false}) async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      final page = await widget.service.load(
        peer: widget.peer,
        before: older ? _rows.last['id'] as int : null,
      );
      if (!mounted) return;
      setState(() {
        if (widget.peer == null) {
          _rows = page;
        } else {
          final ids = page.map((row) => row['id']).toSet();
          final overlap = _rows.any((row) => ids.contains(row['id']));
          _rows = older
              ? [..._rows, ...page]
              : overlap
              ? [...page, ..._rows.where((row) => !ids.contains(row['id']))]
              : page;
          if (older || !overlap) _older = page.length == 50;
        }
        _loaded = true;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _rows = [];
          _loaded = true;
          _loadError = '대화를 불러오지 못했습니다. 친구 관계와 연결을 확인해 주세요.';
        });
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty || widget.peer == null) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final previous = _pendingMessage;
      final message = previous != null && previous.body == text
          ? previous
          : (body: text, id: const Uuid().v4());
      _pendingMessage = message;
      await widget.service.send(widget.peer!, text, message.id);
      _pendingMessage = null;
      if (!mounted) return;
      if (_input.text.trim() == text) _input.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = '메시지를 보내지 못했습니다. 친구 관계와 연결을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  DateTime? _sentAt(Map<String, dynamic> row) {
    final value = row['sent_at'];
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  bool _sameDay(DateTime a, DateTime? b) =>
      b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameGroup(Map<String, dynamic> row, Map<String, dynamic>? other) {
    if (other == null || row['sender_id'] != other['sender_id']) return false;
    final time = _sentAt(row);
    final otherTime = _sentAt(other);
    return time != null &&
        otherTime != null &&
        _sameDay(time, otherTime) &&
        time.difference(otherTime).abs() < const Duration(minutes: 2);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.peer == null) return _buildConversationList();
    final content = Column(
      children: [
        if (_loadError case final error?)
          ListTile(title: Text(error), onTap: _load),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? Center(child: Text('아직 메시지가 없습니다.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  itemCount: _rows.length + (_older ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _rows.length) {
                      return TextButton(
                        onPressed: () => _load(older: true),
                        child: const Text('이전 메시지'),
                      );
                    }
                    final row = _rows[index];
                    final time = _sentAt(row);
                    final previous = index + 1 < _rows.length
                        ? _rows[index + 1]
                        : null;
                    final next = index > 0 ? _rows[index - 1] : null;
                    return ChatMessageBubble(
                      key: ValueKey(row['id']),
                      body: row['body'] as String,
                      nickname: widget.nickname ?? '',
                      mine: row['sender_id'] == widget.service.ownerId,
                      sentAt: time,
                      showDay:
                          time != null &&
                          (previous == null ||
                              !_sameDay(time, _sentAt(previous))),
                      showAvatar: !_sameGroup(row, previous),
                      showTime: !_sameGroup(row, next),
                    );
                  },
                ),
        ),
        if (_sendError case final error?) Text(error),
        ChatComposer(
          controller: _input,
          sending: _sending,
          canSend: _loadError == null,
          onSend: _send,
        ),
      ],
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            ChatAvatar(nickname: widget.nickname ?? ''),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.nickname ?? '대화',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(top: false, child: content),
    );
  }

  Widget _buildConversationList() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_loadError case final error?) {
      return ChatListPlaceholder(message: error, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const ChatListPlaceholder(message: '친구를 눌러 대화를 시작해 보세요.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = _rows[index];
          final nickname = row['nickname'] as String;
          final peer = row['peer_id'] as String;
          return ChatConversationTile(
            key: ValueKey(peer),
            nickname: nickname,
            preview: row['body'] as String,
            sentAt: _sentAt(row),
            onTap: () =>
                openFriendChat(context, widget.service.client, peer, nickname),
          );
        },
      ),
    );
  }
}
