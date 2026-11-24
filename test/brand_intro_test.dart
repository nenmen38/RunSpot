import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/widgets/brand_intro.dart';

void main() {
  testWidgets('발자국과 뜀터 글자를 보여준 뒤 글자가 달려 나가고 다음 화면으로 넘어갑니다', (tester) async {
    await tester.runAsync(BrandIntro.preload);
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandIntro(child: Scaffold(body: Text('다음 화면'))),
      ),
    );
    // 첫 장면부터 발자국(미리 풀어 둔 그림)이 보여 폰 시작 화면과 이어집니다.
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('뜀터'), findsOneWidget);
    expect(find.text('다음 화면'), findsNothing);

    // 달려 나가는 동안 글자가 오른쪽으로 이동합니다.
    await tester.pump(const Duration(milliseconds: 500));
    final before = tester.getCenter(find.text('뜀터')).dx;
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getCenter(find.text('뜀터')).dx, greaterThan(before + 100));

    // 끝나면 다음 화면만 남습니다.
    await tester.pump(BrandIntro.duration);
    await tester.pump();
    expect(find.text('다음 화면'), findsOneWidget);
    expect(find.text('뜀터'), findsNothing);
  });

  testWidgets('동작 줄이기 설정이면 잠깐 보여주고 바로 넘어갑니다', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: BrandIntro(child: Scaffold(body: Text('다음 화면'))),
        ),
      ),
    );
    expect(find.text('뜀터'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('다음 화면'), findsOneWidget);
    expect(find.text('뜀터'), findsNothing);
  });
}
