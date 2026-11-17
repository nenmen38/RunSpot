import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/widgets/status_view.dart';

void main() {
  testWidgets('로딩·빈 화면·오류를 같은 모양으로 보여주고 오류는 다시 시도할 수 있습니다', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: StatusView.loading(message: '불러오는 중')),
              const Expanded(child: StatusView.empty(message: '아직 글이 없어요.')),
              Expanded(
                child: StatusView.error(
                  message: '연결을 확인해 주세요.',
                  onRetry: () => retried++,
                ),
              ),
              const InlineError(message: '통계를 불러오지 못했습니다.'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('아직 글이 없어요.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    expect(retried, 1);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
