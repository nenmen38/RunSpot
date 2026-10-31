import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:runquest/features/diagnostics/error_reporter.dart';

void main() {
  const target = '11111111-1111-4111-8111-111111111111';
  test('다른 계정과 잘못된 푸시 데이터는 화면 이동에 사용하지 않음', () {
    final data = {
      'recipient_id': '본인',
      'kind': 'board_comment',
      'target_id': target,
    };
    expect(PushDestination.parse(data, '본인')?.targetId, target);
    expect(PushDestination.parse(data, '다른 계정'), isNull);
    expect(PushDestination.parse(data, null), isNull);
    expect(PushDestination.parse({...data, 'kind': '알 수 없음'}, '본인'), isNull);
    expect(
      PushDestination.parse({...data, 'target_id': '../설정'}, '본인'),
      isNull,
    );
  });
  test('오류 보고에서 주소·토큰·좌표와 기기 파일 경로를 제외함', () {
    final safe = ErrorReporter.sanitizedStack(
      StackTrace.fromString(
        '좌표: 37.123,127.456 토큰: 비밀\n'
        '#0 save (package:runquest/features/run_history/run_history_controller.dart:12:3)\n'
        '#1 secret (/Users/사용자/비밀.dart:42:1)\n'
        'https://example.com?token=비밀',
      ),
    );
    expect(
      safe,
      'package:runquest/features/run_history/run_history_controller.dart:12:3',
    );
    expect(safe, isNot(contains('비밀')));
    expect(safe, isNot(contains('37.123')));
  });
}
