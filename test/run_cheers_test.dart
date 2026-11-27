import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/data/block_service.dart';
import 'package:runquest/features/social/data/cheer_service.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:runquest/features/social/widgets/user_interaction_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Blocks implements BlockService {
  @override
  bool get isCurrentOwner => true;
  @override
  Future<List<BlockedUser>> load() async => [];
  @override
  Future<void> change(String userId, {required bool blocked}) async {}
}

class FakeCheerService implements CheerService {
  final sent = <String>[];
  final waiting = <String>[];
  @override
  bool get isCurrentOwner => true;
  @override
  Future<void> send(String userId) async => sent.add(userId);
  @override
  Future<List<String>> take() async {
    final taken = [...waiting];
    waiting.clear();
    return taken;
  }
}

void main() {
  test('달리는 동안만 받은 응원을 확인해 한 번씩 알려 줍니다', () async {
    final service = FakeCheerService()..waiting.add('민지');
    final heard = <String>[];
    final listener = CheerListener(service: service, onCheer: heard.add);
    expect(listener.running, isFalse);
    listener.setRunning(true);
    expect(listener.running, isTrue);
    await listener.check();
    await listener.check();
    expect(heard, ['민지']);
    listener.setRunning(false);
    expect(listener.running, isFalse);
    listener.dispose();
  });

  test('응원 결과 문구는 서버가 알려 준 이유를 그대로 보여 줍니다', () {
    expect(cheerResultMessage(null, '민지'), '민지님에게 응원을 보냈어요 👏');
    expect(
      cheerResultMessage(
        const PostgrestException(
          message: '지금 달리고 있는 친구에게만 응원할 수 있어요.',
          code: 'P0001',
        ),
        '민지',
      ),
      '지금 달리고 있는 친구에게만 응원할 수 있어요.',
    );
    expect(
      cheerResultMessage(StateError('x'), '민지'),
      '응원을 보내지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
    );
  });

  testWidgets('친구 메뉴에 응원 보내기가 있고 누르면 보냅니다', (tester) async {
    var cheered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUserInteraction(
                context,
                userId: 'runner',
                nickname: '민지',
                blocks: _Blocks(),
                knownFriend: const FriendEntry(
                  userId: 'runner',
                  nickname: '민지',
                  relation: FriendRelation.friend,
                ),
                onCheer: () => cheered++,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-cheer')));
    await tester.pumpAndSettle();
    expect(cheered, 1);
  });
}
