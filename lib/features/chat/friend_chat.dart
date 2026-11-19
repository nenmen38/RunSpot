import '../titles/badge_directory.dart';
import 'chat_draft_store.dart';
import '../moderation/moderation_screen.dart';

import 'package:runquest/shared/widgets/status_view.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'chat_rooms.dart';
import 'chat_list_style.dart';
import 'friend_chat_content.dart';
import 'chat_sync.dart';
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

  Future<void> sendContent(String peer, FriendChatDraft draft) async {
    if (draft.body case final body? when draft.replyTo == null) {
      return send(peer, body, draft.id);
    }
    await _call('friend_chat_send_content', {
      'peer_id': peer,
      'message_body': draft.body,
      'request_id': draft.id,
      'reply_to': draft.replyTo,
      'jpeg': draft.photo,
      'run_id': draft.runId,
    });
  }

  Future<Uint8List> photo(String peer, int id) async {
    final encoded = await _call('friend_chat_photo', {
      'peer_id': peer,
      'message_id': id,
    }) as String?;
    if (encoded == null) throw StateError('사진을 볼 수 없습니다.');
    return base64Decode(encoded.replaceAll('\n', ''));
  }

  Future<void> report(int id, String reason) async {
    await _call('report_chat', {'message_id': id, 'reason': reason});
  }

  Future<void> delete(String peer, int id) async {
    await _call('friend_chat_delete', {'peer_id': peer, 'message_id': id});
  }

  /// 안 읽은 메시지 총 개수입니다.
  Future<int> unreadTotal() async {
    final friends = ((await _call('friend_chat_unread_total', const {})) as num)
        .toInt();
    // 단톡·크루 대화방의 안 읽은 메시지도 함께 셉니다. 서버가 아직 지원하지 않으면 1:1만 셉니다.
    try {
      return friends +
          ((await _call('chat_rooms_unread_total', const {})) as num).toInt();
    } catch (_) {
      return friends;
    }
  }

  /// 내 대화에 새 메시지나 읽음 변경이 생기면 [onChanged]를 부릅니다.
  /// 신호에는 내용이 없고, 받은 뒤 권한을 다시 검사하는 조회로 새로 불러옵니다.
  /// 돌려준 함수를 부르면 연결을 끊습니다.
  void Function() listen({
    required void Function() onChanged,
    required void Function(bool connected) onConnection,
  }) {
    final owner = ownerId;
    if (owner == null) return () {};
    final channel = client.channel(
      'chat:$owner',
      opts: const RealtimeChannelConfig(private: true),
    );
    channel
      ..onBroadcast(event: 'changed', callback: (_) => onChanged())
      ..subscribe(
        (status, _) =>
            onConnection(status == RealtimeSubscribeStatus.subscribed),
      );
    return () => unawaited(client.removeChannel(channel));
  }

  /// [lastId]까지 받은 메시지를 읽음으로 표시합니다. 상대 화면의 '1'이 사라집니다.
  Future<void> markRead(String peer, int lastId) async {
    await _call('friend_chat_mark_read', {'peer_id': peer, 'last_id': lastId});
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
  String nickname, {
  ChatSync? sync,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => FriendChatView(
      service: FriendChatService(client),
      draftStore: client.auth.currentUser == null
          ? null
          : ChatDraftStore(
              owner: client.auth.currentUser!.id,
              namespace: client.rest.url,
              peer: peer,
            ),
      peer: peer,
      nickname: nickname,
      sync: sync,
    ),
  ),
);

class FriendChatView extends StatefulWidget {
  const FriendChatView({
    super.key,
    required this.service,
    this.peer,
    this.nickname,
    this.sync,
    this.draftStore,
    this.rooms,
  });

  /// 있으면 대화 목록에 단톡·크루 대화방도 함께 보여줍니다.
  final ChatRoomService? rooms;

  /// 실시간 신호를 받으면 바로 다시 불러옵니다. 없으면 주기적으로만 확인합니다.
  final ChatDraftStore? draftStore;
  final ChatSync? sync;
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
  List<ChatRoomSummary> _roomList = [];
  bool _loadingRooms = false;
  Timer? _poll;
  bool _loading = false;
  bool _sending = false;
  bool _restoring = true;
  bool _older = true;
  bool _loaded = false;
  String? _loadError;
  String? _sendError;
  FriendChatDraft? _pendingMessage;
  Map<String, dynamic>? _reply;
  bool _reloadQueued = false;
  bool _refreshAfterDialog = false;

  /// 서버에 읽음으로 알린 마지막 메시지 ID입니다. 같은 값을 반복해서 보내지 않습니다.
  int _markedRead = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seenRevision = widget.sync?.revision;
    widget.sync?.addListener(_onSync);
    _resume();
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    try {
      final draft = await widget.draftStore?.read();
      if (!mounted) return;
      setState(() {
        _pendingMessage = draft;
        _restoring = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = '전송 대기를 복구하지 못했습니다. 대화를 다시 열어 주세요.';
        });
      }
    }
  }

  Future<void> _cancelDraft(FriendChatDraft draft) async {
    setState(() => _sending = true);
    try {
      await widget.draftStore?.remove(draft.id);
      if (mounted) {
        setState(() {
          _pendingMessage = null;
          _sendError = null;
        });
      }
    } catch (_) {
      _showError('전송 대기를 지우지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  int? _seenRevision;

  /// 실시간 연결이 살아 있으면 가끔만, 끊겨 있으면 4초마다 확인합니다.
  Duration get _pollInterval => widget.sync?.connected == true
      ? const Duration(seconds: 20)
      : const Duration(seconds: 4);

  void _resume() {
    _poll?.cancel();
    unawaited(_load());
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) {
      if (widget.peer != null || ModalRoute.of(context)?.isCurrent != false) {
        unawaited(_load());
      }
    });
  }

  void _onSync() {
    final sync = widget.sync;
    if (sync == null || !mounted) return;
    if (_seenRevision != sync.revision) {
      _seenRevision = sync.revision;
      if (widget.peer != null || ModalRoute.of(context)?.isCurrent != false) {
        unawaited(_load());
      }
    }
    if (_poll != null) _schedulePoll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state != AppLifecycleState.inactive) {
      _poll?.cancel();
    }
  }

  /// 대화 목록에 함께 보여줄 단톡·크루 대화방을 불러옵니다. 실패하면 1:1 대화만 보여줍니다.
  Future<void> _loadRooms() async {
    final rooms = widget.rooms;
    if (rooms == null || _loadingRooms || !mounted) return;
    _loadingRooms = true;
    try {
      final list = await rooms.rooms();
      if (mounted) setState(() => _roomList = list);
    } catch (_) {
    } finally {
      _loadingRooms = false;
    }
  }

  Future<void> _load({bool older = false}) async {
    if (!mounted) return;
    if (widget.peer == null && !older) unawaited(_loadRooms());
    if (_loading) {
      if (!older) _reloadQueued = true;
      return;
    }
    _loading = true;
    try {
      final peer = widget.peer;
      final firstPage = await widget.service.load(
        peer: peer,
        before: older ? _rows.last['id'] as int : null,
      );
      final page = [...firstPage];
      var lastPageSize = page.length;
      if (!older && peer != null && _rows.length >= 50) {
        final oldest = _rows.last['id'] as int;
        while (lastPageSize == 50 && (page.last['id'] as int) > oldest) {
          if (!mounted) return;
          final next = await widget.service.load(
            peer: peer,
            before: page.last['id'] as int,
          );
          lastPageSize = next.length;
          page.addAll(next);
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = older ? [..._rows, ...page] : page;
        _older = lastPageSize == 50;
        final replyId = _reply?['id'];
        for (final row in _rows) {
          if (row['id'] == replyId) _reply = row;
        }
        _loaded = true;
        _loadError = null;
      });
      if (widget.peer != null) _markRead();
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
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        unawaited(_load());
      }
    }
  }

  /// 대화방을 보고 있을 때 받은 메시지 중 가장 최근 것까지 읽음으로 표시합니다.
  void _markRead() {
    final peer = widget.peer;
    if (peer == null) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      _refreshAfterDialog = true;
      return;
    }
    _refreshAfterDialog = false;
    var latest = 0;
    for (final row in _rows) {
      final id = row['id'];
      if (row['kind'] != 'deleted' &&
          row['sender_id'] != widget.service.ownerId &&
          id is int &&
          id > latest) {
        latest = id;
      }
    }
    if (latest <= _markedRead) return;
    _markedRead = latest;
    unawaited(
      widget.service.markRead(peer, latest).catchError((Object _) {
        // 실패하면 다음 새로고침 때 다시 알립니다.
        if (_markedRead == latest) _markedRead = 0;
      }),
    );
  }

  void _showError(String message) {
    if (mounted) setState(() => _sendError = message);
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (_sending || body.isEmpty) return;
    final replyTo = _reply?['id'] as int?;
    final previous = _pendingMessage;
    await _sendDraft(
      previous != null && previous.body == body && previous.replyTo == replyTo
          ? previous
          : FriendChatDraft(
              id: const Uuid().v4(),
              body: body,
              replyTo: replyTo,
            ),
    );
  }

  Future<void> _sendDraft(FriendChatDraft draft) async {
    final peer = widget.peer;
    if (_sending || peer == null || !mounted) return;
    setState(() {
      _sending = true;
      _sendError = null;
      _pendingMessage = draft;
    });
    try {
      await widget.draftStore?.save(draft);
      await widget.service.sendContent(peer, draft);
      await widget.draftStore?.remove(draft.id);
      if (!mounted) return;
      setState(() {
        _pendingMessage = null;
        if (_reply?['id'] == draft.replyTo) _reply = null;
      });
      if (_input.text.trim() == draft.body) _input.clear();
      await _load();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('메시지를 보내지 못했습니다. 친구 관계와 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('갤러리 사진'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.directions_run_rounded),
              title: const Text('기록 자랑하기'),
              onTap: () => Navigator.pop(context, 'run'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null || _sending) return;
    try {
      final replyTo = _reply?['id'] as int?;
      if (choice == 'photo') {
        final photo = await pickFriendChatPhoto(context);
        if (photo == null || !mounted) return;
        await _sendDraft(
          FriendChatDraft(
            id: const Uuid().v4(),
            photo: base64Encode(photo),
            replyTo: replyTo,
          ),
        );
      } else {
        final id = await pickFriendChatRun(context, widget.service.client);
        if (id == null || !mounted) return;
        await _sendDraft(
          FriendChatDraft(id: const Uuid().v4(), runId: id, replyTo: replyTo),
        );
      }
    } on FriendChatPhotoException catch (error) {
      _showError(error.message);
    } on AuthException {
      _showError('계정이 변경되었습니다. 다시 로그인해 주세요.');
    } finally {
      if (mounted && _refreshAfterDialog) _markRead();
    }
  }

  Future<void> _messageActions(Map<String, dynamic> row) async {
    final mine = row['sender_id'] == widget.service.ownerId;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('답장'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            if (row['kind'] == null || row['kind'] == 'text')
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('복사'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('신고'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('삭제'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (_refreshAfterDialog) _markRead();
    switch (action) {
      case 'reply':
        final current = _rows
            .where((item) => item['id'] == row['id'])
            .firstOrNull;
        if (current != null && current['kind'] != 'deleted') {
          setState(() => _reply = current);
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: row['body'] as String));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('메시지를 복사했습니다.')));
        }
      case 'report':
        final reason = await moderationReason(
          context,
          '메시지 신고',
          explanation:
              '신고한 메시지와 직전 세 메시지의 텍스트가 운영자에게 전달됩니다. 사진을 신고하면 해당 사진도 포함됩니다.',
        );
        if (!mounted || reason == null) return;
        try {
          await widget.service.report(row['id'] as int, reason);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
          }
        } catch (_) {
          _showError('신고하지 못했습니다. 연결과 메시지 상태를 확인해 주세요.');
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('메시지 삭제'),
            content: const Text('이 메시지를 두 사람의 대화에서 삭제할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (_refreshAfterDialog) _markRead();
        if (confirmed != true) return;
        try {
          await widget.service.delete(widget.peer!, row['id'] as int);
          await _load();
        } catch (_) {
          _showError('메시지를 삭제하지 못했습니다. 다시 시도해 주세요.');
        }
    }
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_onSync);
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
              ? const StatusView.loading()
              : _rows.isEmpty
              ? const StatusView.empty(
                  icon: Icons.chat_bubble_outline_rounded,
                  message: '아직 메시지가 없습니다.',
                )
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
                    // 보낸 사람이 착용한 말풍선 색을 씁니다(내 것도 서버에서 받아 씁니다).
                    final sender = row['sender_id'] as String?;
                    return ListenableBuilder(
                      listenable: BadgeDirectory.instance,
                      builder: (context, _) => ChatMessageBubble(
                        bubble: sender == null
                            ? null
                            : BadgeDirectory.instance.user(sender)?.chatBubble,
                        key: ValueKey(row['id']),
                        body: row['body'] as String,
                        replyPreview: row['reply_preview'] as String?,
                        onLongPress: row['kind'] == 'deleted'
                            ? null
                            : () => _messageActions(row),
                        content: switch (row['kind']) {
                          'photo' => FriendChatPhoto(
                            load: () => widget.service.photo(
                              widget.peer!,
                              row['id'] as int,
                            ),
                          ),
                          'run' => FriendChatRunCard(
                            summary: row['run_summary'] as Map,
                            mine: row['sender_id'] == widget.service.ownerId,
                          ),
                          _ => null,
                        },
                        nickname: widget.nickname ?? '',
                        mine: row['sender_id'] == widget.service.ownerId,
                        sentAt: time,
                        showDay:
                            time != null &&
                            (previous == null ||
                                !_sameDay(time, _sentAt(previous))),
                        showAvatar: !_sameGroup(row, previous),
                        showTime: !_sameGroup(row, next),
                        // 상대가 아직 읽지 않은 내 메시지에는 카카오톡처럼 '1'을 붙입니다.
                        unread: row['read'] == false,
                      ),
                    );
                  },
                ),
        ),
        if (_sendError case final error?) Text(error),
        if (_pendingMessage case final draft? when !_sending)
          ListTile(
            title: Text(
              draft.body ?? (draft.photo != null ? '전송 대기 사진' : '전송 대기 기록'),
            ),
            leading: IconButton(
              tooltip: '전송 취소',
              onPressed: () => _cancelDraft(draft),
              icon: const Icon(Icons.close_rounded),
            ),
            trailing: TextButton(
              onPressed: () => _sendDraft(draft),
              child: const Text('다시 보내기'),
            ),
          ),
        if (_reply case final reply?)
          ListTile(
            dense: true,
            leading: const Icon(Icons.reply_rounded),
            title: const Text('답장'),
            subtitle: Text(
              reply['body'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '답장 취소',
              onPressed: () => setState(() => _reply = null),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ChatComposer(
          controller: _input,
          sending: _sending,
          canSend: _loadError == null && !_restoring && _pendingMessage == null,
          onSend: _send,
          onAttach: _attach,
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
            if (widget.peer case final peer?) UserTitle(userId: peer),
          ],
        ),
      ),
      body: SafeArea(top: false, child: content),
    );
  }

  Widget _buildConversationList() {
    if (!_loaded) return const StatusView.loading();
    if (_loadError case final error?) {
      return ChatListPlaceholder(message: error, onRetry: _load);
    }
    if (_rows.isEmpty && _roomList.isEmpty) {
      return const ChatListPlaceholder(
        message: '오른쪽 위 버튼으로 친구나 크루원과 대화를 시작해 보세요.',
      );
    }
    // 1:1 대화와 단톡·크루 대화방을 최근 메시지 순으로 섞어 보여줍니다.
    final entries = <Object>[..._rows, ..._roomList]
      ..sort((a, b) {
        DateTime? at(Object item) => item is ChatRoomSummary
            ? item.lastAt
            : _sentAt(item as Map<String, dynamic>);
        final x = at(a), y = at(b);
        if (x == null || y == null) return x == null ? 1 : -1;
        return y.compareTo(x);
      });
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          if (entry is ChatRoomSummary) {
            return ChatConversationTile(
              key: ValueKey('room-${entry.roomId}'),
              nickname: entry.title,
              memberCount: entry.memberCount,
              groupIcon: entry.isCrew
                  ? entry.crewIcon?.icon ?? Icons.groups
                  : Icons.forum_outlined,
              groupColor: entry.crewIcon?.color,
              preview: entry.lastBody ?? '대화방이 만들어졌어요.',
              sentAt: entry.lastAt,
              unread: entry.unread,
              onTap: () async {
                await openChatRoom(
                  context,
                  widget.rooms!,
                  entry.roomId,
                  sync: widget.sync,
                );
                if (mounted) unawaited(_load());
                unawaited(widget.sync?.refresh());
              },
            );
          }
          final row = entry as Map<String, dynamic>;
          final nickname = row['nickname'] as String;
          final peer = row['peer_id'] as String;
          return ChatConversationTile(
            key: ValueKey(peer),
            peerId: peer,
            nickname: nickname,
            preview: row['body'] as String,
            sentAt: _sentAt(row),
            unread: (row['unread'] as num?)?.toInt() ?? 0,
            onTap: () async {
              await openFriendChat(
                context,
                widget.service.client,
                peer,
                nickname,
                sync: widget.sync,
              );
              // 대화방에서 읽은 메시지 수를 바로 반영합니다.
              if (mounted) unawaited(_load());
              unawaited(widget.sync?.refresh());
            },
          );
        },
      ),
    );
  }
}
