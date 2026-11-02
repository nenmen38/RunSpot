import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/live_runner.dart';

abstract interface class LiveRunnerService {
  Future<void> publish(LocationFix fix);
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

  void _requireOwner() {
    if (_ownerId == null || client.auth.currentSession?.user.id != _ownerId) {
      throw const AuthException('로그인이 필요합니다.');
    }
  }

  @override
  Future<void> publish(LocationFix fix) async {
    _requireOwner();
    await client.rpc(
      'update_my_live_location',
      params: {
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracy_m': fix.accuracy,
      },
    );
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
