import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/data/block_service.dart';
import 'package:runquest/features/social/data/friend_service.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:runquest/features/social/models/friend_profile.dart';
import 'package:runquest/features/social/widgets/user_interaction_sheet.dart';

class _Blocks implements BlockService {
  bool changed = false;
  @override
  bool get isCurrentOwner => true;
  @override
  Future<List<BlockedUser>> load() async => [];
  @override
  Future<void> change(String userId, {required bool blocked}) async {
    changed = userId == 'runner' && blocked;
  }
}

class _Friends implements FriendService {
  @override
  Future<FriendProfile?> loadProfile(String userId) async => null;

  FriendRelation relation = FriendRelation.none;
  FriendAction? action;
  @override
  bool get isCurrentOwner => true;
  @override
  Future<FriendDashboard> load() async =>
      FriendDashboard(canInteract: true, entries: []);
  @override
  Future<List<FriendEntry>> search(String nickname) async => [
    FriendEntry(userId: 'runner', nickname: nickname, relation: relation),
  ];
  @override
  Future<void> change(FriendEntry entry, FriendAction value) async {
    action = value;
    relation = FriendRelation.sent;
  }
}

void main() {
  testWidgets('사용자 메뉴에서 친구 요청하고 확인 후 차단합니다', (tester) async {
    final blocks = _Blocks();
    final friends = _Friends();
    bool? blocked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                blocked = await showUserInteraction(
                  context,
                  userId: 'runner',
                  nickname: '러너',
                  blocks: blocks,
                  friends: friends,
                );
              },
              child: const Text('사용자 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('사용자 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('친구 요청'));
    await tester.pumpAndSettle();
    expect(friends.action, FriendAction.request);
    expect(find.text('친구 요청 취소'), findsOneWidget);
    await tester.tap(find.text('사용자 차단'));
    await tester.pumpAndSettle();
    expect(find.textContaining('서로의 위치·게시글·댓글·랭킹'), findsOneWidget);
    expect(blocks.changed, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '차단'));
    await tester.pumpAndSettle();
    expect(blocks.changed, isTrue);
    expect(blocked, isTrue);
  });
}
