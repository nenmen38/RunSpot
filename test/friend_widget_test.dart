import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:runquest/features/social/social_screen.dart';

import 'support/friend_fakes.dart';
import 'support/statistics_fakes.dart';

void main() {
  Future<void> showSocial(
    WidgetTester tester,
    FakeFriendService service, {
    Size size = const Size(320, 568),
    VoidCallback? onProfile,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SocialScreen(
                rankingService: FakeRankingService(),
                friendService: service,
                onProfileTap: onProfile,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('검색 후 친구 요청 및 취소가 실제 상태에 반영됩니다', (tester) async {
    final service = FakeFriendService();
    await showSocial(tester, service);
    expect(find.text('아직 친구가 없습니다.'), findsOneWidget);
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '러너1');
    await tester.tap(find.byTooltip('친구 검색'));
    await tester.pumpAndSettle();
    expect(find.text('러너1'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, '요청'));
    await tester.pumpAndSettle();
    expect(service.entries.single.relation, FriendRelation.sent);
    await tester.tap(find.byTooltip('요청 취소'));
    await tester.pumpAndSettle();
    expect(service.entries, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('받은 요청 수락과 친구 삭제 확인 및 취소를 처리합니다', (tester) async {
    final service = FakeFriendService()
      ..entries = [friendEntry('1', FriendRelation.received)];
    await showSocial(tester, service);
    await tester.tap(find.text('요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('요청 수락'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('친구'));
    await tester.pumpAndSettle();
    expect(find.text('내 친구 1'), findsOneWidget);
    await tester.tap(find.byTooltip('친구 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.entries, hasLength(1));
    await tester.tap(find.byTooltip('친구 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('내 친구 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('받은 요청 거절과 인증 전 프로필 이동을 지원합니다', (tester) async {
    final service = FakeFriendService()
      ..entries = [friendEntry('1', FriendRelation.received)];
    var profileOpened = false;
    await showSocial(tester, service, onProfile: () => profileOpened = true);
    await tester.tap(find.text('요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('요청 거절'));
    await tester.pumpAndSettle();
    expect(service.entries, isEmpty);
    service.canInteract = false;
    await tester.tap(find.byTooltip('친구 목록 새로고침'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('프로필'));
    expect(profileOpened, isTrue);
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('좁은 화면에서 긴 닉네임 및 모든 탭이 겹치지 않습니다', (tester) async {
    final service = FakeFriendService()
      ..entries = [
        friendEntry(
          '1',
          FriendRelation.received,
          nickname: '가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나',
        ),
      ];
    await showSocial(tester, service);
    for (final label in ['요청', '검색', '랭킹', '친구']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('줄어든 높이에서도 검색 오류가 겹치지 않습니다', (tester) async {
    await showSocial(tester, FakeFriendService(), size: const Size(320, 250));
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '%');
    await tester.tap(find.byTooltip('친구 검색'));
    await tester.pumpAndSettle();
    expect(find.text('닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
