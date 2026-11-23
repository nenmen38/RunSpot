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

class _CaseService extends _Service {
  _CaseService({this.conflict = false, this.owner = 'admin'});
  @override
  final String owner;
  final bool conflict;
  Map<String, dynamic>? decision;

  @override
  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    if (name == 'moderation_decide') {
      decision = Map.of(params);
      return null;
    }
    expect(name, 'moderation_list');
    expect(params['mode'], 'cases');
    return [
      if (decision == null)
        {
          'id': 17,
          'kind': 'post',
          'author_id': 'runner',
          'nickname': '푸른러너',
          'reason': '스팸·광고\n반복해서 올라오는 광고',
          'created_at': '2026-11-23T01:30:00Z',
          'evidence': {'body': '신고된 게시글 본문'},
          'conflict': conflict,
        },
    ];
  }
}

void main() {
  testWidgets('신고 증거를 검토하고 대상자와 사유를 확인한 뒤 작성 제한을 확정합니다', (tester) async {
    final service = _CaseService();
    await tester.pumpWidget(
      MaterialApp(
        home: ModerationScreen(service: service, mode: 'cases'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('스팸·광고'), findsOneWidget);
    expect(find.text('신고 대상 · 푸른러너'), findsOneWidget);
    await tester.tap(find.text('신고 증거 보기'));
    await tester.pumpAndSettle();
    expect(find.text('신고된 게시글 본문'), findsOneWidget);
    await tester.tap(find.text('신고 대상자 조치'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '처리 확정');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7일 작성 제한').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.textContaining('신고된 콘텐츠를 삭제합니다.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '반복 광고 확인');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(service.decision, {
      'case_id': 17,
      'decision': 'week',
      'note': '반복 광고 확인',
    });
    expect(find.text('검토할 신고가 없습니다.'), findsOneWidget);
  });

  for (final (owner, message) in [('runner', '내 계정이 신고된 건입니다.')]) {
    testWidgets('관련 신고를 열면 역할에 맞게 안내합니다 · $owner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ModerationScreen(
            service: _CaseService(conflict: true, owner: owner),
            mode: 'cases',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('신고 대상자 조치'), findsNothing);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('다른 관리자가 통합 신고 관리에서'), findsOneWidget);
    });
  }

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
