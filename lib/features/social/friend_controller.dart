import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/data/nickname_service.dart';
import 'data/friend_service.dart';
import 'models/friend_entry.dart';

class FriendController extends ChangeNotifier {
  FriendController(this.service);

  final FriendService service;
  static const _timeout = Duration(seconds: 15);
  List<FriendEntry> _entries = const [];
  List<FriendEntry> _results = const [];
  Timer? _timer;
  bool _disposed = false;
  bool _active = false;
  int _loadGeneration = 0;
  int _searchGeneration = 0;
  String _query = '';
  bool loading = false;
  bool searching = false;
  bool loaded = false;
  int revision = 0;
  bool searched = false;
  bool canInteract = false;
  String? busyUserId;
  String? error;
  String? searchError;

  List<FriendEntry> get friends {
    final items =
        _entries
            .where((entry) => entry.relation == FriendRelation.friend)
            .toList()
          ..sort(
            (a, b) =>
                a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
          );
    return List.unmodifiable(items);
  }

  List<FriendEntry> get received => List.unmodifiable(
    _entries.where((entry) => entry.relation == FriendRelation.received),
  );
  List<FriendEntry> get sent => List.unmodifiable(
    _entries.where((entry) => entry.relation == FriendRelation.sent),
  );
  List<FriendEntry> get results => _results;

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (active) {
      unawaited(refresh());
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!loading && busyUserId == null) unawaited(refresh(silent: true));
      });
    } else {
      ++_loadGeneration;
      ++_searchGeneration;
      loading = false;
      searching = false;
    }
  }

  bool _checkOwner() {
    if (service.isCurrentOwner) return true;
    _entries = const [];
    _results = const [];
    canInteract = false;
    error = '다시 로그인해 주세요.';
    _timer?.cancel();
    return false;
  }

  String _message(Object exception, String fallback) {
    if (exception is AuthException) return '다시 로그인해 주세요.';
    if (exception is TimeoutException) return '응답이 지연됩니다. 새로고침 후 상태를 확인해 주세요.';
    if (exception is PostgrestException) {
      if (exception.code == '42501') {
        return '인증 상태와 공개 설정을 확인하거나 목록을 새로고침해 주세요.';
      }
      if (exception.code == 'P0001' || exception.code == '22023') {
        return exception.message;
      }
    }
    return fallback;
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || busyUserId != null) return;
    await _refresh(silent: silent);
    if (!_disposed && _query.isNotEmpty && searched && canInteract) {
      await _search(_query);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final generation = ++_loadGeneration;
    loading = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      final dashboard = await service.load().timeout(_timeout);
      if (_disposed || generation != _loadGeneration) return;
      if (_checkOwner()) {
        _entries = dashboard.entries;
        canInteract = dashboard.canInteract;
        loaded = true;
        error = null;
        // 인증이 취소되면 이전 검색 결과도 즉시 지웁니다.
        if (!canInteract) queryChanged('');
      }
    } catch (exception) {
      if (_disposed || generation != _loadGeneration) return;
      if (_checkOwner()) {
        error = _message(exception, '친구 목록을 불러오지 못했습니다.');
        if (exception is PostgrestException && exception.code == '42501') {
          _entries = const [];
          canInteract = false;
          queryChanged('');
        }
      }
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        loading = false;
        ++revision;
        notifyListeners();
      }
    }
  }

  void queryChanged(String value) {
    if (_disposed) return;
    ++_searchGeneration;
    _query = value.trim();
    _results = const [];
    searched = false;
    searching = false;
    searchError = null;
    notifyListeners();
  }

  Future<void> search(String value) async {
    if (_disposed || busyUserId != null || !canInteract) return;
    await _search(value);
  }

  Future<void> _search(String value) async {
    queryChanged(value);
    final invalid = validateNickname(_query);
    if (invalid != null) {
      searchError = invalid;
      notifyListeners();
      return;
    }
    final generation = ++_searchGeneration;
    searching = true;
    notifyListeners();
    try {
      final matches = await service.search(_query).timeout(_timeout);
      if (_disposed || generation != _searchGeneration) return;
      if (_checkOwner()) {
        _results = List.unmodifiable(matches);
        searched = true;
      }
    } catch (exception) {
      if (_disposed || generation != _searchGeneration) return;
      if (_checkOwner()) {
        searchError = _message(exception, '검색하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (!_disposed && generation == _searchGeneration) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<bool> change(FriendEntry entry, FriendAction action) async {
    if (_disposed || busyUserId != null || !_checkOwner()) return false;
    if (!canInteract &&
        (action == FriendAction.request || action == FriendAction.accept)) {
      return false;
    }
    ++_loadGeneration;
    ++_searchGeneration;
    loading = false;
    searching = false;
    busyUserId = entry.userId;
    error = null;
    notifyListeners();
    var success = false;
    String? failure;
    try {
      await service.change(entry, action).timeout(_timeout);
      if (!_disposed && _checkOwner()) success = true;
    } catch (exception) {
      if (!_disposed && _checkOwner()) {
        failure = _message(exception, '친구 상태를 변경하지 못했습니다.');
      }
    }
    if (_disposed) return false;
    // 성공을 낙관적으로 표시하지 않고 서버 상태를 다시 조회합니다.
    if (_checkOwner()) {
      await _refresh();
      if (!_disposed && _query.isNotEmpty && canInteract) await _search(_query);
      if (!_disposed && failure != null) {
        error = failure;
        notifyListeners();
      }
    }
    if (!_disposed) {
      busyUserId = null;
      notifyListeners();
    }
    return success;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_loadGeneration;
    ++_searchGeneration;
    _timer?.cancel();
    super.dispose();
  }
}
