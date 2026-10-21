import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/maps/run_map.dart';
import '../progress/data/progress_service.dart';
import '../progress/widgets/run_reward_section.dart';
import '../run_history/data/run_record_service.dart';
import '../run_history/models/run_record.dart';
import '../run_history/run_history_screen.dart';
import '../run_history/widgets/run_record_details.dart';
import '../run_conditions/conditions_controller.dart';
import '../run_conditions/widgets/conditions_panel.dart';
import '../run_share/run_share_screen.dart';
import '../social/data/block_service.dart';
import '../social/widgets/block_button.dart';
import 'data/location_service.dart';
import 'live_map_controller.dart';
import 'widgets/run_controls.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    this.mapBridgeFactory,
    this.conditionsController,
    this.progressService,
    this.blockService,
    this.isActive = true,
    super.key,
  });
  final LiveMapController controller;
  final MapBridgeFactory? mapBridgeFactory;
  final ConditionsController? conditionsController;
  final ProgressService? progressService;
  final BlockService? blockService;
  final bool isActive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _overviewZoom = 15.5;
  static const _runningZoom = 16.5;
  final _map = RunMapController();
  bool _mapReady = false;
  bool _following = true;
  bool _endingRun = false;
  String? _selectedId;
  bool _foreground = true;
  late bool _hasRun;
  double? _pendingZoom;
  bool _animateZoom = false;

  double get _recommendedZoom =>
      widget.controller.runSession == null ? _overviewZoom : _runningZoom;

  @override
  void initState() {
    super.initState();
    _hasRun = widget.controller.runSession != null;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    widget.conditionsController?.setActive(widget.isActive);
    widget.conditionsController?.setLocation(widget.controller.position);
    unawaited(widget.controller.runHistory.setActive(true));
    unawaited(widget.controller.start());
  }

  void _changed() {
    if (!mounted) return;
    final hasRun = widget.controller.runSession != null;
    if (hasRun != _hasRun) {
      _hasRun = hasRun;
      _following = true;
      _pendingZoom = _recommendedZoom;
      _animateZoom = hasRun;
    }
    final position = widget.controller.position;
    widget.conditionsController?.setLocation(position);
    if (_following && _mapReady && position != null) {
      _map.move(
        LatLng(position.latitude, position.longitude),
        _pendingZoom ?? _map.camera.zoom,
        animate: _animateZoom,
      );
      _pendingZoom = null;
      _animateZoom = false;
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
      final summary = await widget.controller.finishRun(
        temperatureAtEnd: (endedAt) => widget.conditionsController
            ?.temperatureAt(widget.controller.position, endedAt),
      );
      if (!mounted || summary == null) return;
      final history = widget.controller.runHistory;
      RunRecord currentRecord() =>
          history.visibleRecords
              .where((record) => record.clientRunId == summary.clientRunId)
              .firstOrNull ??
          RunRecord.pending(summary);
      final record = currentRecord();
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(record.pendingSync ? '기기에 저장됨' : '러닝 완료'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RunRecordDetails(record: record),
                if (widget.progressService case final progress?)
                  RunRewardSection(
                    service: progress,
                    runId: record.id,
                    pendingSync: record.pendingSync,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'share'),
              icon: const Icon(Icons.ios_share),
              label: const Text('공유'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'history'),
              child: const Text('내 기록'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted || !history.service.isCurrentOwner) return;
      if (action == 'history') {
        _openHistory();
      } else if (action == 'share') {
        final service = history.service;
        final client = service is SupabaseRunRecordService
            ? service.client
            : null;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RunShareScreen(
              record: currentRecord(),
              isCurrentOwner: () => service.isCurrentOwner,
              loadRoute: () async => summary.route,
              ownerChanges: client?.auth.onAuthStateChange,
            ),
          ),
        );
      }
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
    if (state != AppLifecycleState.inactive) {
      _foreground = state == AppLifecycleState.resumed;
    }
    widget.conditionsController?.setActive(_foreground && widget.isActive);
    // 권한 대화상자의 일시적인 inactive 상태에서는 공유를 중단하지 않습니다.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.runHistory.setActive(true));
      unawaited(widget.controller.setActive(true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (state == AppLifecycleState.detached) widget.controller.pauseRun();
      unawaited(widget.controller.runHistory.setActive(false));
      unawaited(widget.controller.setActive(false));
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conditionsController != widget.conditionsController) {
      oldWidget.conditionsController?.setActive(false);
      widget.conditionsController?.setLocation(widget.controller.position);
    }
    widget.conditionsController?.setActive(_foreground && widget.isActive);
  }

  @override
  void dispose() {
    widget.conditionsController?.setActive(false);
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
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
              RunMap(
                controller: _map,
                bridgeFactory: widget.mapBridgeFactory,
                position: position == null
                    ? null
                    : LatLng(position.latitude, position.longitude),
                segments:
                    state.runSession?.routeSegments
                        .map(
                          (s) => s
                              .map((p) => LatLng(p.latitude, p.longitude))
                              .toList(),
                        )
                        .toList() ??
                    const [],
                markers: state.runners
                    .map(
                      (r) => RunMapMarker(
                        id: r.id,
                        point: LatLng(r.latitude, r.longitude),
                        nickname: r.nickname,
                        selected: r.id == _selectedId,
                      ),
                    )
                    .toList(),
                onReady: () {
                  _mapReady = true;
                  _pendingZoom = _recommendedZoom;
                  _changed();
                },
                onGesture: () {
                  if (_following) setState(() => _following = false);
                },
                onTap: () => setState(() => _selectedId = null),
                onMarkerTap: (id) => setState(() => _selectedId = id),
              ),
              if (state.locating || state.locationFailure != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
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
                                  : state.locationFailure!.message,
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
                    setState(() {
                      _following = true;
                      _pendingZoom = _recommendedZoom;
                    });
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.blockService case final service?)
                            BlockButton(
                              service: service,
                              userId: selected.id,
                              nickname: selected.nickname,
                              onChanged: () {
                                setState(() => _selectedId = null);
                                state.hideBlockedRunner(selected.id);
                                unawaited(state.refresh());
                              },
                            ),
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _selectedId = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.conditionsController != null)
          ConditionsPanel(controller: widget.conditionsController!),
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
                                ? '주변 러너 ${state.runners.length}명'
                                : state.shareWhileRunning
                                ? '러닝 중에만 공유합니다.'
                                : '프로필에서 러닝 시 위치 공유를 설정하세요.',
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
                  ],
                ),
                if (state.sharing && !state.connected) const Text('실시간 연결 중'),
                if (state.sharingError != null)
                  Text(
                    state.sharingError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                if (state.sharing &&
                    state.connected &&
                    state.runners.isEmpty &&
                    state.sharingError == null)
                  const Text('주변에 위치를 공유 중인 러너가 없습니다.'),
                if (state.recoveredRun)
                  const Text(
                    '이전 러닝을 일시 정지 상태로 복구했습니다. 앱이 종료된 동안의 거리와 시간은 포함하지 않습니다.',
                  ),
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
