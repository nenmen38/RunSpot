import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/auth/registration.dart';
import 'package:runquest/features/auth/auth_screen.dart';

void main() {
  testWidgets('서버가 허용한 테스트 모드에서는 동의 항목을 표시하지 않습니다', (tester) async {
    bool enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationFields(
            loadTestMode: () async => true,
            loadTerms: () async => throw StateError('테스트 모드에서 약관 조회 금지'),
            onChanged: (id, accepted) {
              expect(id, isNull);
              expect(accepted, isFalse);
            },
            onTestModeChanged: (value) => enabled = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(find.text('테스트 가입 · 약관 동의 생략'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(validateRegistration(false, null, testMode: enabled), isNull);
    expect(validateRegistration(false, null), isNotNull);
  });

  testWidgets('약관 동의는 기본 해제이며 실제 본문을 열 수 있습니다', (tester) async {
    bool accepted = true;
    String? termsId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationFields(
            loadTerms: () async => {
              'id': 'terms',
              'title': '이용약관',
              'version': '1',
              'body': '테스트 약관 본문',
            },
            onChanged: (id, value) {
              termsId = id;
              accepted = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(termsId, 'terms');
    expect(accepted, isFalse);
    await tester.tap(find.text('이용약관 전문 보기'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 약관 본문'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  test('기본 가입에는 닉네임 없이 게시 약관 동의만 필요합니다', () {
    expect(validateRegistration(true, 'terms'), isNull);
    expect(validateRegistration(false, 'terms'), '이용약관에 동의해 주세요.');
    expect(validateRegistration(true, null), '현재 가입 약관이 준비되지 않았습니다.');
  });

  testWidgets('가입 화면에 추가 필드가 표시되고 비밀번호 불일치를 차단합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.ensureVisible(find.text('새 계정 만들기'));
    await tester.tap(find.text('새 계정 만들기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '비밀번호 확인'), findsOneWidget);
    expect(find.widgetWithText(TextField, '닉네임'), findsNothing);
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
