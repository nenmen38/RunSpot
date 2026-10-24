import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'kakao_map_bridge.dart';
import 'run_map_controller.dart';

export 'kakao_map_bridge.dart' show MapBridge, MapBridgeFactory;
export 'run_map_controller.dart';

class RunMapMarker {
  const RunMapMarker({
    required this.id,
    required this.point,
    required this.nickname,
    this.selected = false,
    this.memberCount = 1,
  });
  final String id;
  final LatLng point;
  final String nickname;
  final bool selected;
  final int memberCount;
  Map<String, Object?> toJson() => {
    'id': id,
    'point': [point.latitude, point.longitude],
    'nickname': nickname,
    'selected': selected,
    'memberCount': memberCount,
  };
}

class RunMap extends StatefulWidget {
  const RunMap({
    required this.controller,
    this.position,
    this.markers = const [],
    this.segments = const [],
    this.endpoints = false,
    this.onReady,
    this.onGesture,
    this.onTap,
    this.onMarkerTap,
    this.bridgeFactory,
    super.key,
  });
  final RunMapController controller;
  final LatLng? position;
  final List<RunMapMarker> markers;
  final List<List<LatLng>> segments;
  final bool endpoints;
  final VoidCallback? onReady;
  final VoidCallback? onGesture;
  final VoidCallback? onTap;
  final ValueChanged<String>? onMarkerTap;
  final MapBridgeFactory? bridgeFactory;
  @override
  State<RunMap> createState() => _RunMapState();
}

class _RunMapState extends State<RunMap> {
  MapBridge? _bridge;
  bool _ready = false;
  String? _error;
  Timer? _timeout;
  int _generation = 0;
  bool _sending = false;
  bool _dirty = false;
  String? _lastData;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_publish);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    _timeout?.cancel();
    _bridge?.dispose();
    _ready = false;
    _lastData = null;
    final bridge = _bridge = widget.bridgeFactory?.call() ?? KakaoMapBridge();
    _timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && generation == _generation && !_ready) {
        _failed('지도 연결이 지연되고 있습니다. 다시 시도해 주세요.');
      }
    });
    try {
      await bridge.initialize(
        (message) {
          if (mounted && generation == _generation) _message(message);
        },
        (error) {
          if (mounted && generation == _generation) _failed(error);
        },
      );
      if (mounted && generation == _generation) setState(() {});
    } catch (_) {
      if (mounted && generation == _generation) {
        _failed('지도를 불러오지 못했습니다. 다시 시도해 주세요.');
      }
    }
  }

  void _failed(String message) {
    _timeout?.cancel();
    _ready = false;
    if (mounted) setState(() => _error = message);
  }

  void _message(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;
      switch (data['type']) {
        case 'ready':
          if (_ready || _error != null) return;
          _timeout?.cancel();
          setState(() => _ready = true);
          widget.onReady?.call();
          _publish();
        case 'gesture':
          if (_ready) widget.onGesture?.call();
        case 'tap':
          if (_ready) widget.onTap?.call();
        case 'marker':
          final id = data['id'];
          if (_ready &&
              id is String &&
              widget.markers.any((marker) => marker.id == id)) {
            widget.onMarkerTap?.call(id);
          }
        case 'camera':
          final lat = data['latitude'],
              lng = data['longitude'],
              zoom = data['zoom'];
          if (!_ready ||
              lat is! num ||
              lng is! num ||
              zoom is! num ||
              !lat.isFinite ||
              !lng.isFinite ||
              !zoom.isFinite ||
              lat.abs() > 90 ||
              lng.abs() > 180 ||
              zoom < 6 ||
              zoom > 19) {
            return;
          }
          widget.controller.acceptCamera(
            LatLng(lat.toDouble(), lng.toDouble()),
            zoom.toDouble(),
          );
        case 'error':
          _failed('카카오 지도 연결에 실패했습니다. 키·도메인 등록과 네트워크를 확인해 주세요.');
      }
    } on FormatException {
      return;
    }
  }

  Map<String, Object?> _data() => {
    'camera': widget.controller.command,
    'position': widget.position == null
        ? null
        : [widget.position!.latitude, widget.position!.longitude],
    'markers': widget.markers.map((m) => m.toJson()).toList(),
    'segments': widget.segments
        .map((s) => s.map((p) => [p.latitude, p.longitude]).toList())
        .toList(),
    'endpoints': widget.endpoints,
  };

  void _publish() {
    _dirty = true;
    if (_ready && !_sending) unawaited(_send());
  }

  Future<void> _send() async {
    _sending = true;
    final generation = _generation;
    try {
      while (mounted && _ready && generation == _generation && _dirty) {
        _dirty = false;
        final data = _data();
        final encoded = jsonEncode(data);
        if (encoded == _lastData) continue;
        await _bridge!.update(data);
        if (generation == _generation) _lastData = encoded;
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _failed('지도를 갱신하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      _sending = false;
      if (mounted && _ready && _dirty) _publish();
    }
  }

  @override
  void didUpdateWidget(covariant RunMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_publish);
      widget.controller.addListener(_publish);
    }
    _publish();
  }

  @override
  void dispose() {
    ++_generation;
    _timeout?.cancel();
    widget.controller.removeListener(_publish);
    _bridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_error == null) _bridge?.build() ?? const SizedBox.expand(),
      if (!_ready && _error == null)
        const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    unawaited(_initialize());
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('지도 다시 불러오기'),
                ),
              ],
            ),
          ),
        ),
      if (widget.position != null)
        Positioned(
          top: 0,
          left: 0,
          child: Semantics(label: '내 현재 위치', child: SizedBox.shrink()),
        ),
    ],
  );
}
