import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/chat/chat_rooms.dart';
import 'package:runquest/features/chat/chat_wallpaper.dart';

class _MemoryWallpapers {
  final values = <String, String>{};
  final deleted = <String>[];
  var photos = 0;

  ChatWallpaperStore store() => ChatWallpaperStore(
    read: (key) async => values[key],
    write: (key, value) async =>
        value == null ? values.remove(key) : values[key] = value,
    savePhoto: (bytes) async => '/photos/${++photos}.jpg',
    deletePhoto: (photo) async => deleted.add(photo),
  );
}

class _Rooms implements ChatRoomService {
  @override
  String? get ownerId => 'me';

  @override
  Future<RoomPage> read(String roomId, {int? before}) async =>
      RoomPage.fromJson({
        'room': {'room_id': roomId, 'kind': 'crew', 'title': '아침런'},
        'members': [
          {'user_id': 'me', 'nickname': '나'},
        ],
        'messages': [
          {
            'id': 1,
            'sender_id': 'me',
            'nickname': '나',
            'body': '안녕',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
            'unread': 0,
          },
        ],
      });

  @override
  Future<void> markRead(String roomId, int lastId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('방마다 배경을 정하고, 모든 대화방 배경은 따로 정하지 않은 방에 씁니다', () async {
    final memory = _MemoryWallpapers();
    final store = memory.store();
    expect(await store.load('me', 'room:a'), isNull);

    await store.save(
      'me',
      'room:a',
      const ChatWallpaper.preset(ChatWallpaperPreset.mint),
      everywhere: true,
    );
    expect(
      await store.load('me', 'room:b'),
      const ChatWallpaper.preset(ChatWallpaperPreset.mint),
    );

    // 한 방만 내 사진으로 바꾸면 그 방만 바뀝니다.
    final photo = await store.keepPhoto(Uint8List(3));
    await store.save('me', 'room:b', ChatWallpaper.photo(photo));
    expect(await store.load('me', 'room:b'), ChatWallpaper.photo(photo));
    expect(
      await store.load('me', 'room:a'),
      const ChatWallpaper.preset(ChatWallpaperPreset.mint),
    );
    // 다른 계정에는 보이지 않습니다.
    expect(await store.load('other', 'room:b'), isNull);

    // 기본으로 되돌리면 모든 대화방 배경을 쓰고, 안 쓰는 사진 파일은 지웁니다.
    await store.save('me', 'room:b', null);
    expect(
      await store.load('me', 'room:b'),
      const ChatWallpaper.preset(ChatWallpaperPreset.mint),
    );
    expect(memory.deleted, [photo]);
    expect(ChatWallpaper.decode('preset:없는배경'), isNull);
  });

  testWidgets('대화방에서 기본 배경을 고르고 기본으로 되돌립니다', (tester) async {
    final memory = _MemoryWallpapers();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatRoomView(
          service: _Rooms(),
          roomId: 'r1',
          wallpaperStore: memory.store(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-wallpaper')), findsNothing);

    await tester.tap(find.byTooltip('대화방 배경'));
    await tester.pumpAndSettle();
    expect(find.text('대화방 배경'), findsOneWidget);
    expect(find.text('내 사진'), findsOneWidget);
    for (final preset in ChatWallpaperPreset.values) {
      expect(find.text(preset.label), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('wallpaper-mint')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-wallpaper')), findsOneWidget);
    expect(memory.values, {'chat-wallpaper:me:room:r1': 'preset:mint'});
    expect(find.text('안녕'), findsOneWidget);

    await tester.tap(find.byTooltip('대화방 배경'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wallpaper-default')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-wallpaper')), findsNothing);
    expect(memory.values, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('내 사진을 골라 모든 대화방 배경으로 씁니다', (tester) async {
    final memory = _MemoryWallpapers();
    final controller = ChatWallpaperController(
      owner: 'me',
      room: 'friend:f1',
      store: memory.store(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => controller.choose(
              context,
              pickPhoto: () async => Uint8List.fromList([1, 2, 3]),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    // 시험 화면이 작아 창 안에서 내려가며 누릅니다.
    await tester.ensureVisible(
      find.byKey(const ValueKey('wallpaper-everywhere')),
    );
    await tester.tap(find.byKey(const ValueKey('wallpaper-everywhere')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('wallpaper-photo')));
    await tester.tap(find.byKey(const ValueKey('wallpaper-photo')));
    await tester.pumpAndSettle();
    expect(controller.value, const ChatWallpaper.photo('/photos/1.jpg'));
    expect(memory.values, {'chat-wallpaper:me:*': 'photo:/photos/1.jpg'});
    controller.dispose();
  });
}
