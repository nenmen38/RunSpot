import 'package:supabase_flutter/supabase_flutter.dart';

String? validateNickname(String value) {
  return RegExp(r'^[가-힣A-Za-z0-9_]{2,30}$').hasMatch(value)
      ? null
      : '닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.';
}

class NicknameState {
  const NicknameState({required this.verified, this.nickname, this.changedAt});
  final bool verified;
  final String? nickname;
  final DateTime? changedAt;

  DateTime? get nextChangeAt => changedAt?.add(const Duration(days: 30));
  bool canChange(DateTime now) =>
      verified && (nextChangeAt == null || !now.isBefore(nextChangeAt!));
}

abstract class NicknameService {
  Future<NicknameState> load();
  Future<void> save(String nickname);
}

class SupabaseNicknameService implements NicknameService {
  SupabaseNicknameService(this.client);
  final SupabaseClient client;

  @override
  Future<NicknameState> load() async {
    final verified = await client.rpc('my_phone_verified') == true;
    final profile = await client
        .from('profiles')
        .select('nickname,nickname_changed_at')
        .eq('id', client.auth.currentUser!.id)
        .single();
    return NicknameState(
      verified: verified,
      nickname: profile['nickname'] as String?,
      changedAt: DateTime.tryParse(
        profile['nickname_changed_at'] as String? ?? '',
      ),
    );
  }

  @override
  Future<void> save(String nickname) =>
      client.rpc('set_my_nickname', params: {'requested_nickname': nickname});
}
