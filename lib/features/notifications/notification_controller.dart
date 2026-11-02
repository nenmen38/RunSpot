import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runquest/shared/errors/server_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/notification_service.dart';
import 'models/app_notification.dart';

/// 확성기 버튼의 읽지 않은 알림 수와 알림창 목록을 관리합니다.
class NotificationController extends ChangeNotifier {
  NotificationController(
    this.service, {
    this.pollInterval = const Duration(minutes: 1),
    this.onGroupChanged,
  });

  final NotificationService service;
  final Duration pollInterval;

  /// 초대에 응답한 뒤 함께 달리기 화면을 새로 고칩니다.
  final VoidCallback? onGroupChanged;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  bool _active = false;
  Timer? _timer;
  int _generation = 0;
  int unreadCount = 0;
  List<AppNotification> items = const [];
  bool loading = false;

  /// 응답을 보내는 중인 초대 알림과 마지막 응답 실패 안내입니다.
  String? responding;
  String? respondError;
  String? error;

  /// 홈 화면이 보이는 동안에만 주기적으로 새 알림 수를 확인합니다.
  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (!active) return;
    unawaited(refreshCount());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refreshCount()));
  }

  bool _checkOwner() {
    if (service.isCurrentOwner) return true;
    unreadCount = 0;
    items = const [];
    return false;
  }

  /// 알림 수 확인은 화면을 방해하지 않도록 실패해도 조용히 넘어갑니다.
  Future<void> refreshCount() async {
    if (_disposed || loading) return;
    final generation = _generation;
    try {
      final count = await service.unreadCount().timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (_checkOwner()) unreadCount = count;
      notifyListeners();
    } catch (_) {}
  }

  /// 알림창을 열 때 목록을 불러오고, 보여준 알림까지 읽음으로 바꿉니다.
  Future<void> open() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await service.load().timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (!_checkOwner()) {
        error = '다시 로그인해 주세요.';
        return;
      }
      items = List.unmodifiable(loaded);
      final unread = loaded.where((item) => !item.read);
      if (unread.isNotEmpty) {
        final seenUntil = unread
            .map((item) => item.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        await service.markRead(seenUntil).timeout(_timeout);
        if (_disposed || generation != _generation) return;
      }
      unreadCount = 0;
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      error = exception is AuthException
          ? '다시 로그인해 주세요.'
          : exception is TimeoutException
          ? '응답이 지연됩니다. 잠시 후 다시 확인해 주세요.'
          : unexpectedServerError(exception, '알림을 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 초대를 수락·거절합니다. 성공하면 null, 실패하면 안내 문구를 반환합니다.
  Future<String?> respond(AppNotification item, {required bool accept}) async {
    final groupId = item.groupId;
    if (_disposed || responding != null || groupId == null) return null;
    responding = item.id;
    respondError = null;
    notifyListeners();
    String? failure;
    try {
      await service.respondToInvite(groupId, accept: accept).timeout(_timeout);
      onGroupChanged?.call();
    } catch (exception) {
      failure = switch (exception) {
        AuthException() => '다시 로그인해 주세요.',
        TimeoutException() => '응답이 지연됩니다. 잠시 후 다시 확인해 주세요.',
        PostgrestException(:final code?, :final message)
            when {'42501', '22023', 'P0001'}.contains(code) =>
          message,
        _ => unexpectedServerError(exception, '초대에 응답하지 못했습니다.'),
      };
    }
    if (_disposed) return failure;
    // 성공·실패와 관계없이 서버의 최신 초대 상태를 다시 보여줍니다.
    try {
      final loaded = await service.load().timeout(_timeout);
      if (!_disposed && _checkOwner()) items = List.unmodifiable(loaded);
    } catch (_) {}
    if (_disposed) return failure;
    responding = null;
    respondError = failure;
    notifyListeners();
    return failure;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
