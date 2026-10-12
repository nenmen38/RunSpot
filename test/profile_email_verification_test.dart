import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/profile/privacy_controls.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/auth_storage.dart';

void main() {
  var verified = false;
  final requests = <http.Request>[];
  final owner = {
    'id': 'owner',
    'aud': 'authenticated',
    'email': 'runner@example.com',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-10-09T00:00:00Z',
  };
  setUp(() async {
    verified = false;
    requests.clear();
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
        final Object body;
        if (request.url.path.endsWith('my_email_verified')) {
          body = verified;
        } else if (request.url.path.endsWith('my_phone_verification_state')) {
          body = {
            'verified': true,
            'phone': '821012345678',
            'pending_phone': null,
          };
        } else if (request.url.path.endsWith('/user')) {
          body = owner;
        } else {
          body = {
            'visibility': 'private',
            'nickname': null,
            'nickname_changed_at': null,
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': owner,
      }),
    );
  });
  tearDown(() => Supabase.instance.dispose());

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrivacyControls())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('미인증 프로필은 공개 변경 대신 이메일 인증 화면으로 연결됩니다', (tester) async {
    await show(tester);
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .onSelectionChanged,
      isNull,
    );
    await tester.tap(find.text('이메일 인증'));
    await tester.pumpAndSettle();
    expect(find.text('인증 메일 재전송'), findsOneWidget);
    expect(find.text('인증 상태 확인'), findsOneWidget);
    expect(find.text('전화번호 인증'), findsNothing);
    expect(requests.any((r) => r.url.path.contains('phone')), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이메일 인증된 프로필은 추가 전화번호 인증 없이 닉네임 등록이 가능합니다', (tester) async {
    verified = true;
    await show(tester);
    expect(find.text('이메일 인증'), findsNothing);
    expect(find.text('닉네임 등록'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'private'},
    );
    await tester.tap(find.text('닉네임 등록'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNotNull,
    );
    expect(requests.any((r) => r.url.path.contains('phone')), isFalse);
    expect(
      requests.any((r) => r.url.path.endsWith('set_my_nickname')),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('프로필의 선택 전화번호 인증은 서버의 수동 확인 상태를 표시합니다', (tester) async {
    verified = true;
    await show(tester);
    await tester.tap(find.text('전화번호 인증 (선택)'));
    await tester.pumpAndSettle();
    expect(find.text('전화번호 인증 완료'), findsOneWidget);
    expect(requests.last.url.path, '/rest/v1/rpc/my_phone_verification_state');
    expect(
      requests.any(
        (r) => r.url.path.endsWith('/verify') || r.url.path.endsWith('/resend'),
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
