import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchHistoryItem {
  const SearchHistoryItem(this.query, this.at);
  final String query;
  final DateTime at;

  Map<String, dynamic> toJson() => {'q': query, 'at': at.toIso8601String()};

  static SearchHistoryItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final query = json['q'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    return query is String && query.isNotEmpty && at != null
        ? SearchHistoryItem(query, at)
        : null;
  }
}

/// 이 기기에 저장하는 최근 검색어입니다. 계정마다 따로 저장하고 최대 [limit]개까지 최신순으로 둡니다.
/// 자동저장을 끄면 새 검색어를 저장하지 않고 목록도 보여주지 않습니다.
class SearchHistory extends ChangeNotifier {
  SearchHistory({
    required this.scope,
    String? Function()? owner,
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String? value)? write,
    this.limit = 10,
  }) : _owner = owner ?? _currentUser,
       _read = read ?? ((key) => _prefs.getString(key)),
       _write = write ?? _writePrefs;

  /// 검색 종류(예: 'friend')입니다. 다른 검색과 기록을 섞지 않습니다.
  final String scope;
  final int limit;
  final String? Function() _owner;
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String? value) _write;

  static final _prefs = SharedPreferencesAsync();
  static Future<void> _writePrefs(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);
  static String? _currentUser() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  List<SearchHistoryItem> _items = const [];
  bool _enabled = true;
  bool _loaded = false;
  bool _disposed = false;

  List<SearchHistoryItem> get items => _items;
  bool get enabled => _enabled;
  bool get loaded => _loaded;

  String get _key => 'search-history:$scope:${_owner() ?? 'guest'}';

  Future<void> load() async {
    try {
      final saved = await _read(_key);
      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        _enabled = data['enabled'] != false;
        _items = [
          for (final item in data['items'] as List? ?? const [])
            ?SearchHistoryItem.fromJson(item),
        ].take(limit).toList();
      }
    } catch (_) {
      // 저장된 기록을 읽지 못하면 빈 기록으로 시작합니다.
    }
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() async {
    if (!_disposed) notifyListeners();
    try {
      await _write(
        _key,
        jsonEncode({
          'enabled': _enabled,
          'items': [for (final item in _items) item.toJson()],
        }),
      );
    } catch (_) {
      // 기기에 저장하지 못해도 이번 실행 동안은 화면에 그대로 둡니다.
    }
  }

  /// 검색한 말을 맨 위에 올립니다. 같은 말은 하나만 남깁니다.
  Future<void> add(String query, {DateTime? at}) async {
    final value = query.trim();
    if (!_enabled || value.isEmpty) return;
    _items = [
      SearchHistoryItem(value, at ?? DateTime.now()),
      ..._items.where((item) => item.query != value),
    ].take(limit).toList();
    await _save();
  }

  Future<void> remove(String query) async {
    _items = [..._items.where((item) => item.query != query)];
    await _save();
  }

  Future<void> clear() async {
    _items = const [];
    await _save();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
