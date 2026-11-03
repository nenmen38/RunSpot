import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/auth/password_policy.dart';

void main() {
  test('8자리 경계와 각 필수 문자 종류를 검증합니다', () {
    expect(PasswordPolicy.isValid('Abcdef1!'), isTrue);
    for (final password in [
      'Abcde1!',
      'abcdef1!',
      'ABCDEF1!',
      'Abcdefg!',
      'Abcdef12',
      'Abcdef1 ',
      'Abcdef1한',
    ]) {
      expect(PasswordPolicy.isValid(password), isFalse, reason: password);
    }
  });
}
