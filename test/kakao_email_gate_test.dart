import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/email_verification.dart';
import 'package:runquest/features/auth/kakao_email_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/auth_storage.dart';

void main() {
  var verified = false;
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
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(request.url.path.endsWith('/user') ? owner : verified),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
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
