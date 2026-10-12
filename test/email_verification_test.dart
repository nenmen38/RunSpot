import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/auth/data/email_verification_service.dart';
import 'package:runquest/features/auth/email_verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeEmailService implements EmailVerificationService {
  EmailVerificationState state = const EmailVerificationState(
    verified: false,
    email: 'runner@example.com',
  );
  bool unavailable = false;
  Object? sendError;
  int sends = 0;
  String? sentEmail;

  @override
  Future<bool> isVerified() async => state.verified;

  @override
  Future<EmailVerificationState> load() async {
    if (unavailable) throw Exception('연결 실패');
    return state;
  }

  @override
  Future<void> send(String email) async {
    if (sendError != null) throw sendError!;
    sends++;
    sentEmail = email;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    FakeEmailService service,
    Future<void> Function() verified, {
    DateTime Function()? now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationScreen(
          service: service,
          onVerified: verified,
          now: now ?? DateTime.now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('메일 발송만으로 인증 완료를 인정하지 않고 재전송 대기를 유지합니다', (tester) async {
    final service = FakeEmailService();
    var completed = 0;
    var now = DateTime.utc(2026, 10, 12);
    await show(tester, service, () async => completed++, now: () => now);
    await tester.tap(find.text('인증 메일 재전송'));
    await tester.pumpAndSettle();
    expect(service.sentEmail, 'runner@example.com');
    expect(service.sends, 1);
    expect(completed, 0);
    expect(find.text('인증 메일을 보냈습니다.'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('인증 메일 재전송'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('서버에서 확인한 인증 상태만 완료 처리합니다', (tester) async {
    final service = FakeEmailService();
    var completed = 0;
    await show(tester, service, () async => completed++);
    await tester.tap(find.text('인증 상태 확인'));
    await tester.pumpAndSettle();
    expect(completed, 0);
    expect(find.text('이메일 인증이 아직 완료되지 않았습니다.'), findsOneWidget);
    service.state = const EmailVerificationState(
      verified: true,
      email: 'runner@example.com',
    );
    await tester.tap(find.text('인증 상태 확인'));
    await tester.pumpAndSettle();
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이미 인증된 계정에는 메일을 다시 보내지 않습니다', (tester) async {
    final service = FakeEmailService()
      ..state = const EmailVerificationState(
        verified: true,
        email: 'runner@example.com',
      );
    var completed = 0;
    await show(tester, service, () async => completed++);
    expect(completed, 1);
    expect(service.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('앱으로 돌아오면 이메일 인증 상태를 다시 확인합니다', (tester) async {
    final service = FakeEmailService();
    var completed = 0;
    await show(tester, service, () async => completed++);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    service.state = const EmailVerificationState(
      verified: true,
      email: 'runner@example.com',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('서버 확인 실패 시 메일 발송과 완료 처리를 허용하지 않습니다', (tester) async {
    final service = FakeEmailService()..unavailable = true;
    var completed = 0;
    await show(tester, service, () async => completed++);
    expect(find.text('이메일 인증 상태를 확인하지 못했습니다.'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(completed, 0);
    service.unavailable = false;
    await tester.tap(find.text('인증 상태 확인'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이메일이 없는 계정은 올바른 이메일만 등록 요청합니다', (tester) async {
    final service = FakeEmailService()
      ..state = const EmailVerificationState(verified: false);
    await show(tester, service, () async {});
    await tester.enterText(find.byType(TextField), '잘못된주소');
    await tester.tap(find.text('인증 메일 보내기'));
    await tester.pumpAndSettle();
    expect(service.sends, 0);
    await tester.enterText(find.byType(TextField), 'new@example.com');
    await tester.tap(find.text('인증 메일 보내기'));
    await tester.pumpAndSettle();
    expect(service.sentEmail, 'new@example.com');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('메일 발송 제한 오류는 한국어로 표시합니다', (tester) async {
    final service = FakeEmailService()
      ..sendError = const AuthException(
        '제한',
        code: 'over_email_send_rate_limit',
      );
    await show(tester, service, () async {});
    await tester.tap(find.text('인증 메일 재전송'));
    await tester.pumpAndSettle();
    expect(find.text('메일 요청이 많습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
