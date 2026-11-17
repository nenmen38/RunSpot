import 'package:supabase_flutter/supabase_flutter.dart';

/// 1km·5km·10km 중 하나의 개인 최고 기록입니다.
class PersonalRecord {
  const PersonalRecord({
    required this.kilometers,
    required this.duration,
    required this.runId,
    required this.startedAt,
  });

  PersonalRecord.fromJson(Map<String, dynamic> json)
    : kilometers = (json['distance_km'] as num).toInt(),
      duration = Duration(microseconds: (json['duration_us'] as num).toInt()),
      runId = json['run_id'] as String,
      startedAt = DateTime.parse(json['started_at'] as String).toLocal();

  final int kilometers;
  final Duration duration;
  final String runId;
  final DateTime startedAt;

  /// 1km당 평균 시간입니다.
  Duration get pace =>
      Duration(microseconds: duration.inMicroseconds ~/ kilometers);

  /// 최근 7일 안에 세운 기록이면 '신기록'으로 표시합니다.
  bool isRecent(DateTime now) =>
      now.difference(startedAt) < const Duration(days: 7);
}

abstract interface class PersonalRecordsService {
  bool get isCurrentOwner;
  Future<List<PersonalRecord>> load();
}

class SupabasePersonalRecordsService implements PersonalRecordsService {
  SupabasePersonalRecordsService(this.client)
    : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  @override
  Future<List<PersonalRecord>> load() async {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    final session = client.auth.currentSession!;
    final rows = await client
        .rpc('my_personal_records')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return [
      for (final row in rows as List)
        PersonalRecord.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
}
