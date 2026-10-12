import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_redirect.dart';

class EmailVerificationState {
  const EmailVerificationState({
    required this.verified,
    this.email,
    this.pendingEmail,
  });

  final bool verified;
  final String? email;
  final String? pendingEmail;
  String? get confirmationEmail => pendingEmail ?? email;
}

abstract interface class EmailVerificationService {
  Future<bool> isVerified();
  Future<EmailVerificationState> load();
  Future<void> send(String email);
}

class SupabaseEmailVerification implements EmailVerificationService {
  SupabaseEmailVerification(this.client)
    : _ownerId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _ownerId;

  Session _requireOwner() {
    final session = client.auth.currentSession;
    if (_ownerId == null || session == null || session.user.id != _ownerId) {
      throw const AuthException('로그인이 필요합니다.');
    }
    return session;
  }

  @override
  Future<bool> isVerified() async {
    final session = _requireOwner();
    final verified =
        await client
            .rpc('my_email_verified')
            .setHeader('Authorization', 'Bearer ${session.accessToken}') ==
        true;
    _requireOwner();
    return verified;
  }

  @override
  Future<EmailVerificationState> load() async {
    final session = _requireOwner();
    final response = await client.auth.getUser(session.accessToken);
    _requireOwner();
    final user = response.user;
    if (user == null || user.id != _ownerId) {
      throw const AuthException('계정 확인에 실패했습니다. 다시 로그인해 주세요.');
    }
    return EmailVerificationState(
      verified: await isVerified(),
      email: user.email?.isNotEmpty == true ? user.email : null,
      pendingEmail: user.newEmail?.isNotEmpty == true ? user.newEmail : null,
    );
  }

  @override
  Future<void> send(String email) async {
    final state = await load();
    _requireOwner();
    if (state.verified) return;
    if (email == state.confirmationEmail && state.email != null) {
      // 재전송 API는 기존 이메일로 계정을 찾고 서버의 변경 예정 주소로 발송합니다.
      await client.auth.resend(
        type: state.pendingEmail == null ? OtpType.signup : OtpType.emailChange,
        email: state.email!,
        emailRedirectTo: authRedirectUrl,
      );
    } else {
      await client.auth.updateUser(
        UserAttributes(email: email),
        emailRedirectTo: authRedirectUrl,
      );
    }
    _requireOwner();
  }
}
