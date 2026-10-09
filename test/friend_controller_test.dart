import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/friend_controller.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/friend_fakes.dart';

void main() {
  late FakeFriendService service;
  late FriendController controller;
  setUp(() {
    service = FakeFriendService();
    controller = FriendController(service);
  });
  tearDown(() => controller.dispose());

  test('목록을 친구와 받은 요청 및 보낸 요청으로 구분합니다', () async {
    service.entries = [
      friendEntry('1', FriendRelation.sent),
      friendEntry('2', FriendRelation.received),
      friendEntry('3', FriendRelation.friend),
    ];
    await controller.refresh();
    expect(controller.friends.single.userId, '3');
    expect(controller.received.single.userId, '2');
    expect(controller.sent.single.userId, '1');
    expect(() => controller.sent.clear(), throwsUnsupportedError);
  });

  test('이전 목록 응답은 최신 목록을 덮어쓰지 않습니다', () async {
    final old = Completer<FriendDashboard>();
    service.onLoad = () => old.future;
    final first = controller.refresh();
    service.onLoad = null;
    service.entries = [friendEntry('2', FriendRelation.friend)];
    await controller.refresh();
    old.complete(
      FriendDashboard(
        canInteract: true,
        entries: [friendEntry('1', FriendRelation.friend)],
      ),
    );
    await first;
    expect(controller.friends.single.userId, '2');
  });

  test('검색어 변경과 늦게 도착한 검색 결과를 분리합니다', () async {
    await controller.refresh();
    final old = Completer<List<FriendEntry>>();
    service.onSearch = (_) => old.future;
    final first = controller.search('러너1');
    controller.queryChanged('러너2');
    old.complete([friendEntry('1', FriendRelation.none)]);
    await first;
    expect(controller.results, isEmpty);
    expect(controller.searched, isFalse);
    expect(controller.searching, isFalse);
  });

  test('잘못된 검색어와 인증 전 요청은 서버로 보내지 않습니다', () async {
    await controller.refresh();
    await controller.search('%');
    expect(service.searches, isEmpty);
    expect(controller.searchError, isNotNull);
    service.canInteract = false;
    await controller.refresh();
    expect(
      await controller.change(
        friendEntry('1', FriendRelation.none),
        FriendAction.request,
      ),
      isFalse,
    );
    await controller.search('러너1');
    expect(service.changes, isEmpty);
    expect(service.searches, isEmpty);
  });

  test('친구 요청 후 서버 상태로 목록과 검색 결과를 갱신합니다', () async {
    await controller.refresh();
    await controller.search('러너1');
    expect(
      await controller.change(controller.results.single, FriendAction.request),
      isTrue,
    );
    expect(controller.sent.single.userId, '1');
    expect(controller.results.single.relation, FriendRelation.sent);
    await controller.change(controller.sent.single, FriendAction.cancel);
    expect(controller.sent, isEmpty);
    expect(controller.results.single.relation, FriendRelation.none);
  });

  test('변경 중 중복 클릭을 차단하고 실패를 새로고침 후에도 표시합니다', () async {
    await controller.refresh();
    final pending = Completer<void>();
    service.onChange = (_, _) => pending.future;
    final request = controller.change(
      friendEntry('1', FriendRelation.none),
      FriendAction.request,
    );
    expect(
      await controller.change(
        friendEntry('2', FriendRelation.none),
        FriendAction.request,
      ),
      isFalse,
    );
    pending.completeError(
      const PostgrestException(message: '잠시 후 친구 요청을 보내 주세요.', code: 'P0001'),
    );
    expect(await request, isFalse);
    expect(service.changes, hasLength(1));
    expect(controller.error, '잠시 후 친구 요청을 보내 주세요.');
    expect(controller.busyUserId, isNull);
  });

  test('계정 전환 후 이전 계정의 목록과 검색을 지웁니다', () async {
    service.entries = [friendEntry('1', FriendRelation.friend)];
    await controller.refresh();
    await controller.search('러너1');
    final pending = Completer<FriendDashboard>();
    service.onLoad = () => pending.future;
    final load = controller.refresh();
    service.isCurrentOwner = false;
    pending.complete(
      FriendDashboard(canInteract: true, entries: service.entries),
    );
    await load;
    expect(controller.friends, isEmpty);
    expect(controller.results, isEmpty);
    expect(controller.canInteract, isFalse);
    expect(controller.error, '다시 로그인해 주세요.');
  });

  test('인증 해제 시 기존 검색 결과를 숨깁니다', () async {
    await controller.refresh();
    await controller.search('러너1');
    service.canInteract = false;
    await controller.refresh();
    expect(controller.results, isEmpty);
    expect(controller.searched, isFalse);
  });

  test('새로고침은 상대방이 수락한 상태를 검색 결과에도 반영합니다', () async {
    service.entries = [friendEntry('1', FriendRelation.sent)];
    await controller.refresh();
    await controller.search('러너1');
    service.entries = [friendEntry('1', FriendRelation.friend)];
    await controller.refresh();
    expect(controller.results.single.relation, FriendRelation.friend);
  });

  test('목록 권한이 회수되면 기존 친구와 검색 결과를 지웁니다', () async {
    service.entries = [friendEntry('1', FriendRelation.friend)];
    await controller.refresh();
    await controller.search('러너1');
    service.onLoad = () async => throw const PostgrestException(
      message: '계정 상태를 확인해 주세요.',
      code: '42501',
    );
    await controller.refresh();
    expect(controller.friends, isEmpty);
    expect(controller.results, isEmpty);
    expect(controller.canInteract, isFalse);
  });

  test('변경 후 목록 갱신이 끝날 때까지 다른 변경을 차단합니다', () async {
    await controller.refresh();
    final pending = Completer<FriendDashboard>();
    service.onLoad = () => pending.future;
    final first = controller.change(
      friendEntry('1', FriendRelation.none),
      FriendAction.request,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.busyUserId, '1');
    expect(
      await controller.change(
        friendEntry('2', FriendRelation.none),
        FriendAction.request,
      ),
      isFalse,
    );
    pending.complete(
      FriendDashboard(canInteract: true, entries: service.entries),
    );
    await first;
    expect(controller.busyUserId, isNull);
  });

  test('백그라운드 전환 시 진행 중 조회를 무효화하고 복귀 시 다시 조회합니다', () async {
    final pending = Completer<FriendDashboard>();
    service.onLoad = () => pending.future;
    controller.setActive(true);
    controller.setActive(false);
    pending.complete(
      FriendDashboard(
        canInteract: true,
        entries: [friendEntry('1', FriendRelation.friend)],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.friends, isEmpty);
    service.onLoad = null;
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(service.loads, 2);
    expect(controller.loaded, isTrue);
  });
}
