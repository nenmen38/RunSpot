import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/admin/widgets/staff_mfa_control.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final verified in [false, true]) {
    testWidgets(
      verified ? '완료한 인증은 재사용하고 삭제하지 않습니다' : '중단한 관리자 인증만 정리하고 다시 등록합니다',
      (tester) async {
        final requests = <String>[];
        Map<String, dynamic> factor(String id, String name, String status) => {
          'id': id,
          'friendly_name': name,
          'factor_type': 'totp',
          'status': status,
          'created_at': '2026-10-26T00:00:00Z',
          'updated_at': '2026-10-26T00:00:00Z',
        };
        final session = {
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'user': {
            'id': 'owner',
            'aud': 'authenticated',
            'created_at': '2026-10-26T00:00:00Z',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'factors': [
              factor(
                'staff',
                '런스팟 관리 인증',
                verified ? 'verified' : 'unverified',
              ),
              factor('other', '다른 인증', 'unverified'),
            ],
          },
        };
        final client = (await tester.runAsync(
          () async => SupabaseClient(
            'https://example.supabase.co',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              final Object body;
              if (request.url.path.endsWith('/token')) {
                body = session;
              } else if (request.method == 'DELETE') {
                body = {'id': 'staff'};
              } else {
                body = {
                  'id': 'new-staff',
                  'type': 'totp',
                  'totp': {
                    'secret': 'TESTSECRET',
                    'qr_code': '<svg/>',
                    'uri': 'otpauth://test',
                  },
                };
              }
              return http.Response(
                jsonEncode(body),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ))!;
        addTearDown(() => tester.runAsync(client.dispose));
        await tester.runAsync(
          () => client.auth.recoverSession(jsonEncode(session)),
        );
        requests.clear();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StaffMfaControl(
                client: client,
                isCurrentOwner: () => true,
                onVerified: () {},
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('관리자 다중 인증'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('인증 준비에 실패했습니다. 다시 시도해 주세요.'), findsNothing);
        expect(find.text('인증 앱의 6자리 코드'), findsOneWidget);
        expect(
          requests,
          verified
              ? ['POST /auth/v1/token']
              : [
                  'POST /auth/v1/token',
                  'DELETE /auth/v1/factors/staff',
                  'POST /auth/v1/factors',
                ],
        );
        expect(
          find.text('TESTSECRET'),
          verified ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
