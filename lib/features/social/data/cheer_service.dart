import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 러닝 중 친구 응원을 보내고 받습니다.
abstract interface class CheerService {
  bool get isCurrentOwner;

  /// 지금 달리고 있는 친구에게 응원을 보냅니다. 안 되면 이유를 담은 오류를 던집니다.
  Future<void> send(String userId);

  /// 아직 듣지 않은 응원을 가져옵니다(보낸 사람 닉네임). 가져간 응원은 다시 오지 않습니다.
  Future<List<String>> take();
}

class SupabaseCheerService implements CheerService {
  SupabaseCheerService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentUser?.id == _owner;

  @override
  Future<void> send(String userId) =>
      client.rpc<void>('send_cheer', params: {'target': userId});

  @override
  Future<List<String>> take() async => [
    for (final item in await client.rpc('take_my_cheers') as List? ?? const [])
      (item as Map)['nickname'] as String? ?? '친구',
  ];
}

/// 보낸 응원 결과 문구입니다(서버가 알려 준 이유가 있으면 그대로).
String cheerResultMessage(Object? error, String nickname) => switch (error) {
  null => '$nickname님에게 응원을 보냈어요 👏',
  PostgrestException(:final message, :final code)
      when code == 'P0001' || code == '42501' =>
    message,
  _ => '응원을 보내지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
};

/// 달리는 동안 20초마다 받은 응원을 확인해 [onCheer]로 알려 줍니다.
class CheerListener {
  CheerListener({
    required this.service,
    required this.onCheer,
    this.interval = const Duration(seconds: 20),
  });

  final CheerService service;
  final void Function(String nickname) onCheer;
  final Duration interval;
  Timer? _timer;
  bool _checking = false;

  bool get running => _timer != null;

  /// 러닝 중이면 확인을 시작하고, 아니면 멈춥니다.
  void setRunning(bool running) {
    if (running == this.running) return;
    _timer?.cancel();
    _timer = running ? Timer.periodic(interval, (_) => check()) : null;
  }

  @visibleForTesting
  Future<void> check() async {
    if (_checking || !service.isCurrentOwner) return;
    _checking = true;
    try {
      for (final nickname in await service.take()) {
        onCheer(nickname);
      }
    } catch (_) {
      // 응원을 못 가져와도 러닝 측정에는 영향이 없습니다.
    } finally {
      _checking = false;
    }
  }

  void dispose() => setRunning(false);
}
