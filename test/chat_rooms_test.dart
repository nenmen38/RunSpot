import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/chat/chat_rooms.dart';
import 'package:runquest/features/chat/friend_chat_content.dart';
import 'package:runquest/features/chat/new_chat_screen.dart';
import 'package:runquest/features/crew/crew_controller.dart';
import 'package:runquest/features/crew/models/crew.dart';
import 'package:runquest/features/crew/widgets/crew_widgets.dart';

import 'support/crew_fakes.dart';

class _Rooms implements ChatRoomService {
  @override
  String? get ownerId => 'me';
  final sent = <String>[];
  final marked = <int>[];
  RoomPage page = RoomPage.fromJson({
    'room': {'room_id': 'r1', 'kind': 'group', 'title': '주말 런'},
    'members': [
      {'user_id': 'me', 'nickname': '나'},
      {'user_id': 'a', 'nickname': '러너A'},
      {'user_id': 'b', 'nickname': '러너B'},
    ],
    'messages': [
      {
        'id': 3,
        'sender_id': 'b',
        'nickname': '러너B',
        'body': '사진',
        'kind': 'photo',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'unread': 0,
      },
      {
        'id': 2,
        'sender_id': 'me',
        'nickname': '나',
        'body': '토요일 7시?',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'unread': 2,
      },
      {
        'id': 1,
        'sender_id': 'a',
        'nickname': '러너A',
        'body': '같이 뛰어요',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'unread': 0,
      },
    ],
  });

  @override
  Future<List<ChatRoomSummary>> rooms() async => const [];
  @override
  Future<String> create(List<String> memberIds, {String? name}) async => 'r1';
  @override
  Future<String> crewRoom(String crewId) async => 'crew-room';
  @override
  Future<RoomPage> read(String roomId, {int? before}) async => page;
  @override
  Future<void> send(String roomId, String body, String requestId) async =>
      sent.add(body);
  @override
  Future<void> markRead(String roomId, int lastId) async => marked.add(lastId);
  @override
  Future<void> leave(String roomId) async {}

  @override
  Future<void> sendPhoto(String roomId, String jpeg, String requestId) async =>
      sent.add('photo');

  @override
  Future<Uint8List> photo(String roomId, int messageId) async =>
      Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
}

void main() {
  testWidgets('단톡에서 다른 사람 이름과 안 읽은 사람 수를 보여주고 메시지를 보냅니다', (tester) async {
    final rooms = _Rooms();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatRoomView(service: rooms, roomId: 'r1'),
      ),
    );
    await tester.pump();
    expect(find.text('주말 런 (3)'), findsOneWidget);
    expect(find.text('러너A'), findsOneWidget);
    // 내 메시지를 아직 두 명이 안 읽었습니다.
    expect(find.text('2'), findsOneWidget);
    expect(rooms.marked, [3]);
    // 사진 메시지는 사진으로 보여주고, 사진 첨부 버튼이 있습니다.
    expect(find.byType(FriendChatPhoto), findsOneWidget);
    expect(find.byTooltip('첨부'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '좋아요');
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pump();
    expect(rooms.sent, ['좋아요']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('새 대화에서 친구와 크루원을 고르고 크루 목록은 펼치고 접습니다', (tester) async {
    NewChatSelection? picked;
    final crew = Crew.fromJson(FakeCrewService.crewJson());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<NewChatSelection>(
                MaterialPageRoute(
                  builder: (_) => NewChatScreen(
                    friends: const [(id: 'f1', nickname: '친구1')],
                    crews: [crew],
                    ownerId: 'me',
                  ),
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('대화할 사람을 골라 주세요'), findsOneWidget);
    // 크루원은 접혀 있다가 크루 이름을 누르면 보입니다. 나는 목록에 없습니다.
    expect(find.text('러너2'), findsNothing);
    await tester.tap(find.text('새벽런'));
    await tester.pumpAndSettle();
    expect(find.text('러너2'), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-me')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-f1')));
    await tester.tap(find.byKey(const ValueKey('pick-2')));
    await tester.pumpAndSettle();
    expect(find.text('단톡 만들기 (2명)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('room-name')), '주말 런');
    await tester.tap(find.text('단톡 만들기 (2명)'));
    await tester.pumpAndSettle();
    expect(picked!.members, {'f1': '친구1', '2': '러너2'});
    expect(picked!.name, '주말 런');
  });

  testWidgets('크루 화면의 설명 옆 버튼으로 크루 대화방에 들어갑니다', (tester) async {
    final controller = CrewController(
      FakeCrewService()..crews = [FakeCrewService.crewJson()],
    );
    await controller.refresh();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrewTab(
            controller: controller,
            onOpenChat: (crew) async => opened.add(crew.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('크루 대화방'));
    expect(opened, ['crew-1']);
    controller.dispose();
  });
}
