import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/auth/auth_screen.dart';

void main() {
  testWidgets('가입 화면은 약관 없이 비밀번호 확인만 표시합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.ensureVisible(find.text('새 계정 만들기'));
    await tester.tap(find.text('새 계정 만들기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '비밀번호 확인'), findsOneWidget);
    expect(find.widgetWithText(TextField, '닉네임'), findsNothing);
    expect(find.textContaining('약관'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'runner@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '비밀번호'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '비밀번호 확인'),
      'different',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '회원가입'));
    await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
