import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/auth/data/phone_verification_service.dart';
import 'package:runquest/features/auth/phone_verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakePhoneService implements PhoneVerificationService {
  bool verified = false;
  bool unavailable = false;
  bool acceptCode = true;
  bool failSend = false;
  String? pending;
  int sends = 0;
  @override
  Future<PhoneVerificationState> load() async {
    if (unavailable) throw Exception('연결 실패');
    return PhoneVerificationState(
      verified: verified,
      phone: verified ? '+821012345678' : null,
      pendingPhone: pending,
    );
  }

  @override
  Future<void> send(String phone) async {
    sends++;
    if (failSend) {
      throw const AuthException('발송 없음', code: 'phone_provider_disabled');
    }
    pending = phone;
  }

  @override
  Future<void> verify(String phone, String code) async {
    if (code != '123456') throw const AuthException('만료', code: 'otp_expired');
    verified = acceptCode;
    if (verified) pending = null;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    FakePhoneService service, {
    DateTime Function()? now,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneVerificationScreen(
          service: service,
          now: now ?? DateTime.now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '01012345678');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pumpAndSettle();
  }

  test('국내·국제 번호를 정규화하고 잘못된 입력을 거절합니다', () {
    expect(normalizePhone('010-1234-5678'), '+821012345678');
    expect(normalizePhone('+82 10 1234 5678'), '+821012345678');
    expect(normalizePhone('010123'), isNull);
    expect(normalizePhone('abc01012345678'), isNull);
  });
  testWidgets('이미 인증된 계정은 발송 없이 완료 상태를 표시합니다', (tester) async {
    final service = FakePhoneService()..verified = true;
    await show(tester, service);
    expect(find.text('전화번호 인증 완료'), findsOneWidget);
    expect(find.text('인증번호 받기'), findsNothing);
    expect(service.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('발송만으로 인증하지 않고 서버 확인 후에만 완료합니다', (tester) async {
    final service = FakePhoneService();
    var now = DateTime.utc(2026, 10, 12);
    await show(tester, service, now: () => now);
    await send(tester);
    expect(service.pending, '+821012345678');
    expect(find.text('전화번호 인증 완료'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('인증번호 확인'));
    await tester.pumpAndSettle();
    expect(find.text('전화번호 인증 완료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('잘못된 코드와 서버 미확인 상태는 완료로 처리하지 않습니다', (tester) async {
    final service = FakePhoneService()..acceptCode = false;
    await show(tester, service);
    await send(tester);
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('인증번호 확인'));
    await tester.pumpAndSettle();
    expect(find.text('인증번호가 올바르지 않거나 만료되었습니다.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('인증번호 확인'));
    await tester.pumpAndSettle();
    expect(find.text('전화번호 인증이 아직 완료되지 않았습니다.'), findsOneWidget);
    expect(find.text('전화번호 인증 완료'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('인증 상태 조회 실패 시 발송을 차단하고 재확인합니다', (tester) async {
    final service = FakePhoneService()..unavailable = true;
    await show(tester, service);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    service.unavailable = false;
    service.verified = true;
    await tester.tap(find.text('인증 상태 확인'));
    await tester.pumpAndSettle();
    expect(find.text('전화번호 인증 완료'), findsOneWidget);
    expect(service.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('SMS 미연결은 오류로 안내하고 인증을 우회하지 않습니다', (tester) async {
    final service = FakePhoneService()..failSend = true;
    await show(tester, service);
    await send(tester);
    expect(find.text('문자 발송이 연결되어 있지 않습니다.'), findsOneWidget);
    expect(find.text('전화번호 인증 완료'), findsNothing);
    expect(find.text('인증번호 확인'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('앱 복귀 시 관리자 변경 상태를 다시 확인합니다', (tester) async {
    final service = FakePhoneService();
    await show(tester, service);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    service.verified = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('전화번호 인증 완료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
