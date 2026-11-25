import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/auth_gate.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:runquest/features/auth/community_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/auth_storage.dart';

void main() {
  var policyAccepted = true;
  final consentRequests = <Map<String, dynamic>>[];

  setUp(() async {
    policyAccepted = true;
    consentRequests.clear();
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
        final rpc = request.url.path.split('/').last;
        final Object? result;
        switch (rpc) {
          case 'my_registration_complete':
            result = true;
          case 'my_community_policy_accepted':
            result = policyAccepted;
          case 'accept_community_policy':
            consentRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
            policyAccepted = true;
            result = null;
          default:
            result = {};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': 'owner',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'runner@example.com',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDown(() => Supabase.instance.dispose());

  testWidgets('운영정책에 직접 동의한 뒤에만 홈으로 이동합니다', (tester) async {
    policyAccepted = false;
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(child: Scaffold(body: Text('로그인된 홈'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CommunityPolicy.title), findsOneWidget);
    expect(find.text('로그인된 홈'), findsNothing);
    final continueButton = find.widgetWithText(FilledButton, '동의하고 계속');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(consentRequests, isEmpty);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(consentRequests, [
      {'shown_version': CommunityPolicy.version},
    ]);
    expect(find.text('로그인된 홈'), findsOneWidget);
  });

  testWidgets('로그아웃 시 설정과 상세 화면을 닫고 로그인 화면을 표시합니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const AuthGate(child: Scaffold(body: Text('로그인된 홈'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('로그인된 홈'), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('설정 화면')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('상세 화면')),
      ),
    );
    await tester.pumpAndSettle();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('설정 화면'), findsNothing);
    expect(find.text('상세 화면'), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
  });
}
