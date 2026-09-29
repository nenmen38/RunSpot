import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/auth/phone_verification.dart';

class FakePhoneService implements PhoneVerificationService {
  bool verified = false;
  bool unavailable = false;
  bool invalidCode = false;
  String? sentPhone;
  int sends = 0;
  @override
  Future<bool> isVerified() async {
    if (unavailable) throw Exception('연결 실패');
    return verified;
  }

  @override
  Future<void> send(String phone) async {
    sentPhone = phone;
    sends++;
  }

  @override
  Future<void> verify(String phone, String code) async {
    if (invalidCode) throw Exception('번호 불일치');
    verified = phone == sentPhone && code == '123456';
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  test('국내 번호와 국제 번호를 정규화하고 잘못된 번호를 거부한다', () {
    expect(normalizePhone('010-1234-5678'), '+821012345678');
    expect(normalizePhone('+82 10 1234 5678'), '+821012345678');
    expect(normalizePhone('010123'), isNull);
    expect(normalizePhone('abc01012345678'), isNull);
  });
  testWidgets('인증 완료 전 차단하고 확인 후 앱을 표시한다', (tester) async {
    final service = FakePhoneService();
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerificationGate(
          service: service,
          child: const Text('앱 진입'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('앱 진입'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '01012345678');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pump();
    expect(service.sentPhone, '+821012345678');
    expect(service.sends, 1);
    final resend = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(resend.onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('인증 완료'));
    await tester.pumpAndSettle();
    expect(find.text('앱 진입'), findsOneWidget);
  });
  testWidgets('서버 확인 실패 시 앱 접근을 허용하지 않는다', (tester) async {
    final service = FakePhoneService()..unavailable = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerificationGate(
          service: service,
          child: const Text('앱 진입'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('앱 진입'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });
  testWidgets('인증된 계정은 문자 재발송 없이 진입한다', (tester) async {
    final service = FakePhoneService()..verified = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerificationGate(
          service: service,
          child: const Text('앱 진입'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('앱 진입'), findsOneWidget);
    expect(service.sends, 0);
  });
  testWidgets('잘못된 인증번호로는 진입하지 못한다', (tester) async {
    final service = FakePhoneService()..invalidCode = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerificationGate(
          service: service,
          child: const Text('앱 진입'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '01012345678');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('인증 완료'));
    await tester.pump();
    expect(find.text('앱 진입'), findsNothing);
    expect(find.text('인증을 처리하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
