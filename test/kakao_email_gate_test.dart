import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/email_verification.dart';
import 'package:runquest/features/auth/kakao_email_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:runquest/features/auth/auth_gate.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:runquest/shared/widgets/footprint_loader.dart';

import 'support/auth_storage.dart';

void main() {
  var verified = false;
  Completer<void>? emailCheck;
  Completer<void>? registrationCheck;
  final owner = {
    'id': 'owner',
    'aud': 'authenticated',
    'app_metadata': {'provider': 'kakao'},
    'created_at': '2026-01-01T00:00:00Z',
    'identities': [
      {'id': 'kakao-id', 'user_id': 'owner', 'provider': 'kakao'},
    ],
  };
  setUp(() async {
    verified = false;
    emailCheck = null;
    registrationCheck = null;
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'public-key',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user')) await emailCheck?.future;
        if (request.url.path.endsWith('my_registration_complete'))
          await registrationCheck?.future;
        return http.Response(
          jsonEncode(request.url.path.endsWith('/user') ? owner : verified),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'session-token',
        'refresh_token': 'refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': owner,
      }),
    );
  });
  tearDown(() => Supabase.instance.dispose());

  for (final restored in [true, false]) {
    testWidgets('카카오 세션 복원 여부 $restored 에 맞춰 발자국을 한 번 표시합니다', (tester) async {
      final auth = Supabase.instance.client.auth;
      final session = jsonEncode(auth.currentSession!.toJson());
      if (!restored) await auth.signOut(scope: SignOutScope.local);
      verified = true;
      emailCheck = Completer<void>();
      registrationCheck = Completer<void>();
      await tester.pumpWidget(
        const MaterialApp(
          home: AuthGate(child: Scaffold(body: Text('홈 화면'))),
        ),
      );
      final footprints = find.byType(FootprintLoader);
      if (!restored) {
        expect(find.byType(AuthScreen), findsOneWidget);
        expect(footprints, findsNothing);
        await auth.recoverSession(session);
        await tester.pump();
      }
      expect(footprints, restored ? findsOneWidget : findsNothing);
      final initial = restored ? tester.state(footprints) : null;
      emailCheck!.complete();
      await tester.pump();
      await tester.pump();
      expect(footprints, findsOneWidget);
      if (restored) expect(tester.state(footprints), same(initial));
      registrationCheck!.complete();
      await tester.pump(const Duration(milliseconds: 900));
      expect(footprints, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('홈 화면'), findsOneWidget);
      expect(footprints, findsNothing);
    });
  }

  testWidgets('이메일 없는 카카오 계정은 별도 인증 후에만 홈으로 이동합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: KakaoEmailGate(child: Scaffold(body: Text('홈 화면'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmailVerificationScreen), findsOneWidget);
    expect(find.text('홈 화면'), findsNothing);
    expect(find.text('로그아웃'), findsOneWidget);
    verified = true;
    await tester.tap(find.text('인증 상태 확인'));
    await tester.pumpAndSettle();
    expect(find.text('홈 화면'), findsOneWidget);
    expect(find.byType(EmailVerificationScreen), findsNothing);
  });
}
