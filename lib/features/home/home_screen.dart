import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_colors.dart';
import '../run_history/models/run_record.dart';
import '../run_history/run_history_screen.dart';
import '../run_history/widgets/run_record_details.dart';
import 'data/location_service.dart';
import 'live_map_controller.dart';
import 'widgets/run_controls.dart';

// 지도 타일만 채도를 낮추고 밝게 처리하여 위치 마커의 대비를 유지합니다.
const _lightMapFilter = ColorFilter.matrix([
  0.318899,
  0.527818,
  0.053284,
  0,
  25.5,
  0.156899,
  0.689818,
  0.053284,
  0,
  25.5,
  0.156899,
  0.527818,
  0.215284,
  0,
  25.5,
  0,
  0,
  0,
  1,
  0,
]);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    required this.onProfileTap,
    this.tileProvider,
    super.key,
  });
  final LiveMapController controller;
  final VoidCallback onProfileTap;
  final TileProvider? tileProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _map = MapController();
  final _tileReset = StreamController<void>.broadcast();
  late final TileProvider _tileProvider;
  bool _mapReady = false;
  bool _following = true;
  bool _tileError = false;
  bool _endingRun = false;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _tileProvider = widget.tileProvider ?? NetworkTileProvider();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.start());
  }

  void _changed() {
    if (!mounted) return;
    final position = widget.controller.position;
    if (_following && _mapReady && position != null) {
      _map.move(
        LatLng(position.latitude, position.longitude),
        _map.camera.zoom,
      );
    }
    setState(() {});
  }

  Future<void> _finishRun() async {
    if (_endingRun) return;
    setState(() => _endingRun = true);
    try {
      final confirmed =
          widget.controller.runSession?.isFinished == true ||
          await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('러닝을 종료할까요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('종료'),
                    ),
                  ],
                ),
              ) ==
              true;
      if (confirmed != true || !mounted) return;
      final summary = await widget.controller.finishRun();
      if (!mounted || summary == null) return;
      final record = RunRecord(
        id: summary.clientRunId,
        clientRunId: summary.clientRunId,
        startedAt: summary.startedAt,
        endedAt: summary.endedAt,
        distanceMeters: summary.distanceMeters.round(),
        durationSeconds: summary.duration.inSeconds,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('러닝 완료'),
          content: SingleChildScrollView(
            child: RunRecordDetails(record: record),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openHistory();
              },
              child: const Text('내 기록'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _endingRun = false);
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RunHistoryScreen(controller: widget.controller.runHistory),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 권한 대화상자의 일시적인 inactive 상태에서는 공유를 중단하지 않습니다.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.setActive(true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(widget.controller.setActive(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    unawaited(_tileReset.close());
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller;
    final position = state.position;
    final selected = state.runners
        .where((runner) => runner.id == _selectedId)
        .firstOrNull;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: position == null
                      ? const LatLng(37.5665, 126.9780)
                      : LatLng(position.latitude, position.longitude),
                  initialZoom: 15,
                  minZoom: 3,
                  maxZoom: 19,
                  onMapReady: () {
                    _mapReady = true;
                    _changed();
                  },
                  onPositionChanged: (_, gesture) {
                    if (gesture && _following) {
                      setState(() => _following = false);
                    }
                  },
                  onTap: (_, point) => setState(() => _selectedId = null),
                ),
                children: [
                  TileLayer(
                    reset: _tileReset.stream,
                    urlTemplate: const String.fromEnvironment(
                      'MAP_TILE_URL',
                      defaultValue:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    userAgentPackageName: 'com.runspot.runquest',
                    tileProvider: _tileProvider,
                    maxNativeZoom: 19,
                    tileBuilder: (context, tile, image) => ColorFiltered(
                      colorFilter: _lightMapFilter,
                      child: tile,
                    ),
                    errorTileCallback: (_, error, stack) {
                      if (_tileError) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _tileError = true);
                      });
                    },
                  ),
                  MarkerLayer(
                    markers: [
                      if (position != null)
                        Marker(
                          point: LatLng(position.latitude, position.longitude),
                          width: 48,
                          height: 48,
                          child: Semantics(
                            label: '내 현재 위치',
                            child: Container(
                              margin: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      for (final runner in state.runners)
                        Marker(
                          point: LatLng(runner.latitude, runner.longitude),
                          width: 48,
                          height: 48,
                          child: IconButton.filled(
                            tooltip: runner.nickname,
                            style: IconButton.styleFrom(
                              backgroundColor: runner.id == _selectedId
                                  ? AppColors.ink
                                  : const Color(0xFF16836F),
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _selectedId = runner.id),
                            icon: const Icon(Icons.directions_run),
                          ),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Material(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () => launchUrl(
                          Uri.parse(
                            const String.fromEnvironment(
                              'MAP_ATTRIBUTION_URL',
                              defaultValue:
                                  'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            String.fromEnvironment(
                              'MAP_ATTRIBUTION',
                              defaultValue: '\u00a9 OpenStreetMap contributors',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Material(
                  color: Colors.white,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.directions_run,
                          color: Color(0xFF16836F),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'RunSpot',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        PopupMenuButton<int>(
                          tooltip: '주변 러너 조회 반경',
                          initialValue: state.radiusMeters,
                          onSelected: state.setRadius,
                          itemBuilder: (_) => [
                            for (final radius in [500, 1000, 3000, 5000])
                              CheckedPopupMenuItem(
                                value: radius,
                                checked: state.radiusMeters == radius,
                                child: Text(_distance(radius.toDouble())),
                              ),
                          ],
                          icon: const Icon(Icons.radar),
                        ),
                        IconButton(
                          tooltip: '내 기록',
                          onPressed: _openHistory,
                          icon: const Icon(Icons.history),
                        ),
                        IconButton(
                          tooltip: '프로필 및 공개 설정',
                          onPressed: widget.onProfileTap,
                          icon: const Icon(Icons.person_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (state.locating || state.locationFailure != null || _tileError)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 80,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (state.locating) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              state.locating
                                  ? '현재 위치 확인 중'
                                  : state.locationFailure?.message ??
                                        '지도를 불러오지 못했습니다.',
                            ),
                          ),
                          if (!state.locating)
                            IconButton(
                              tooltip: '다시 시도 또는 기기 설정',
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                final problem = state.locationFailure?.problem;
                                if (problem == LocationProblem.disabled ||
                                    problem == LocationProblem.deniedForever) {
                                  unawaited(
                                    state.locationService.openSettings(
                                      problem!,
                                    ),
                                  );
                                } else {
                                  setState(() {
                                    _tileError = false;
                                  });
                                  _tileReset.add(null);
                                  unawaited(state.start());
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 46,
                child: IconButton.filled(
                  tooltip: '내 위치로 이동',
                  onPressed: () {
                    setState(() => _following = true);
                    _changed();
                    if (position == null) unawaited(state.start());
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _following
                        ? AppColors.blue
                        : AppColors.ink,
                  ),
                  icon: const Icon(Icons.my_location),
                ),
              ),
              if (selected != null)
                Positioned(
                  left: 12,
                  right: 68,
                  bottom: 46,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.directions_run,
                        color: Color(0xFF16836F),
                      ),
                      title: Text(
                        selected.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_distance(selected.distanceMeters)} 거리',
                      ),
                      trailing: IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedId = null),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '위치 공유',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            state.sharing
                                ? '주변 러너 ${state.runners.length}명 · ${_distance(state.radiusMeters.toDouble())}'
                                : '내 위치만 표시 중',
                          ),
                        ],
                      ),
                    ),
                    if (state.changingSharing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    Switch(
                      value: state.sharing,
                      onChanged: state.changingSharing || position == null
                          ? null
                          : state.setSharing,
                    ),
                  ],
                ),
                if (state.sharing && !state.connected) const Text('실시간 연결 중'),
                if (state.sharingError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.sharingError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      IconButton(
                        tooltip: '프로필 및 공개 설정',
                        onPressed: widget.onProfileTap,
                        icon: const Icon(Icons.manage_accounts_outlined),
                      ),
                    ],
                  ),
                if (state.sharing &&
                    state.connected &&
                    state.runners.isEmpty &&
                    state.sharingError == null)
                  const Text('주변에 위치를 공유 중인 러너가 없습니다.'),
                RunControls(
                  controller: state,
                  busy: _endingRun,
                  onFinish: _finishRun,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _distance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} km';
}
