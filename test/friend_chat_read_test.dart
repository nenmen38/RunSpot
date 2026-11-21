import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/chat/chat_sync.dart';
import 'package:runquest/features/chat/friend_chat.dart';
import 'package:runquest/features/chat/friend_chat_content.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Chat extends FriendChatService {
  _Chat()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  String? get ownerId => 'me';
  List<Map<String, dynamic>> room = [];
  List<Map<String, dynamic>> list = [];
  final marked = <(String, int)>[];

  @override
  Future<List<Map<String, dynamic>>> load({String? peer, int? before}) async {
    loads++;
    return peer == null ? list : room;
  }

  @override
  Future<void> markRead(String peer, int lastId) async =>
      marked.add((peer, lastId));

  final sent = <FriendChatDraft>[];

  @override
  Future<void> sendContent(String peer, FriendChatDraft draft) async {
    sent.add(draft);
  }

  @override
  Future<void> delete(String peer, int id) async {
    room = [
      for (final row in room)
        if (row['id'] == id)
          {...row, 'body': '삭제된 메시지입니다.', 'kind': 'deleted'}
        else
          row,
    ];
  }

  int total = 0;
  int loads = 0;
  void Function()? changed;
  void Function(bool)? connection;
  @override
  Future<int> unreadTotal() async => total;

  @override
  void Function() listen({
    required void Function() onChanged,
    required void Function(bool connected) onConnection,
  }) {
    changed = onChanged;
    connection = onConnection;
    return () => changed = null;
  }
}

Map<String, dynamic> message(int id, String sender, {bool read = true}) => {
  'id': id,
  'sender_id': sender,
  'body': '메시지$id',
  'sent_at': DateTime.now().toUtc().toIso8601String(),
  'read': read,
};

void main() {
  testWidgets('거리 0m인 공유 기록은 평균 페이스 없이 표시합니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FriendChatRunCard(
            summary: {'distance_m': 0, 'duration_sec': 42},
            mine: false,
          ),
        ),
      ),
    );

    expect(find.text('0.00 km · 00:42 · 평균 페이스 —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('메시지에 답장하고 내 메시지를 두 사람의 대화에서 삭제합니다', (tester) async {
    final chat = _Chat()..room = [message(2, 'me'), message(1, 'friend')];
    await tester.pumpWidget(
      MaterialApp(
        home: FriendChatView(service: chat, peer: 'friend', nickname: '친구'),
      ),
    );
    await tester.pump();
    await tester.longPress(find.text('메시지1'));
    await tester.pumpAndSettle();
    expect(find.text('복사'), findsOneWidget);
    expect(find.text('삭제'), findsNothing);
    await tester.tap(find.text('답장'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '답장 내용');
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    expect(chat.sent.single.body, '답장 내용');
    expect(chat.sent.single.replyTo, 1);

    await tester.longPress(find.text('메시지2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('메시지2'), findsNothing);
    expect(find.text('삭제된 메시지입니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('공유된 달리기 기록을 요약 카드로 표시합니다', (tester) async {
    final chat = _Chat()
      ..room = [
        {
          ...message(1, 'friend'),
          'kind': 'run',
          'run_summary': {'distance_m': 5000, 'duration_sec': 1500},
        },
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: FriendChatView(service: chat, peer: 'friend', nickname: '친구'),
      ),
    );
    await tester.pump();
    expect(find.text('달리기 기록'), findsOneWidget);
    expect(find.textContaining('5.00 km'), findsOneWidget);
    expect(find.textContaining('5’00” /km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('상대가 안 읽은 내 메시지에만 1을 붙이고 받은 메시지는 읽음으로 알립니다', (tester) async {
    final chat = _Chat()
      ..room = [
        message(4, 'me', read: false),
        message(3, 'friend'),
        message(2, 'me'),
        message(1, 'friend'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: FriendChatView(service: chat, peer: 'friend', nickname: '친구'),
      ),
    );
    await tester.pump();
    expect(find.text('메시지4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('읽지 않음')), findsOneWidget);
    // 받은 메시지 중 가장 최근(3번)까지 한 번만 읽음으로 알립니다.
    expect(chat.marked, [('friend', 3)]);

    // 상대가 읽으면 다음 새로고침에서 1이 사라집니다.
    chat.room = [message(4, 'me'), ...chat.room.skip(1)];
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('1'), findsNothing);
    expect(chat.marked, [('friend', 3)]);

    // 새 메시지를 받으면 그 메시지까지 다시 읽음으로 알립니다.
    chat.room = [message(5, 'friend'), ...chat.room];
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(chat.marked.last, ('friend', 5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('대화 목록에 안 읽은 메시지 수를 보여줍니다', (tester) async {
    final chat = _Chat()
      ..list = [
        {
          'peer_id': 'a',
          'nickname': '러너A',
          'id': 9,
          'body': '내일 뛰어요',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
          'unread': 3,
        },
        {
          'peer_id': 'b',
          'nickname': '러너B',
          'id': 7,
          'body': '좋아요',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
          'unread': 0,
        },
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FriendChatView(service: chat)),
      ),
    );
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('안 읽은 메시지 3개')), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('실시간 신호가 오면 안 읽은 수를 다시 세고 열린 대화방을 바로 새로 불러옵니다', (tester) async {
    final chat = _Chat()
      ..total = 2
      ..room = [message(1, 'friend')];
    final sync = ChatSync(chat)..start();
    await tester.pumpWidget(
      MaterialApp(
        home: FriendChatView(
          service: chat,
          peer: 'friend',
          nickname: '친구',
          sync: sync,
        ),
      ),
    );
    await tester.pump();
    expect(sync.unreadTotal, 2);
    final before = chat.loads;

    // 실시간이 연결되면 4초마다 확인하지 않습니다.
    chat.connection!(true);
    await tester.pump();
    expect(sync.connected, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(chat.loads, before);

    // 새 메시지 신호를 받으면 기다리지 않고 바로 불러옵니다.
    chat
      ..total = 3
      ..room = [message(2, 'friend'), ...chat.room];
    chat.changed!();
    await tester.pump();
    await tester.pump();
    expect(chat.loads, before + 1);
    expect(find.text('메시지2'), findsOneWidget);
    expect(sync.unreadTotal, 3);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  test('메시지 알림은 대상이 친구 ID인 경우에만 화면 이동에 씁니다', () {
    const friend = '00000000-0000-0000-0000-000000000271';
    final destination = PushDestination.parse({
      'kind': 'friend_message',
      'target_id': friend,
      'recipient_id': 'me',
    }, 'me');
    expect(destination?.kind, 'friend_message');
    expect(destination?.targetId, friend);
    expect(
      PushDestination.parse({
        'kind': 'friend_message',
        'target_id': friend,
        'recipient_id': 'other',
      }, 'me'),
      isNull,
    );
  });
}
