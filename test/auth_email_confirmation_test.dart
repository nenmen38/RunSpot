import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/auth_storage.dart';

void main() {
  final requests = <http.Request>[];
  var rateLimited = false;

  setUp(() async {
    requests.clear();
    rateLimited = false;
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'error_code': 'email_not_confirmed',
              'msg': 'Email not confirmed',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        if (rateLimited) {
          return http.Response(
            jsonEncode({
              'error_code': 'over_email_send_rate_limit',
              'msg': 'Email rate limit exceeded',
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() => Supabase.instance.dispose());

  Future<void> showPending(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.enterText(find.byType(TextField).first, 'runner@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.ensureVisible(find.text('이메일로 로그인'));
    await tester.tap(find.text('이메일로 로그인'));
    await tester.pumpAndSettle();
    expect(find.text('이메일 인증을 완료한 후 로그인해 주세요.'), findsOneWidget);
  }

  testWidgets('미인증 로그인은 가입 확인 메일을 재전송할 수 있습니다', (tester) async {
    await showPending(tester);
    await tester.ensureVisible(find.text('인증 메일 재전송'));
    await tester.tap(find.text('인증 메일 재전송'));
    await tester.pumpAndSettle();
    expect(requests.last.url.path, '/auth/v1/resend');
    expect(jsonDecode(requests.last.body)['type'], 'signup');
    expect(jsonDecode(requests.last.body)['email'], 'runner@example.com');
    expect(
      requests.last.url.queryParameters['redirect_to'],
      'runspot://login-callback',
    );
    expect(find.text('인증 메일 재전송 대기 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('미인증 로그인 메일 발송 제한은 한국어로 안내합니다', (tester) async {
    await showPending(tester);
    rateLimited = true;
    await tester.ensureVisible(find.text('인증 메일 재전송'));
    await tester.tap(find.text('인증 메일 재전송'));
    await tester.pumpAndSettle();
    expect(find.text('메일 요청이 많습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
