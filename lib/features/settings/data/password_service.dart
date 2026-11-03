import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/password_policy.dart';

class PasswordService {
  PasswordService(
    this.client, {
    SupabaseClient Function()? verificationClientFactory,
  }) : _ownerId = client.auth.currentUser?.id,
       _verificationClientFactory =
           verificationClientFactory ?? _configuredFactory;
  static SupabaseClient Function()? _configuredFactory;
  final SupabaseClient Function()? _verificationClientFactory;
  static void configure(String url, String publicKey) {
    _configuredFactory = () => SupabaseClient(
      url,
      publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  final SupabaseClient client;
  final String? _ownerId;
  bool get canChange =>
      client.auth.currentUser?.identities?.any((i) => i.provider == 'email') ??
      false;
  void _requireOwner() {
    if (_ownerId == null || client.auth.currentSession?.user.id != _ownerId) {
      throw const AuthException('다시 로그인해 주세요.');
    }
  }

  Future<void> sendConfirmation() async {
    _requireOwner();
    await client.auth.reauthenticate();
    _requireOwner();
  }

  Future<void> change(String current, String password, {String? nonce}) async {
    _requireOwner();
    if (!canChange) {
      throw const AuthException('소셜 로그인 계정의 비밀번호는 해당 서비스에서 변경해 주세요.');
    }
    if (current.isEmpty) throw const AuthException('현재 비밀번호를 입력해 주세요.');
    if (!PasswordPolicy.isValid(password)) {
      throw const AuthException(PasswordPolicy.description);
    }
    if (current == password) {
      throw const AuthException('현재 비밀번호와 다른 비밀번호를 입력해 주세요.');
    }
    final email = client.auth.currentUser?.email;
    final factory = _verificationClientFactory;
    if (email == null || factory == null) {
      throw const AuthException('비밀번호 변경 설정을 확인해 주세요.');
    }
    // 현재 세션을 교체하지 않는 별도 인증 클라이언트에서 현재 비밀번호를 검증합니다.
    final verification = factory();
    try {
      final response = await verification.auth.signInWithPassword(
        email: email,
        password: current,
      );
      final matches = response.user?.id == _ownerId;
      await verification.auth.signOut(scope: SignOutScope.local);
      _requireOwner();
      if (!matches) throw const AuthException('계정을 확인해 주세요.');
    } finally {
      await verification.dispose();
    }
    await client.auth.updateUser(
      UserAttributes(
        password: password,
        currentPassword: current,
        nonce: nonce,
      ),
    );
    _requireOwner();
  }
}
