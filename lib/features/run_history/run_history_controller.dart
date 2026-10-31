import 'dart:async';
import 'dart:math' as math;

import '../diagnostics/error_reporter.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/models/run_session.dart';
import 'data/run_outbox.dart';
import 'data/run_record_service.dart';
import 'models/run_record.dart';
import 'models/run_route.dart';

class RunHistoryController extends ChangeNotifier {
  RunHistoryController(this.service, {required this.outbox}) {
    if (service.ownerId != outbox.ownerId) {
      throw ArgumentError('기록 저장소의 계정이 일치하지 않습니다.');
    }
  }
  final RunRecordService service;
  final RunOutbox outbox;
  static const pageSize = 20;
  static const requestTimeout = Duration(seconds: 20);
  List<RunRecord> records = [];
  List<RunRecord> pendingRecords = [];
  bool syncing = false;
  String? syncError;
  bool loading = false;
  bool hasMore = true;
  String? error;
  int _offset = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _retryRefresh = true;
  bool _foreground = true;
  bool _automatic = false;
  bool _retryable = true;
  int _failures = 0;
  Timer? _retryTimer;
  Future<void> _writes = Future.value();
  Future<void> _localWrites = Future.value();
  Future<void>? _syncFuture;

  List<RunRecord> get hiddenRecords =>
      records.where((record) => record.hidden).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  Future<void> setHidden(RunRecord record, bool hidden) => _enqueue(() async {
    _requireOwner();
    if (record.pendingSync) {
      throw const RunOutboxException('서버 저장 후 숨길 수 있습니다.');
    }
    await service.setHidden(record.id, hidden).timeout(requestTimeout);
    _requireOwner();
    records = records
        .map((item) => item.id == record.id ? item.withHidden(hidden) : item)
        .toList();
    _notify();
  });

  List<RunRecord> get visibleRecords {
    final pendingIds = pendingRecords.map((row) => row.clientRunId).toSet();
    return [
      ...pendingRecords,
      ...records.where(
        (row) => !row.hidden && !pendingIds.contains(row.clientRunId),
      ),
    ]..sort((a, b) {
      final date = b.startedAt.compareTo(a.startedAt);
      return date == 0 ? b.clientRunId.compareTo(a.clientRunId) : date;
    });
  }

  bool isPending(String clientRunId) =>
      pendingRecords.any((row) => row.clientRunId == clientRunId);

  Future<RunRoute> loadRoute(RunRecord record) async {
    _requireOwner();
    if (record.route != null) return record.route!;
    final route = await service.loadRoute(record.id).timeout(requestTimeout);
    _requireOwner();
    return route;
  }

  bool get _canUpload => !_disposed && _foreground && service.isCurrentOwner;

  void _requireOwner() {
    if (_disposed || !service.isCurrentOwner) {
      throw const AuthException('로그인 상태를 확인해 주세요.');
    }
  }

  // 수동 저장과 자동 복구가 같은 기록을 동시에 전송하지 않도록 직렬화합니다.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<RunRecord> save(RunSummary summary) async {
    _requireOwner();
    // 이전 기록의 느린 서버 전송이 새 기록의 디스크 저장을 막지 않게 분리합니다.
    final persisted = _localWrites.then((_) async {
      _requireOwner();
      await outbox.put(summary);
    });
    _localWrites = persisted.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await persisted;
    } catch (_, stack) {
      ErrorReporter.report('run_storage', stack);
      rethrow;
    }
    final pending = RunRecord.pending(summary);
    if (_disposed || !service.isCurrentOwner) return pending;
    pendingRecords = [
      pending,
      ...pendingRecords.where((row) => row.clientRunId != summary.clientRunId),
    ];
    _notify();
    final record = await _enqueue(() async {
      if (!_canUpload) return pending;
      try {
        final saved = await _upload(summary);
        syncError = null;
        _failures = 0;
        return saved;
      } catch (failure, stack) {
        ErrorReporter.report('run_upload', stack);
        if (!_disposed && service.isCurrentOwner) {
          syncError = message(failure);
          _retryable = _canRetry(failure);
          _failures++;
        }
        return pending;
      } finally {
        _scheduleRetry();
        _notify();
      }
    });
    if (!record.pendingSync && !_disposed) await _refreshRecords();
    return record;
  }

  Future<RunRecord> _upload(RunSummary summary) async {
    _requireOwner();
    final saved = await service.save(summary).timeout(requestTimeout);
    _requireOwner();
    // 응답을 못 받았거나 삭제가 실패하면 원본을 남겨 같은 식별자로 재시도합니다.
    await outbox.remove(summary.clientRunId);
    if (!_disposed && service.isCurrentOwner) {
      pendingRecords = pendingRecords
          .where((row) => row.clientRunId != summary.clientRunId)
          .toList();
      records = [
        saved,
        ...records.where((row) => row.clientRunId != saved.clientRunId),
      ];
    }
    return saved;
  }

  Future<void> setActive(bool active) async {
    if (_disposed) return;
    _foreground = active;
    _automatic = true;
    _retryTimer?.cancel();
    if (active) {
      // 복귀 시 이전 전송이 끝나길 기다린 뒤 보관 목록을 다시 확인합니다.
      await _syncFuture;
      if (_canUpload) await syncPending();
    }
  }

  Future<void> syncPending({bool refreshRecords = true}) {
    if (_disposed) return Future.value();
    return _syncFuture ??= _syncPending(refreshRecords).whenComplete(() {
      _syncFuture = null;
    });
  }

  Future<void> _syncPending(bool refreshRecords) async {
    final uploaded = await _enqueue(() async {
      if (!_canUpload) return false;
      _retryTimer?.cancel();
      syncing = true;
      syncError = null;
      _retryable = false;
      _notify();
      var uploaded = false;
      var failed = false;
      try {
        final summaries = await outbox.list();
        if (_disposed || !service.isCurrentOwner) return false;
        pendingRecords = summaries.map(RunRecord.pending).toList();
        _notify();
        for (final summary in summaries) {
          if (!_canUpload) break;
          try {
            await _upload(summary);
            uploaded = true;
          } catch (failure, stack) {
            ErrorReporter.report('run_upload', stack);
            failed = true;
            if (!_disposed && service.isCurrentOwner) {
              syncError = message(failure);
              _retryable = _retryable || _canRetry(failure);
            }
          }
          _notify();
        }
      } catch (failure, stack) {
        ErrorReporter.report('run_upload', stack);
        failed = true;
        if (!_disposed && service.isCurrentOwner) {
          syncError = message(failure);
          _retryable = _canRetry(failure);
        }
      } finally {
        if (!failed && pendingRecords.isNotEmpty) _retryable = true;
        _failures = failed ? _failures + 1 : 0;
        syncing = false;
        _scheduleRetry();
        _notify();
      }
      return uploaded;
    });
    if (uploaded && refreshRecords && !_disposed) await _refreshRecords();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!_automatic ||
        !_canUpload ||
        !_retryable ||
        (pendingRecords.isEmpty && syncError == null)) {
      return;
    }
    final seconds = math.min(
      300,
      30 * (1 << math.min(math.max(0, _failures - 1), 4)),
    );
    _retryTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(syncPending()),
    );
  }

  static bool _canRetry(Object failure) =>
      failure is! PostgrestException ||
      !['42501', '22023', 'PGRST202', '42883'].contains(failure.code);

  Future<void> refresh() async {
    await syncPending(refreshRecords: false);
    if (!_disposed) await _refreshRecords();
  }

  Future<void> _refreshRecords() async {
    if (_disposed) return;
    final generation = ++_generation;
    _retryRefresh = true;
    loading = true;
    error = null;
    _notify();
    try {
      _requireOwner();
      final rows = await service
          .list(offset: 0, limit: pageSize)
          .timeout(requestTimeout);
      _requireOwner();
      if (_disposed || generation != _generation) return;
      records = rows;
      _offset = rows.length;
      hasMore = rows.length == pageSize;
    } catch (failure) {
      if (!_disposed && generation == _generation) error = message(failure);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    final generation = _generation;
    _retryRefresh = false;
    loading = true;
    error = null;
    _notify();
    try {
      _requireOwner();
      final rows = await service
          .list(offset: _offset, limit: pageSize)
          .timeout(requestTimeout);
      _requireOwner();
      if (_disposed || generation != _generation) return;
      final ids = records.map((record) => record.id).toSet();
      records = [...records, ...rows.where((record) => ids.add(record.id))];
      _offset += rows.length;
      hasMore = rows.length == pageSize;
    } catch (failure) {
      if (!_disposed && generation == _generation) error = message(failure);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  static String message(Object failure) {
    if (failure is RunOutboxException) return failure.message;
    if (failure is AuthException) return '로그인 상태를 확인해 주세요.';
    if (failure is PostgrestException) {
      if (failure.code == '42501' || failure.code == '22023') {
        return failure.message;
      }
      if (failure.code == 'PGRST202' || failure.code == '42883') {
        return '서버의 러닝 기록 저장 기능 설정이 필요합니다.';
      }
    }
    return '서버에 연결하지 못했습니다. 다시 시도해 주세요.';
  }

  Future<void> retry() => _retryRefresh ? refresh() : loadMore();

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retryTimer?.cancel();
    records = [];
    pendingRecords = [];
    // 진행 중인 디스크 쓰기가 끝난 후 닫으며, 로그아웃해도 미전송 원본은 보관합니다.
    unawaited(
      _localWrites
          .then((_) => _writes)
          .then((_) => outbox.close())
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
