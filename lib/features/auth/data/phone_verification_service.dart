import 'package:supabase_flutter/supabase_flutter.dart';

String? normalizePhone(String input) {
  final value = input.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^010\d{8}$').hasMatch(value)) {
    return '+82${value.substring(1)}';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value) ? value : null;
}

class PhoneVerificationState {
  const PhoneVerificationState({
    required this.verified,
    this.phone,
    this.pendingPhone,
  });
  final bool verified;
  final String? phone;
  final String? pendingPhone;
}

abstract interface class PhoneVerificationService {
  Future<PhoneVerificationState> load();
  Future<void> send(String phone);
  Future<void> verify(String phone, String code);
}

class SupabasePhoneVerification implements PhoneVerificationService {
  SupabasePhoneVerification(this.client)
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
  Future<PhoneVerificationState> load() async {
    final session = _requireOwner();
    final result = await client
        .rpc('my_phone_verification_state')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    final data = Map<String, dynamic>.from(result as Map);
    return PhoneVerificationState(
      verified: data['verified'] == true,
      phone: data['phone'] as String?,
      pendingPhone: data['pending_phone'] as String?,
    );
  }

  @override
  Future<void> send(String phone) async {
    final state = await load();
    _requireOwner();
    final existing = state.phone;
    if (state.verified &&
        existing != null &&
        existing.replaceFirst(RegExp(r'^\+'), '') ==
            phone.replaceFirst(RegExp(r'^\+'), '')) {
      return;
    }
    // 번호 등록·재전송은 실제 Auth 인증 흐름을 사용하며 확인 상태를 직접 쓰지 않습니다.
    await client.auth.updateUser(UserAttributes(phone: phone));
    _requireOwner();
  }

  @override
  Future<void> verify(String phone, String code) async {
    _requireOwner();
    final result = await client.auth.verifyOTP(
      phone: phone,
      token: code,
      type: OtpType.phoneChange,
    );
    if (result.user?.id != _ownerId) {
      await client.auth.signOut();
      throw const AuthException('계정 확인에 실패했습니다. 다시 로그인해 주세요.');
    }
    _requireOwner();
  }
}
