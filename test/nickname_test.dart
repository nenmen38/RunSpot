import 'package:runquest/features/auth/data/nickname_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:runquest/features/auth/nickname.dart';

class FakeNicknameService implements NicknameService {
  FakeNicknameService(this.state);
  NicknameState state;
  Object? error;
  String? saved;
  @override
  Future<NicknameState> load() async => state;
  @override
  Future<void> save(String nickname) async {
    if (error != null) throw error!;
    saved = nickname;
  }
}

void main() {
  test('닉네임 형식과 변경 기간 경계를 검증합니다', () {
    expect(validateNickname('러너_123'), isNull);
    for (final value in ['', 'a', '공 백', ' runner', 'runner!', 'a' * 31]) {
      expect(validateNickname(value), isNotNull);
    }
    final now = DateTime.utc(2026, 9, 22);
    expect(const NicknameState(verified: false).canChange(now), isFalse);
    expect(const NicknameState(verified: true).canChange(now), isTrue);
    expect(
      NicknameState(
        verified: true,
        changedAt: now.subtract(const Duration(days: 29)),
      ).canChange(now),
      isFalse,
    );
    expect(
      NicknameState(
        verified: true,
        changedAt: now.subtract(const Duration(days: 30)),
      ).canChange(now),
      isTrue,
    );
  });

  testWidgets('미인증 사용자의 입력과 저장을 비활성화합니다', (tester) async {
    final service = FakeNicknameService(const NicknameState(verified: false));
    await tester.pumpWidget(
      MaterialApp(home: NicknameScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(service.saved, isNull);
  });

  testWidgets('30일 변경 제한과 가능 날짜를 표시합니다', (tester) async {
    final service = FakeNicknameService(
      NicknameState(verified: true, nickname: '러너', changedAt: DateTime.now()),
    );
    await tester.pumpWidget(
      MaterialApp(home: NicknameScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('변경 가능:'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('중복 오류 후 수정하여 저장하면 이전 화면으로 돌아갑니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeNicknameService(const NicknameState(verified: true));
    service.error = const PostgrestException(message: '중복', code: '23505');
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => NicknameScreen(service: service),
                  ),
                );
              },
              child: const Text('등록'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Runner');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('이미 사용 중인 닉네임입니다.'), findsOneWidget);
    service.error = null;
    await tester.enterText(find.byType(TextField), '새러너');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(service.saved, '새러너');
    expect(result, isTrue);
    expect(find.text('등록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
