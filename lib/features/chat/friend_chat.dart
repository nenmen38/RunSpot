import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  @override
  Widget build(BuildContext context) {
    final isRoom = widget.peer != null;
    final content = Column(
      children: [
        if (_loadError case final error?)
          ListTile(title: Text(error), onTap: _load),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? Center(
                  child: Text(isRoom ? '아직 메시지가 없습니다.' : '친구를 눌러 대화를 시작해 보세요.'),
                )
              : ListView.builder(
                  reverse: isRoom,
                  itemCount: _rows.length + (isRoom && _older ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _rows.length) {
                      return TextButton(
                        onPressed: () => _load(older: true),
                        child: const Text('이전 메시지'),
                      );
                    }
                    final row = _rows[index];
                    if (isRoom) {
                      final mine = row['sender_id'] == widget.service.ownerId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .75,
                          ),
                          child: Card(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(row['body'] as String),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(row['nickname'] as String),
                      subtitle: Text(
                        row['body'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => openFriendChat(
                        context,
                        widget.service.client,
                        row['peer_id'] as String,
                        row['nickname'] as String,
                      ),
                    );
                  },
                ),
        ),
        if (isRoom) ...[
          if (_sendError case final error?) Text(error),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '메시지 입력',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '보내기',
                  onPressed: _sending || _loadError != null ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return isRoom
        ? Scaffold(
            appBar: AppBar(title: Text(widget.nickname!)),
            body: SafeArea(child: content),
          )
        : content;
  }
}
