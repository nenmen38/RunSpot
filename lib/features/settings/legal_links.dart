/// 스토어 심사와 이용자 안내에 필요한 정책 문서 주소입니다.
/// `config/*.json`에 값을 넣으면 설정 화면에 표시되고, 비어 있으면 숨깁니다.
class LegalLinks {
  static const privacyPolicy = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const terms = String.fromEnvironment('TERMS_URL');
  static const locationTerms = String.fromEnvironment('LOCATION_TERMS_URL');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
