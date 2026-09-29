import 'package:supabase_flutter/supabase_flutter.dart';

String? normalizePhone(String input) {
  final value = input.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^010\d{8}$').hasMatch(value)) {
    return '+82${value.substring(1)}';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value) ? value : null;
}

abstract class PhoneVerificationService {
  Future<bool> isVerified();
  Future<void> send(String phone);
  Future<void> verify(String phone, String code);
  Future<void> signOut();
}

class SupabasePhoneVerification implements PhoneVerificationService {
  SupabasePhoneVerification(this.client);
  final SupabaseClient client;

  @override
  Future<bool> isVerified() async {
    return await client.rpc('my_phone_verified') == true;
  }

  @override
  Future<void> send(String phone) async {
    await client.auth.updateUser(UserAttributes(phone: phone));
  }

  @override
  Future<void> verify(String phone, String code) async {
    final expectedId = client.auth.currentUser?.id;
    if (expectedId == null) throw const AuthException('인증 세션이 만료되었습니다.');
    final result = await client.auth.verifyOTP(
      phone: phone,
      token: code,
      type: OtpType.phoneChange,
    );
    if (result.user?.id != expectedId) {
      await client.auth.signOut();
      throw const AuthException('계정 확인에 실패했습니다. 다시 로그인해 주세요.');
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
