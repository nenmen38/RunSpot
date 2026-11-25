/// 스토어 심사와 이용자 안내에 필요한 정책 문서 주소입니다.
/// 출시용 공개 주소를 기본값으로 사용하며 빌드 설정에서 바꿀 수 있습니다.
class LegalLinks {
  static const privacyPolicy = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://capstone-running-policy.web.app/privacy.html',
  );
  static const accountDeletion = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
    defaultValue: 'https://capstone-running-policy.web.app/account-deletion.html',
  );
  static const terms = String.fromEnvironment('TERMS_URL');
  static const locationTerms = String.fromEnvironment('LOCATION_TERMS_URL');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
