import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/models/run_session.dart';
import 'data/run_record_service.dart';
import 'models/run_record.dart';

class RunHistoryController extends ChangeNotifier {
  RunHistoryController(this.service);
  final RunRecordService service;
  static const pageSize = 20;
  List<RunRecord> records = [];
  bool loading = false;
  bool hasMore = true;
  String? error;
  int _offset = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _retryRefresh = true;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<RunRecord> save(RunSummary summary) async {
    final record = await service.save(summary);
    if (!_disposed) await refresh();
    return record;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    _retryRefresh = true;
    loading = true;
    error = null;
    _notify();
    try {
      final rows = await service.list(offset: 0, limit: pageSize);
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
      final rows = await service.list(offset: _offset, limit: pageSize);
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
    super.dispose();
  }
}
