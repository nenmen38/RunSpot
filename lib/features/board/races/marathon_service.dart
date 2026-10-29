import 'package:supabase_flutter/supabase_flutter.dart';

import 'marathon_event.dart';

class MarathonFeed {
  const MarathonFeed(this.events, this.syncedAt);
  final List<MarathonEvent> events;
  final DateTime? syncedAt;
}

abstract interface class MarathonService {
  Future<MarathonFeed> load();
}

class SupabaseMarathonService implements MarathonService {
  SupabaseMarathonService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  Future<MarathonFeed> load() async {
    if (_owner == null || client.auth.currentUser?.id != _owner) {
      throw const AuthException('다시 로그인해 주세요.');
    }
    final result = Map<String, dynamic>.from(
      await client.rpc('marathon_events') as Map,
    );
    if (client.auth.currentUser?.id != _owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return MarathonFeed(
      List.unmodifiable(
        (result['events'] as List).map(
          (e) => MarathonEvent.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      ),
      result['synced_at'] == null
          ? null
          : DateTime.parse(result['synced_at'] as String),
    );
  }
}
