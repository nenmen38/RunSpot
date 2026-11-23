import 'friend_chat_content.dart';

import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/status_view.dart';
import '../../shared/widgets/skeleton.dart';
import '../crew/models/crew.dart';
import '../titles/badge_directory.dart';
import 'chat_room_style.dart';
import 'chat_sync.dart';
import 'chat_wallpaper.dart';

/// 대화 목록에 보여줄 단톡·크루 대화방 하나입니다.
class ChatRoomSummary {
  ChatRoomSummary.fromJson(Map<String, dynamic> json)
    : roomId = json['room_id'] as String,
      kind = json['kind'] as String,
      title = json['title'] as String? ?? '대화방',
      memberCount = (json['member_count'] as num?)?.toInt() ?? 0,
      crewIcon = json['crew_icon'] == null
          ? null
          : CrewIcon.fromCode(json['crew_icon']),
      lastBody = json['body'] as String?,
      lastAt = DateTime.tryParse(
        (json['sent_at'] ?? json['active_at']) as String? ?? '',
      )?.toLocal(),
      unread = (json['unread'] as num?)?.toInt() ?? 0;

  final String roomId;

  /// group(단톡) 또는 crew(크루 대화방)입니다.
  final String kind;
  final String title;
  final int memberCount;
  final CrewIcon? crewIcon;
  final String? lastBody;
  final DateTime? lastAt;
  final int unread;

  bool get isCrew => kind == 'crew';
}

class RoomMessage {
  RoomMessage.fromJson(Map<String, dynamic> json)
    : id = (json['id'] as num).toInt(),
      senderId = json['sender_id'] as String,
      nickname = json['nickname'] as String? ?? '알 수 없음',
      body = json['body'] as String,
      kind = json['kind'] as String? ?? 'text',
      sentAt = DateTime.tryParse(json['sent_at'] as String? ?? '')?.toLocal(),
      unread = (json['unread'] as num?)?.toInt() ?? 0;

  final int id;
  final String senderId;
  final String nickname;
  final String body;

  /// text 또는 photo입니다. 사진은 [ChatRoomService.photo]로 따로 받습니다.
  final String kind;
  final DateTime? sentAt;

  /// 이 메시지를 아직 안 읽은 사람 수입니다(보낸 사람 제외).
  final int unread;
}

class RoomPage {
  RoomPage.fromJson(Map<String, dynamic> json)
    : title = (json['room'] as Map?)?['title'] as String? ?? '대화방',
      kind = (json['room'] as Map?)?['kind'] as String? ?? 'group',
      members = [
        for (final row in json['members'] as List? ?? const [])
          (
            id: (row as Map)['user_id'] as String,
            nickname: row['nickname'] as String? ?? '알 수 없음',
          ),
      ],
      messages = [
        for (final row in json['messages'] as List? ?? const [])
          RoomMessage.fromJson(Map<String, dynamic>.from(row as Map)),
      ];

  final String title;
  final String kind;
  final List<({String id, String nickname})> members;

  /// 최신 메시지가 앞에 옵니다.
  final List<RoomMessage> messages;
}

abstract interface class ChatRoomService {
  String? get ownerId;
  Future<List<ChatRoomSummary>> rooms();

  /// 나 말고 [memberIds]와 단톡을 만들고 대화방 ID를 돌려줍니다.
  Future<String> create(List<String> memberIds, {String? name});

  /// 크루 대화방 ID입니다. 처음이면 서버가 만듭니다.
  Future<String> crewRoom(String crewId);
  Future<RoomPage> read(String roomId, {int? before});
  Future<void> send(String roomId, String body, String requestId);

  /// JPEG(base64)을 사진 메시지로 보냅니다.
  Future<void> sendPhoto(String roomId, String jpeg, String requestId);

  /// 사진 메시지의 사진입니다.
  Future<Uint8List> photo(String roomId, int messageId);
  Future<void> markRead(String roomId, int lastId);
  Future<void> leave(String roomId);
}

class SupabaseChatRoomService implements ChatRoomService {
  SupabaseChatRoomService(this.client) : ownerId = client.auth.currentUser?.id;
  final SupabaseClient client;
  @override
  final String? ownerId;

  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != ownerId) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .timeout(const Duration(seconds: 12));
    if (client.auth.currentUser?.id != ownerId) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return result;
  }

  @override
  Future<List<ChatRoomSummary>> rooms() async => [
    for (final row in await _call('my_chat_rooms', const {}) as List)
      ChatRoomSummary.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  @override
  Future<String> create(List<String> memberIds, {String? name}) async =>
      await _call('create_chat_room', {
        'member_ids': memberIds,
        'room_name': name,
      }) as String;

  @override
  Future<String> crewRoom(String crewId) async =>
      await _call('crew_chat_room', {'requested_crew': crewId}) as String;

  @override
  Future<RoomPage> read(String roomId, {int? before}) async =>
      RoomPage.fromJson(
        Map<String, dynamic>.from(
          await _call('chat_room_read', {'target': roomId, 'before_id': before})
              as Map,
        ),
      );

  @override
  Future<void> send(String roomId, String body, String requestId) async {
    await _call('chat_room_send', {
      'target': roomId,
      'message_body': body,
      'request_id': requestId,
    });
  }

  @override
  Future<void> markRead(String roomId, int lastId) async {
    await _call('chat_room_mark_read', {'target': roomId, 'last_id': lastId});
  }

  @override
  Future<void> sendPhoto(String roomId, String jpeg, String requestId) async {
    await _call('chat_room_send_photo', {
      'target': roomId,
      'jpeg': jpeg,
      'request_id': requestId,
    });
  }

  @override
  Future<Uint8List> photo(String roomId, int messageId) async {
    final encoded = await _call('chat_room_photo', {
      'target': roomId,
      'message_id': messageId,
    }) as String?;
    if (encoded == null) throw StateError('사진을 볼 수 없습니다.');
    return base64Decode(encoded.replaceAll('\n', ''));
  }

  @override
  Future<void> leave(String roomId) async {
    await _call('leave_chat_room', {'target': roomId});
  }
}

Future<void> openChatRoom(
  BuildContext context,
  ChatRoomService service,
  String roomId, {
  ChatSync? sync,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ChatRoomView(service: service, roomId: roomId, sync: sync),
  ),
);

/// 단톡·크루 대화방 화면입니다. 메시지 옆에 아직 안 읽은 사람 수를 보여줍니다.
class ChatRoomView extends StatefulWidget {
  const ChatRoomView({
    required this.service,
    required this.roomId,
    this.sync,
    this.wallpaperStore,
    super.key,
  });

  final ChatRoomService service;
  final String roomId;
  final ChatSync? sync;

  /// 대화방 배경을 저장하는 곳입니다. 없으면 기기 저장소를 씁니다.
  final ChatWallpaperStore? wallpaperStore;

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  RoomPage? _page;
  List<RoomMessage> _messages = [];
  bool _loading = false;
  bool _sending = false;
  String? _error;
  String? _sendError;
  ({String body, String id})? _pending;
  Timer? _poll;
  int? _seenRevision;
  int _markedRead = 0;
  late final _wallpaper = ChatWallpaperController(
    owner: widget.service.ownerId,
    room: 'room:${widget.roomId}',
    store: widget.wallpaperStore,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seenRevision = widget.sync?.revision;
    widget.sync?.addListener(_onSync);
    _resume();
  }

  Duration get _interval => widget.sync?.connected == true
      ? const Duration(seconds: 20)
      : const Duration(seconds: 4);

  void _resume() {
    unawaited(_load());
    _poll?.cancel();
    _poll = Timer.periodic(_interval, (_) {
      if (ModalRoute.of(context)?.isCurrent != false) unawaited(_load());
    });
  }

  void _onSync() {
    final sync = widget.sync;
    if (sync == null || !mounted || _seenRevision == sync.revision) return;
    _seenRevision = sync.revision;
    if (ModalRoute.of(context)?.isCurrent != false) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state != AppLifecycleState.inactive) {
      _poll?.cancel();
    }
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      final page = await widget.service.read(widget.roomId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _messages = page.messages;
        _error = null;
      });
      _markRead();
    } catch (_) {
      if (mounted) setState(() => _error = '대화방을 불러오지 못했습니다. 연결을 확인해 주세요.');
    } finally {
      _loading = false;
    }
  }

  void _markRead() {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final latest = _messages.isEmpty ? 0 : _messages.first.id;
    if (latest <= _markedRead) return;
    _markedRead = latest;
    unawaited(
      widget.service
          .markRead(widget.roomId, latest)
          .then((_) {
            unawaited(widget.sync?.refresh());
          })
          .catchError((Object _) {
            if (_markedRead == latest) _markedRead = 0;
          }),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final message = _pending != null && _pending!.body == text
        ? _pending!
        : (body: text, id: const Uuid().v4());
    _pending = message;
    try {
      await widget.service.send(widget.roomId, text, message.id);
      _pending = null;
      if (!mounted) return;
      if (_input.text.trim() == text) _input.clear();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _sendError = '메시지를 보내지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 갤러리에서 사진을 골라 대화방에 보냅니다. 1:1 대화와 같은 방식으로 줄여서 보냅니다.
  Future<void> _sendPhoto() async {
    if (_sending) return;
    try {
      final photo = await pickFriendChatPhoto(context);
      if (photo == null || !mounted) return;
      setState(() {
        _sending = true;
        _sendError = null;
      });
      await widget.service.sendPhoto(
        widget.roomId,
        base64Encode(photo),
        const Uuid().v4(),
      );
      if (mounted) await _load();
    } on FriendChatPhotoException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (_) {
      if (mounted) setState(() => _sendError = '사진을 보내지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('대화방에서 나갈까요?'),
        content: const Text('나가면 이 대화방의 메시지를 더 볼 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.leave(widget.roomId);
      unawaited(widget.sync?.refresh());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('대화방에서 나가지 못했습니다.')));
      }
    }
  }

  void _showMembers() {
    final page = _page;
    if (page == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('참여자 ${page.members.length}명')),
            for (final member in page.members)
              ListTile(
                leading: ChatAvatar(
                  nickname: member.nickname,
                  userId: member.id,
                  size: 34,
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(member.nickname)),
                    UserTitle(userId: member.id),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_onSync);
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _wallpaper.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  bool _sameGroup(RoomMessage a, RoomMessage? b) =>
      b != null &&
      a.senderId == b.senderId &&
      _sameDay(a.sentAt, b.sentAt) &&
      a.sentAt != null &&
      b.sentAt != null &&
      a.sentAt!.difference(b.sentAt!).abs() < const Duration(minutes: 2);

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final owner = widget.service.ownerId;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: Text(
          page == null ? '대화방' : '${page.title} (${page.members.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '대화방 배경',
            onPressed: () => _wallpaper.choose(context),
            icon: const Icon(Icons.wallpaper_outlined),
          ),
          IconButton(
            tooltip: '참여자 보기',
            onPressed: page == null ? null : _showMembers,
            icon: const Icon(Icons.people_outline),
          ),
          if (page?.kind == 'group')
            IconButton(
              tooltip: '대화방 나가기',
              onPressed: _leave,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: _wallpaper,
                builder: (context, wallpaper, child) => ChatWallpaperBackground(
                  wallpaper: wallpaper,
                  child: child!,
                ),
                child: page == null
                    ? (_error == null
                          ? const SkeletonList(layout: SkeletonLayout.chat)
                          : StatusView.error(message: _error!, onRetry: _load))
                    : _messages.isEmpty
                    ? const StatusView.empty(
                        icon: Icons.forum_outlined,
                        message: '첫 메시지를 보내 보세요.',
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final previous = index + 1 < _messages.length
                              ? _messages[index + 1]
                              : null;
                          final next = index > 0 ? _messages[index - 1] : null;
                          return ListenableBuilder(
                            key: ValueKey(message.id),
                            listenable: BadgeDirectory.instance,
                            builder: (context, _) => ChatMessageBubble(
                              senderId: message.senderId,
                              body: message.body,
                              nickname: message.nickname,
                              mine: message.senderId == owner,
                              sentAt: message.sentAt,
                              showDay:
                                  message.sentAt != null &&
                                  !_sameDay(message.sentAt, previous?.sentAt),
                              showAvatar: !_sameGroup(message, previous),
                              showTime: !_sameGroup(message, next),
                              unreadCount: message.unread,
                              showName: true,
                              content: message.kind == 'photo'
                                  ? FriendChatPhoto(
                                      load: () => widget.service.photo(
                                        widget.roomId,
                                        message.id,
                                      ),
                                    )
                                  : null,
                              bubble: BadgeDirectory.instance
                                  .user(message.senderId)
                                  ?.chatBubble,
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_sendError case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  error,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ChatComposer(
              controller: _input,
              sending: _sending,
              canSend: page != null,
              onSend: _send,
              onAttach: page == null ? null : _sendPhoto,
            ),
          ],
        ),
      ),
    );
  }
}
