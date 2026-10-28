import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AccountService {
  bool get isCurrentOwner;

  /// 서버에서 본인 계정과 연결된 자료를 지웁니다. 되돌릴 수 없습니다.
  Future<void> deleteMyAccount();

  /// 탈퇴 후 기기에 남은 로그인 정보를 지웁니다.
  Future<void> signOutLocally();
}

class SupabaseAccountService implements AccountService {
  SupabaseAccountService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  static const _boardBucket = 'board-images';

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  @override
  Future<void> deleteMyAccount() async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    // 게시판 사진 파일은 DB 연쇄 삭제로 지워지지 않으므로 계정을 지우기 전에 본인 폴더를 비웁니다.
    final bucket = client.storage.from(_boardBucket);
    for (var page = 0; ; page++) {
      final files = await bucket.list(
        path: _owner,
        searchOptions: const SearchOptions(limit: 100),
      );
      final paths = [
        for (final file in files)
          if (file.id != null) '$_owner/${file.name}',
      ];
      if (paths.isEmpty) break;
      final removed = await bucket.remove(paths);
      // 지워지지 않는 파일이 있으면 같은 목록을 계속 받으므로 멈추고 알립니다.
      if (removed.isEmpty || page >= 50) {
        throw const StorageException('게시판 사진을 지우지 못했습니다. 다시 시도해 주세요.');
      }
    }
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    await client
        .rpc('delete_my_account')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
  }

  @override
  Future<void> signOutLocally() =>
      client.auth.signOut(scope: SignOutScope.local);
}
