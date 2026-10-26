import 'package:supabase_flutter/supabase_flutter.dart';

import '../../run_history/models/run_split.dart';
import '../../run_history/models/run_motion_evidence.dart';

class IntegrityReview {
  IntegrityReview.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      nickname = json['nickname'] as String,
      distance = json['distance_m'] as int,
      seconds = json['duration_sec'] as int,
      risk = json['risk'] as int,
      rule = json['rule'] as String? ?? 'average_speed_over_6_5',
      splits = RunSplit.decode(json['splits']),
      motionEvidence = RunMotionEvidence.decode(json['motion_evidence']);
  final String id;
  final String nickname;
  final int distance;
  final int seconds;
  final int risk;
  final String rule;
  final List<RunSplit>? splits;
  final List<RunMotionEvidence>? motionEvidence;
}

abstract interface class ReviewService {
  bool get isCurrentOwner;
  Future<List<IntegrityReview>> load();
  Future<void> resolve(
    String id, {
    required bool approved,
    required String note,
  });
}

class SupabaseReviewService implements ReviewService {
  SupabaseReviewService(this.client) : _owner = client.auth.currentUser?.id;
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

  Future<bool> canAccessManagement() async =>
      await _rpc('can_access_management') == true;

  Future<List<Map<String, dynamic>>> loadBoardReports() async =>
      (await _rpc('board_report_cases') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  Future<void> resolveBoardReport(
    String id,
    String decision,
    String note,
  ) async => await _rpc('resolve_board_report', {
    'report_id': id,
    'decision': decision,
    'note': note,
  });

  @override
  Future<List<IntegrityReview>> load() async =>
      (await _rpc('review_cases') as List)
          .map(
            (row) =>
                IntegrityReview.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
  @override
  Future<void> resolve(
    String id, {
    required bool approved,
    required String note,
  }) async {
    await _rpc('resolve_review', {
      'case_id': id,
      'decision': approved ? 'approved' : 'rejected',
      'note': note,
    });
  }
}
