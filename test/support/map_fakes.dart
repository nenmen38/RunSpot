import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:runquest/shared/maps/run_map.dart';

class FakeMapBridge implements MapBridge {
  final updates = <Map<String, Object?>>[];
  void Function(String)? onMessage;
  void Function(String)? onError;
  bool disposed = false;
  bool autoReady = true;
  Completer<void>? pendingUpdate;
  void emit(Map<String, Object?> event) => onMessage?.call(jsonEncode(event));
  @override
  Future<void> initialize(
    void Function(String) onMessage,
    void Function(String) onError,
  ) async {
    this.onMessage = onMessage;
    this.onError = onError;
    if (autoReady) scheduleMicrotask(() => emit({'type': 'ready'}));
  }

  @override
  Future<void> update(Map<String, Object?> data) async {
    updates.add(data);
    await pendingUpdate?.future;
  }

  @override
  Widget build() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: (_) => emit({'type': 'gesture'}),
    onPanUpdate: (_) => emit({
      'type': 'camera',
      'latitude': 37.56,
      'longitude': 126.97,
      'zoom': 18,
    }),
    child: const ColoredBox(color: Color(0xFFE9F0EC), child: SizedBox.expand()),
  );
  @override
  void dispose() {
    disposed = true;
  }
}
