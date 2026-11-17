import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/moderation/moderation_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Service extends ModerationService {
  _Service()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  String? appeal;
  @override
  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    if (name == 'moderation_appeal') {
      appeal = params['reason'] as String;
      return null;
    }
    return [
      {
        'id': 1,
        'kind': 'day',
        'reason': '반복 괴롭힘',
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now()
            .add(const Duration(hours: 24))
            .toIso8601String(),
        'active': true,
        'appeal': appeal,
        'appeal_status': appeal == null ? null : 'pending',
      },
    ];
  }
}

void main() {
  testWidgets('제재 범위와 해제 시각을 확인하고 이의신청을 접수합니다', (tester) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(home: ModerationScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('24시간 작성 제한'), findsOneWidget);
    expect(find.text('제한 기능 · 게시글·댓글·채팅 작성'), findsOneWidget);
    expect(find.text('제한 중'), findsOneWidget);
    await tester.tap(find.text('이의신청'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '맥락을 확인해 주세요.');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(service.appeal, '맥락을 확인해 주세요.');
    expect(find.text('이의신청 검토 중'), findsOneWidget);
    expect(find.text('이의신청'), findsNothing);
  });
}
