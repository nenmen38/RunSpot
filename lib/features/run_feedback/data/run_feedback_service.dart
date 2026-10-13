import 'package:supabase_flutter/supabase_flutter.dart';

enum FeedbackStatus {
  available,
  ready,
  cooldown,
  processing,
  insufficientData,
  emailRequired,
  generationFailed,
  notConfigured,
  budgetExhausted,
}

class RunFeedbackState {
  const RunFeedbackState({
    required this.status,
    this.message,
    this.createdAt,
    this.nextAvailableAt,
  });
  final FeedbackStatus status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? nextAvailableAt;

  factory RunFeedbackState.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'available' => FeedbackStatus.available,
      'ready' => FeedbackStatus.ready,
      'cooldown' => FeedbackStatus.cooldown,
      'processing' => FeedbackStatus.processing,
      'insufficient_data' => FeedbackStatus.insufficientData,
      'email_required' => FeedbackStatus.emailRequired,
      'generation_failed' => FeedbackStatus.generationFailed,
      'not_configured' => FeedbackStatus.notConfigured,
      'budget_exhausted' => FeedbackStatus.budgetExhausted,
      _ => throw const FormatException('피드백 응답이 올바르지 않습니다.'),
    };
    final message = json['message'] as String?;
    final created = DateTime.tryParse(json['created_at'] as String? ?? '');
    final next = DateTime.tryParse(json['next_available_at'] as String? ?? '');
    if (status == FeedbackStatus.ready &&
        (message == null ||
            message.isEmpty ||
            message.runes.length > 500 ||
            created == null)) {
      throw const FormatException('피드백 내용이 올바르지 않습니다.');
    }
    if ([
          FeedbackStatus.cooldown,
          FeedbackStatus.processing,
          FeedbackStatus.generationFailed,
        ].contains(status) &&
        next == null) {
      throw const FormatException('피드백 제한 시각이 올바르지 않습니다.');
    }
    return RunFeedbackState(
      status: status,
      message: message,
      createdAt: created,
      nextAvailableAt: next,
    );
  }
}

abstract interface class RunFeedbackService {
  bool get isCurrentOwner;
  Future<RunFeedbackState> load(String runId);
  Future<RunFeedbackState> generate(String runId);
}

class SupabaseRunFeedbackService implements RunFeedbackService {
  SupabaseRunFeedbackService(this.client)
    : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Session _session() {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return client.auth.currentSession!;
  }

  @override
  Future<RunFeedbackState> load(String runId) async {
    final session = _session();
    final result = await client
        .rpc('my_run_feedback', params: {'requested_run_id': runId})
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _session();
    return RunFeedbackState.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<RunFeedbackState> generate(String runId) async {
    final session = _session();
    final response = await client.functions.invoke(
      'run-feedback',
      body: {'run_id': runId},
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    _session();
    return RunFeedbackState.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
