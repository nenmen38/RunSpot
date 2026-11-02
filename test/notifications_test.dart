import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_post_loader_screen.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/notifications/data/notification_service.dart';
import 'package:runquest/features/notifications/models/app_notification.dart';
import 'package:runquest/features/notifications/notification_controller.dart';
import 'package:runquest/features/notifications/widgets/notification_bell.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_fakes.dart';
import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';

Map<String, dynamic> notificationJson(
  String id, {
  String kind = 'comment',
  String createdAt = '2026-10-28T01:00:00.000000+00:00',
  bool read = false,
}) => {
  'id': id,
  'kind': kind,
  'post_id': 'post$id',
  'post_title': '한강 코스',
  'nickname': '러너$id',
  'comment': kind == 'comment' ? '같이 뛰어요' : null,
  'created_at': createdAt,
  'read': read,
};

class FakeNotificationService implements NotificationService {
  bool owner = true;
  int unread = 0;
  List<Map<String, dynamic>> rows = [];
  Object? loadError;
  final marked = <DateTime>[];
  int countCalls = 0;

  @override
  bool get isCurrentOwner => owner;

  @override
  Future<int> unreadCount() async {
    countCalls++;
    return unread;
  }

  @override
  Future<List<AppNotification>> load() async {
    if (loadError != null) throw loadError!;
    return rows.map(AppNotification.fromJson).toList();
  }

  final responses = <(String, bool)>[];
  Object? respondError;
  @override
  Future<void> respondToInvite(String groupId, {required bool accept}) async {
    responses.add((groupId, accept));
    if (respondError != null) throw respondError!;
    rows = [
      for (final row in rows)
        row['group_id'] == groupId
            ? {
                ...row,
                'invite_status': accept ? 'accepted' : 'declined',
                'can_respond': false,
              }
            : row,
    ];
  }

  @override
  Future<void> markRead(DateTime seenUntil) async {
    marked.add(seenUntil);
    unread = 0;
  }
}

void main() {
  test('알림창을 열면 보여준 가장 최근 알림 시각까지 읽음 처리합니다', () async {
    final service = FakeNotificationService()
      ..unread = 2
      ..rows = [
        notificationJson('2', createdAt: '2026-10-28T02:00:00.000000+00:00'),
        notificationJson('1', kind: 'like'),
        notificationJson(
          '0',
          createdAt: '2026-10-28T03:00:00.000000+00:00',
          read: true,
        ),
      ];
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    await controller.refreshCount();
    expect(controller.unreadCount, 2);
    await controller.open();
    expect(service.marked, [DateTime.parse('2026-10-28T02:00:00Z')]);
    expect(controller.unreadCount, 0);
    expect(controller.items, hasLength(3));
    expect(controller.items[1].message, '러너1님이 내 글을 좋아해요.');
    expect(controller.items[0].message, '러너2님이 댓글을 남겼어요: 같이 뛰어요');
  });

  test('모두 읽은 알림은 다시 읽음 처리하지 않고 실패는 안내합니다', () async {
    final service = FakeNotificationService()
      ..rows = [notificationJson('1', read: true)];
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    await controller.open();
    expect(service.marked, isEmpty);
    service.loadError = const PostgrestException(
      message: 'x',
      code: 'PGRST202',
    );
    await controller.open();
    expect(controller.error, contains('서버 업데이트'));
    expect(controller.loading, isFalse);
  });

  testWidgets('홈 화면이 보일 때만 알림 수를 주기적으로 확인합니다', (tester) async {
    final service = FakeNotificationService()..unread = 1;
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    controller.setActive(true);
    await tester.pump();
    expect(controller.unreadCount, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(service.countCalls, 3);
    controller.setActive(false);
    await tester.pump(const Duration(minutes: 5));
    expect(service.countCalls, 3);
  });

  testWidgets('확성기를 눌러야 알림창이 열리고 알림을 누르면 글을 엽니다', (tester) async {
    final service = FakeNotificationService()
      ..unread = 1
      ..rows = [notificationJson('1')];
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBell(
            controller: controller,
            onOpenPost: opened.add,
          ),
        ),
      ),
    );
    await controller.refreshCount();
    await tester.pump();
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('알림'), findsNothing);

    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('러너1님이 댓글을 남겼어요: 같이 뛰어요'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.text('러너1님이 댓글을 남겼어요: 같이 뛰어요'));
    await tester.pumpAndSettle();
    expect(opened, ['post1']);
    expect(find.text('알림'), findsNothing);
  });

  testWidgets('알림이 없으면 빈 안내를 보여줍니다', (tester) async {
    final controller = NotificationController(FakeNotificationService());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBell(controller: controller, onOpenPost: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 알림이 없어요'), findsOneWidget);
  });

  testWidgets('알림에서 연 글을 불러오고 볼 수 없는 글은 안내합니다', (tester) async {
    final service = FakeBoardService();
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostLoaderScreen(service: service, postId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.loadedPosts, ['p1']);
    expect(service.loads, isEmpty);
    expect(find.text('제목p1'), findsOneWidget);

    service.onLoadPost = (_) => Future.error(
      const PostgrestException(message: '삭제되었거나 볼 수 없는 글입니다.', code: 'P0001'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostLoaderScreen(
          key: const ValueKey('gone'),
          service: service,
          postId: 'gone',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('삭제되었거나 볼 수 없는 글입니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('홈 화면 오른쪽 위에 확성기 버튼을 두고 알림에서 글을 엽니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    addTearDown(location.updates.close);
    final service = FakeNotificationService()
      ..unread = 3
      ..rows = [notificationJson('7', kind: 'like')];
    final notifications = NotificationController(service);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: map,
            mapBridgeFactory: FakeMapBridge.new,
            notificationController: notifications,
            onOpenPost: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bell = find.byIcon(Icons.campaign_outlined);
    expect(bell, findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final center = tester.getCenter(bell);
    expect(center.dx, greaterThan(390 - 60));
    expect(center.dy, lessThan(80));

    await tester.tap(bell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('러너7님이 내 글을 좋아해요.'));
    await tester.pumpAndSettle();
    expect(opened, ['post7']);
    expect(find.text('3'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    notifications.dispose();
    map.dispose();
    history.dispose();
  });

  testWidgets('홈 초대 배너는 읽음 처리 없이 표시되고 수락 뒤 사라집니다', (tester) async {
    final service = FakeNotificationService()
      ..unread = 1
      ..rows = [_inviteJson('group')];
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupInviteBanner(controller: controller, onOpenPost: (_) {}),
        ),
      ),
    );
    await controller.refreshCount();
    await tester.pump();
    expect(find.text('방장님이 함께 달리기에 초대했어요.'), findsOneWidget);
    expect(service.marked, isEmpty);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수락'));
    await tester.pumpAndSettle();
    expect(service.responses, [('group', true)]);
    expect(controller.pendingInvites, isEmpty);
    expect(find.textContaining('참여했어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이미 읽은 대기 초대도 표시하고 취소·계정 변경 시 배너를 지웁니다', (tester) async {
    final service = FakeNotificationService()
      ..rows = [
        {..._inviteJson('group'), 'read': true},
      ];
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupInviteBanner(controller: controller, onOpenPost: (_) {}),
        ),
      ),
    );
    await controller.refreshCount();
    await tester.pump();
    expect(find.text('방장님이 함께 달리기에 초대했어요.'), findsOneWidget);
    service.rows = [
      {
        ..._inviteJson('group'),
        'can_respond': false,
        'invite_status': 'cancelled',
      },
    ];
    await controller.refreshCount();
    await tester.pump();
    expect(controller.pendingInvites, isEmpty);
    service.unread = 1;
    service.rows = [_inviteJson('group')];
    await controller.refreshCount();
    service.owner = false;
    await controller.refreshCount();
    await tester.pump();
    expect(find.text('방장님이 함께 달리기에 초대했어요.'), findsNothing);
    expect(controller.pendingInvites, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('함께 달리기 초대 알림에서 수락하면 참여하고 버튼이 사라집니다', (tester) async {
    final service = FakeNotificationService()
      ..unread = 1
      ..rows = [_inviteJson('g1'), notificationJson('2', kind: 'like')];
    var groupRefreshes = 0;
    final controller = NotificationController(
      service,
      onGroupChanged: () => groupRefreshes++,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBell(controller: controller, onOpenPost: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    expect(find.text('방장님이 함께 달리기에 초대했어요.'), findsOneWidget);
    expect(find.text('수락'), findsOneWidget);
    expect(find.text('거절'), findsOneWidget);

    await tester.tap(find.text('수락'));
    await tester.pumpAndSettle();
    expect(service.responses.single, ('g1', true));
    expect(groupRefreshes, 1);
    expect(find.text('수락'), findsNothing);
    expect(find.textContaining('참여했어요'), findsOneWidget);
    // 초대 알림은 눌러도 창이 닫히지 않습니다.
    await tester.tap(find.text('방장님이 함께 달리기에 초대했어요.'));
    await tester.pumpAndSettle();
    expect(find.text('알림'), findsOneWidget);
  });

  testWidgets('초대 거절과 응답 실패를 알림창에 보여줍니다', (tester) async {
    final service = FakeNotificationService()
      ..rows = [_inviteJson('g1')]
      ..respondError = const PostgrestException(
        message: '대기 중인 초대만 응답할 수 있습니다.',
        code: 'P0001',
      );
    final controller = NotificationController(service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBell(controller: controller, onOpenPost: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수락'));
    await tester.pumpAndSettle();
    expect(find.text('대기 중인 초대만 응답할 수 있습니다.'), findsOneWidget);

    service.respondError = null;
    await tester.tap(find.text('거절'));
    await tester.pumpAndSettle();
    expect(service.responses.last, ('g1', false));
    expect(find.textContaining('거절했어요'), findsOneWidget);
    expect(find.text('대기 중인 초대만 응답할 수 있습니다.'), findsNothing);
  });
}

Map<String, dynamic> _inviteJson(String groupId) => {
  'id': 'n-$groupId',
  'kind': 'group_invite',
  'post_id': null,
  'post_title': null,
  'group_id': groupId,
  'invite_status': 'invited',
  'can_respond': true,
  'nickname': '방장',
  'comment': null,
  'created_at': '2026-11-02T01:00:00.000000+00:00',
  'read': false,
};
