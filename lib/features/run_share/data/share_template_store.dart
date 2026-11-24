import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/share_edits.dart';
import '../models/share_layout.dart';

class SavedShareTemplate {
  SavedShareTemplate({
    required this.id,
    required this.name,
    required this.layout,
    required ShareEdits edits,
  }) : edits = ShareEdits(
         visible: edits.visible,
         placements: edits.placements,
         useTemplatePlacement: edits.useTemplatePlacement,
       );

  final String id;
  final String name;
  final ShareLayout layout;
  final ShareEdits edits;

  factory SavedShareTemplate.fromJson(Map<String, dynamic> json) {
    final placements = <ShareSticker, StickerPlacement>{};
    for (final entry in (json['placements'] as Map).entries) {
      final values = entry.value as List;
      final x = (values[0] as num).toDouble();
      final y = (values[1] as num).toDouble();
      final scale = (values[2] as num).toDouble();
      if (!x.isFinite || !y.isFinite || !scale.isFinite || scale <= 0) {
        throw const FormatException('스티커 배치가 올바르지 않습니다.');
      }
      placements[ShareSticker.values.byName(entry.key as String)] = (
        center: Offset(x, y),
        scale: scale,
      );
    }
    return SavedShareTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      layout: ShareLayout.values.byName(json['layout'] as String),
      edits: ShareEdits(
        visible: (json['visible'] as List).cast<String>().map(
          ShareSticker.values.byName,
        ),
        placements: placements,
        useTemplatePlacement: json['useTemplatePlacement'] == true,
      ),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'layout': layout.name,
    'visible': [for (final sticker in edits.visible) sticker.name],
    'useTemplatePlacement': edits.useTemplatePlacement,
    'placements': {
      for (final entry in edits.placements.entries)
        entry.key.name: [
          entry.value.center.dx,
          entry.value.center.dy,
          entry.value.scale,
        ],
    },
  };
}

/// 계정별로 배치만 기기에 저장합니다. 사진, 경로와 건강 수치는 저장하지 않습니다.
class ShareTemplateStore {
  ShareTemplateStore(String ownerId) : _key = 'share_templates_v1.$ownerId';

  final String _key;
  late final _preferences = SharedPreferencesAsync();
  static final _pendingWrites = <String, Future<void>>{};

  Future<List<SavedShareTemplate>> load() async {
    final stored = await _preferences.getString(_key);
    if (stored == null) return [];
    return [
      for (final item in jsonDecode(stored) as List)
        SavedShareTemplate.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<List<SavedShareTemplate>> add(SavedShareTemplate template) =>
      _update((templates) => [...templates, template]);

  Future<List<SavedShareTemplate>> delete(String id) => _update(
    (templates) => templates.where((template) => template.id != id).toList(),
  );

  // 같은 계정의 여러 화면에서 수정해도 저장 직전에 최신 목록을 읽습니다.
  Future<List<SavedShareTemplate>> _update(
    List<SavedShareTemplate> Function(List<SavedShareTemplate>) change,
  ) async {
    final previous = _pendingWrites[_key] ?? Future<void>.value();
    final result = previous.then((_) async {
      final templates = change(await load());
      await _preferences.setString(_key, jsonEncode(templates));
      return templates;
    });
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pendingWrites[_key] = completed;
    try {
      return await result;
    } finally {
      if (identical(_pendingWrites[_key], completed)) {
        _pendingWrites.remove(_key);
      }
    }
  }
}
