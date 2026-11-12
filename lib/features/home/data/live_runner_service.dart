import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/live_runner.dart';

abstract interface class LiveRunnerService {
  /// [paceSecPerKm]은 달리는 중일 때의 현재 페이스입니다. 친구의 오라 박자 맞춤에 씁니다.
  Future<void> publish(LocationFix fix, {int? paceSecPerKm});
  Future<void> stopSharing();
  Future<List<LiveRunner>> nearby(int radiusMeters, LocationFix origin);
  Future<void> connect(
    void Function() onChanged,
    void Function(bool) onConnection,
  );
  Future<void> disconnect();
}

class SupabaseLiveRunnerService implements LiveRunnerService {
  SupabaseLiveRunnerService(this.client)
    : _ownerId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _ownerId;
  RealtimeChannel? _channel;
  bool _paceSupported = true;

  void _requireOwner() {
    if (_ownerId == null || client.auth.currentSession?.user.id != _ownerId) {
      throw const AuthException('로그인이 필요합니다.');
    }
  }

  @override
  Future<void> publish(LocationFix fix, {int? paceSecPerKm}) async {
    _requireOwner();
    Future<void> send(int? pace) => client.rpc(
      'update_my_live_location',
      params: {
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracy_m': fix.accuracy,
        'pace_sec_per_km': ?pace,
      },
    );
    try {
      await send(_paceSupported ? paceSecPerKm : null);
    } on PostgrestException catch (error) {
      // 서버가 아직 페이스를 받지 못하는 버전이면 위치만 보내 공유가 끊기지 않게 합니다.
      if (error.code != 'PGRST202' || paceSecPerKm == null || !_paceSupported) {
        rethrow;
      }
      _paceSupported = false;
      await send(null);
    }
  }

  @override
  Future<void> stopSharing() async {
    _requireOwner();
    await client.rpc('stop_live_location');
  }

  @override
  Future<List<LiveRunner>> nearby(int radiusMeters, LocationFix origin) async {
    _requireOwner();
    final session = client.auth.currentSession!;
    final rows =
        await client
                .rpc(
                  'map_nearby_runners_at',
                  params: {
                    'radius_m': radiusMeters,
                    'viewer_latitude': origin.latitude,
                    'viewer_longitude': origin.longitude,
                  },
                )
                .setHeader('Authorization', 'Bearer ${session.accessToken}')
            as List<dynamic>;
    _requireOwner();
    return rows
        .map((row) => LiveRunner.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> connect(
    void Function() onChanged,
    void Function(bool) onConnection,
  ) async {
    _requireOwner();
    await disconnect();
    // 좌표를 방송하지 않고 변경 신호를 받은 뒤 서버 권한을 다시 확인합니다.
    _channel =
        client.channel(
            'runner-map',
            opts: const RealtimeChannelConfig(private: true),
          )
          ..onBroadcast(event: 'changed', callback: (_) => onChanged())
          ..subscribe((status, error) {
            onConnection(status == RealtimeSubscribeStatus.subscribed);
          });
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}
