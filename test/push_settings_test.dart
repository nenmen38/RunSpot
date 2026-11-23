import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:runquest/features/notifications/push_settings_screen.dart';

void main() {
  testWidgets('알림을 항목별로 나눠 보여주고 하나씩 켜고 끕니다', (tester) async {
    final values = <String, dynamic>{
      for (final group in pushPreferenceGroups)
        for (final item in group.items) item.key: true,
    };
    final sent = <Map<String, dynamic>?>[];
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PushSettingsScreen(
          enable: () async {},
          update: (changes) async {
            sent.add(changes);
            if (fail) throw Exception('오프라인');
            values.addAll(changes ?? const {});
            return {...values};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['대화', '친구·모임', '게시판', '표시 방식']) {
      // 아래 항목은 내려가며 확인합니다.
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('1:1 메시지'), -200);
    for (final label in ['1:1 메시지', '단체·크루 대화방', '친구 요청', '함께 달리기 초대']) {
      expect(find.text(label), findsOneWidget);
    }

    final message = find.byKey(const ValueKey('push-friend_message'));
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();
    await tester.tap(message);
    await tester.pumpAndSettle();
    expect(sent.last, {'friend_message': false});
    expect(values['room_message'], true);

    // 저장에 실패하면 스위치를 원래대로 돌리고 알려줍니다.
    fail = true;
    final like = find.byKey(const ValueKey('push-board_like'));
    await tester.scrollUntilVisible(like, 200);
    await tester.ensureVisible(like);
    await tester.pumpAndSettle();
    await tester.tap(like);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(like).value, true);
    expect(find.text('알림 설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  test('좋아요·크루 초대 알림도 눌러서 열 수 있습니다', () {
    const target = '11111111-1111-4111-8111-111111111111';
    for (final kind in ['board_like', 'crew_invite']) {
      expect(
        PushDestination.parse({
          'kind': kind,
          'target_id': target,
          'recipient_id': '본인',
        }, '본인')?.kind,
        kind,
      );
    }
  });

  testWidgets('상점 테두리 동그라미에는 사람 대신 지도와 같은 화살표를 그립니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrameBadge(kind: FrameKind.basic, color: Colors.red),
        ),
      ),
    );
    expect(find.byType(MapHeadingArrow), findsOneWidget);
    expect(find.byIcon(Icons.directions_run), findsNothing);
  });
}
