import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/errors/server_error.dart';
import 'data/crew_service.dart';
import 'models/crew.dart';

/// 내 크루와 받은 초대를 관리합니다. 모든 결과는 서버가 돌려준 상태로 바꿉니다.
class CrewController extends ChangeNotifier {
  CrewController(this.service);

  final CrewService service;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  int _generation = 0;
  CrewDashboard? dashboard;
  bool loading = false;
  String? error;

  /// 처리 중인 작업 대상입니다. 초대 중인 친구 ID나 응답 중인 크루 ID가 들어갑니다.
  String? busy;

  Crew? get crew => dashboard?.crew;
  List<CrewInvite> get invites => dashboard?.invites ?? const [];
  bool get isOwner => crew?.isOwner ?? false;

  /// 크루장에게 [userId] 친구의 초대 버튼을 보여줄지 정합니다. 이미 크루원이면 숨깁니다.
  bool canInvite(String userId) =>
      isOwner && !(crew?.hasMember(userId) ?? true);
  bool invited(String userId) => crew?.pending.contains(userId) ?? false;

  String _message(Object exception, String fallback) => switch (exception) {
    AuthException() => '다시 로그인해 주세요.',
    TimeoutException() => '응답이 지연됩니다. 잠시 후 다시 확인해 주세요.',
    PostgrestException(:final code?, :final message)
        when {'42501', '22023', 'P0001'}.contains(code) =>
      message,
    _ => unexpectedServerError(exception, fallback),
  };

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await service.load().timeout(_timeout);
      if (_disposed || generation != _generation) return;
      dashboard = result;
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      error = _message(exception, '크루 정보를 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<String?> _change(
    String target,
    Future<CrewDashboard> Function() action,
    String fallback,
  ) async {
    if (_disposed || busy != null) return null;
    busy = target;
    ++_generation;
    notifyListeners();
    String? failure;
    try {
      final result = await action().timeout(_timeout);
      if (!_disposed) dashboard = result;
    } catch (exception) {
      failure = _message(exception, fallback);
    }
    if (_disposed) return failure;
    busy = null;
    notifyListeners();
    return failure;
  }

  Future<String?> create(String name, String description, CrewIcon icon) =>
      _change(
        'create',
        () => service.create(name, description, icon),
        '크루를 만들지 못했습니다.',
      );

  Future<String?> invite(String userId) =>
      _change(userId, () => service.invite(userId), '크루원을 초대하지 못했습니다.');

  Future<String?> respond(String crewId, {required bool accept}) => _change(
    crewId,
    () => service.respond(crewId, accept: accept),
    '크루 초대에 응답하지 못했습니다.',
  );

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
