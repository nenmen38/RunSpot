import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/errors/server_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('서버 함수가 없으면 업데이트가 필요하다고 안내합니다', () {
    expect(
      unexpectedServerError(
        const PostgrestException(message: 'not found', code: 'PGRST202'),
        '실패',
      ),
      '서버 업데이트가 필요한 기능입니다. 잠시 후 다시 시도해 주세요.',
    );
  });

  test('그 밖의 서버 오류에는 오류 코드를 덧붙입니다', () {
    expect(
      unexpectedServerError(
        const PostgrestException(message: 'boom', code: '23505'),
        '실패',
      ),
      '실패 (오류 코드 23505)',
    );
    expect(unexpectedServerError(StateError('x'), '실패'), '실패');
  });
}
