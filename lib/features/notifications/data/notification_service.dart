import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

abstract interface class NotificationService {
  bool get isCurrentOwner;
  Future<int> unreadCount();
  Future<List<AppNotification>> load();

  /// [seenUntil]까지 만들어진 알림을 읽음으로 바꿉니다.
  Future<void> markRead(DateTime seenUntil);

  /// 함께 달리기 초대를 수락하거나 거절합니다.
  Future<void> respondToInvite(String groupId, {required bool accept});

  /// 크루 초대를 수락하거나 거절합니다.
  Future<void> respondToCrewInvite(String crewId, {required bool accept});
}

class SupabaseNotificationService implements NotificationService {
  SupabaseNotificationService(this.client)
    : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return result;
  }

  @override
  Future<int> unreadCount() async =>
      await _rpc('unread_notification_count') as int;

  @override
  Future<List<AppNotification>> load() async => [
    for (final row in await _rpc('my_notifications') as List)
      AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  @override
  Future<void> respondToInvite(String groupId, {required bool accept}) async {
    await _rpc('group_action', {
      'requested_group': groupId,
      'operation': accept ? 'accept' : 'reject',
    });
  }

  @override
  Future<void> respondToCrewInvite(
    String crewId, {
    required bool accept,
  }) async {
    await _rpc('respond_crew_invite', {
      'requested_crew': crewId,
      'accept': accept,
    });
  }

  @override
  Future<void> markRead(DateTime seenUntil) async {
    await _rpc('mark_notifications_read', {
      'seen_until': seenUntil.toUtc().toIso8601String(),
    });
  }
}
