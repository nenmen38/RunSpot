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

  /// 소셜 크루 탭에서 보고 있는 크루입니다.
  String? _selectedId;

  List<Crew> get crews => dashboard?.crews ?? const [];
  List<CrewInvite> get invites => dashboard?.invites ?? const [];

  /// 보고 있는 크루입니다. 고른 크루가 없어졌으면 첫 크루를 보여줍니다.
  Crew? get crew =>
      crews.where((crew) => crew.id == _selectedId).firstOrNull ??
      crews.firstOrNull;

  void select(String crewId) {
    if (_disposed || _selectedId == crewId) return;
    _selectedId = crewId;
    notifyListeners();
  }

  /// 내가 크루장인 크루 중 [userId] 친구가 아직 크루원이 아닌 크루입니다.
  List<Crew> inviteTargets(String userId) => [
    for (final crew in crews)
      if (crew.isOwner && !crew.hasMember(userId)) crew,
  ];

  /// 초대할 수 있는 크루마다 이미 초대를 보냈으면 true입니다.
  bool invitedEverywhere(String userId) {
    final targets = inviteTargets(userId);
    return targets.isNotEmpty &&
        targets.every((crew) => crew.pending.contains(userId));
  }

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

  /// 크루를 만들면 새 크루를 보고 있는 크루로 고릅니다.
  Future<String?> create(String name, String description, CrewIcon icon) async {
    final before = {for (final crew in crews) crew.id};
    final error = await _change(
      'create',
      () => service.create(name, description, icon),
      '크루를 만들지 못했습니다.',
    );
    final created = crews.where((crew) => !before.contains(crew.id));
    if (error == null && created.isNotEmpty) select(created.first.id);
    return error;
  }

  Future<String?> invite(String userId, String crewId) =>
      _change(userId, () => service.invite(userId, crewId), '크루원을 초대하지 못했습니다.');

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
