import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../board/data/board_photo_service.dart';
import '../chat/chat_rooms.dart';
import '../chat/friend_chat.dart';
import '../chat/friend_chat_content.dart';
import '../run_share/data/run_share_service.dart';
import '../social/data/friend_service.dart';
import '../social/models/friend_entry.dart';
import 'character_profile_card.dart';

/// 카드를 보낼 수 있는 채팅 상대입니다(친구 1:1 또는 대화방).
@immutable
class ChatTarget {
  const ChatTarget({
    required this.id,
    required this.name,
    required this.isRoom,
  });

  final String id;
  final String name;
  final bool isRoom;
}

/// 프로필 카드를 내보내는 방법들입니다. 앱에서는 기기·서버를, 테스트에서는 가짜를 씁니다.
abstract interface class CharacterCardActions {
  /// 사진 앨범에 이미지로 저장합니다.
  Future<void> saveImage(Uint8List png);

  /// 기기의 공유 창(카카오톡·인스타그램 등)으로 보냅니다.
  Future<void> shareImage(Uint8List png, Rect origin);

  /// 채팅·게시판에 올릴 JPEG(1MB 이하)로 바꿉니다.
  Future<Uint8List> toJpeg(Uint8List png);

  Future<List<ChatTarget>> chatTargets();

  Future<void> sendToChat(ChatTarget target, Uint8List jpeg);

  /// 게시판 글쓰기 화면을 사진이 붙은 채로 엽니다.
  void openBoard(Uint8List jpeg);
}

class DeviceCharacterCardActions implements CharacterCardActions {
  DeviceCharacterCardActions({
    required this.client,
    required this.onOpenBoard,
    FriendService? friends,
    ChatRoomService? rooms,
    FriendChatService? chat,
  }) : _friends = friends ?? SupabaseFriendService(client),
       _rooms = rooms ?? SupabaseChatRoomService(client),
       _chat = chat ?? FriendChatService(client);

  final SupabaseClient client;
  final void Function(Uint8List jpeg) onOpenBoard;
  final FriendService _friends;
  final ChatRoomService _rooms;
  final FriendChatService _chat;

  @override
  Future<void> saveImage(Uint8List png) => Gal.putImageBytes(
    png,
    // 파일 이름에 확장자(.png)가 있어야 저장됩니다.
    name: 'ddimteo_runner_${DateTime.now().millisecondsSinceEpoch}.png',
  );

  @override
  Future<void> shareImage(Uint8List png, Rect origin) =>
      PlatformRunShareService().share(png, origin, isCurrentOwner: () => true);

  @override
  Future<Uint8List> toJpeg(Uint8List png) async {
    final jpeg = await encodeBoardPhoto(png);
    if (jpeg.length > 1024 * 1024) {
      throw const FriendChatPhotoException('카드 이미지가 너무 커서 보낼 수 없어요.');
    }
    return jpeg;
  }

  @override
  Future<List<ChatTarget>> chatTargets() async {
    final dashboard = await _friends.load();
    final rooms = await _rooms.rooms();
    return [
      for (final entry in dashboard.entries)
        if (entry.relation == FriendRelation.friend)
          ChatTarget(id: entry.userId, name: entry.nickname, isRoom: false),
      for (final room in rooms)
        ChatTarget(id: room.roomId, name: room.title, isRoom: true),
    ];
  }

  @override
  Future<void> sendToChat(ChatTarget target, Uint8List jpeg) async {
    final requestId = const Uuid().v4();
    final encoded = base64Encode(jpeg);
    if (target.isRoom) {
      await _rooms.sendPhoto(target.id, encoded, requestId);
    } else {
      await _chat.sendContent(
        target.id,
        FriendChatDraft(id: requestId, photo: encoded),
      );
    }
  }

  @override
  void openBoard(Uint8List jpeg) => onOpenBoard(jpeg);
}

/// 프로필 카드 공유 창을 엽니다.
Future<void> showCharacterCardSheet(
  BuildContext context, {
  required CharacterCardData data,
  required CharacterCardActions actions,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => CharacterCardSheet(data: data, actions: actions),
);

class CharacterCardSheet extends StatefulWidget {
  const CharacterCardSheet({
    required this.data,
    required this.actions,
    super.key,
  });

  final CharacterCardData data;
  final CharacterCardActions actions;

  @override
  State<CharacterCardSheet> createState() => _CharacterCardSheetState();
}

class _CharacterCardSheetState extends State<CharacterCardSheet> {
  final _card = GlobalKey();
  final _shareButton = GlobalKey();
  bool _busy = false;
  String? _message;
  Uint8List? _png;

  Future<Uint8List> _render() async =>
      _png ??= await renderCharacterCardPng(_card);

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    String? result;
    try {
      result = await action();
    } on GalException catch (error) {
      result = switch (error.type) {
        GalExceptionType.permissionDenied => '사진 저장 권한이 없어요. 설정에서 허용해 주세요.',
        GalExceptionType.notEnoughSpace => '저장 공간이 부족해요.',
        _ => '이미지를 저장하지 못했어요.',
      };
    } on FriendChatPhotoException catch (error) {
      result = error.message;
    } catch (_) {
      result = '처리하지 못했어요. 잠시 뒤에 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result;
    });
  }

  Future<void> _save() => _run(() async {
    await widget.actions.saveImage(await _render());
    return '갤러리에 저장했어요.';
  });

  Future<void> _share() => _run(() async {
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    await widget.actions.shareImage(await _render(), origin);
    return null;
  });

  Future<void> _chat() async {
    final target = await showModalBottomSheet<ChatTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ChatTargetPicker(actions: widget.actions),
    );
    if (target == null || !mounted) return;
    await _run(() async {
      final jpeg = await widget.actions.toJpeg(await _render());
      await widget.actions.sendToChat(target, jpeg);
      return '${target.name}에게 카드를 보냈어요.';
    });
  }

  Future<void> _board() => _run(() async {
    final jpeg = await widget.actions.toJpeg(await _render());
    if (!mounted) return null;
    Navigator.of(context).pop();
    widget.actions.openBoard(jpeg);
    return null;
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '내 러너 프로필 카드',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          // 카드는 늘 320×400으로 그리고 화면에서는 폭에 맞춰 줄여 보여 줍니다.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: FittedBox(
                child: RepaintBoundary(
                  key: _card,
                  child: CharacterProfileCard(data: widget.data),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('card-save'),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('이미지 저장'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: _shareButton,
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('공유하기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('card-chat'),
                  onPressed: _busy ? null : _chat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('채팅으로 보내기'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('card-board'),
                  onPressed: _busy ? null : _board,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('게시판에 올리기'),
                ),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _message!,
                key: const ValueKey('card-message'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// 카드를 보낼 친구나 대화방을 고릅니다.
class _ChatTargetPicker extends StatefulWidget {
  const _ChatTargetPicker({required this.actions});

  final CharacterCardActions actions;

  @override
  State<_ChatTargetPicker> createState() => _ChatTargetPickerState();
}

class _ChatTargetPickerState extends State<_ChatTargetPicker> {
  List<ChatTarget>? _targets;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final targets = await widget.actions.chatTargets();
      if (mounted) setState(() => _targets = targets);
    } catch (_) {
      if (mounted) setState(() => _error = '친구와 대화방을 불러오지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final friends = [
      for (final target in targets ?? const <ChatTarget>[])
        if (!target.isRoom) target,
    ];
    final rooms = [
      for (final target in targets ?? const <ChatTarget>[])
        if (target.isRoom) target,
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '누구에게 보낼까요?',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!))
          else if (targets == null)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (targets.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text('보낼 친구나 대화방이 아직 없어요. 친구를 추가해 보세요.'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (friends.isNotEmpty) const _Header('친구'),
                  for (final target in friends)
                    ListTile(
                      key: ValueKey('target-${target.id}'),
                      leading: const Icon(Icons.person_outline),
                      title: Text(target.name),
                      onTap: () => Navigator.pop(context, target),
                    ),
                  if (rooms.isNotEmpty) const _Header('대화방'),
                  for (final target in rooms)
                    ListTile(
                      key: ValueKey('target-${target.id}'),
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(target.name),
                      onTap: () => Navigator.pop(context, target),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
