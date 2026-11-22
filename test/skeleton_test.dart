import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/profile/privacy_controls.dart';
import 'package:runquest/shared/widgets/skeleton.dart';

void main() {
  testWidgets('목록 모양별 로딩 뼈대를 그리고, 다른 목록 안에서도 깨지지 않습니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SkeletonList(count: 2),
              SkeletonList(layout: SkeletonLayout.cards, count: 2),
              SkeletonList(layout: SkeletonLayout.chat, count: 3),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Shimmer), findsNWidgets(3));
    expect(find.bySemanticsLabel('불러오는 중'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('동작 줄이기 설정이면 반짝이지 않아 바로 멈춥니다', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: SkeletonList())),
      ),
    );
    // 반복 애니메이션이 없으므로 pumpAndSettle이 끝납니다.
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('프로필 머리말은 이니셜·인증 상태를 보여주고 불러오는 중엔 뼈대를 보여줍니다', (tester) async {
    var edited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileIdentityHeader(
            name: '바람러너',
            verified: true,
            onEdit: () => edited++,
          ),
        ),
      ),
    );
    expect(find.text('바'), findsOneWidget);
    expect(find.text('바람러너'), findsOneWidget);
    expect(find.text('인증된 러너'), findsOneWidget);
    await tester.tap(find.byTooltip('닉네임 변경'));
    expect(edited, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileIdentityHeader(
            name: '나',
            verified: false,
            loading: true,
          ),
        ),
      ),
    );
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.text('나'), findsNothing);
  });
}
