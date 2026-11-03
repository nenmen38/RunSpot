class PasswordPolicy {
  static const description = '비밀번호는 8자 이상, 영문 대문자·소문자·숫자·특수기호를 모두 포함해 주세요.';

  static bool isValid(String password) =>
      password.runes.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password) &&
      RegExp(r'[!-/:-@\[-`{-~]').hasMatch(password);
}
