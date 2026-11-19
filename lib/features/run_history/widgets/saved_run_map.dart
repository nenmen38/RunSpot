import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../../../shared/maps/run_map.dart';
import '../models/display_route.dart';
import '../models/pace_route.dart';
import '../models/run_route.dart';
import '../models/run_split.dart';

class SavedRunMap extends StatefulWidget {
  const SavedRunMap({
    required this.route,
    this.splits,
    this.mapBridgeFactory,
    super.key,
  });
  final RunRoute route;

  /// 1km 구간 기록이 있으면 구간 페이스에 따라 경로 색을 칠합니다.
  final List<RunSplit>? splits;
  final MapBridgeFactory? mapBridgeFactory;
  @override
  State<SavedRunMap> createState() => _SavedRunMapState();
}

class _SavedRunMapState extends State<SavedRunMap> {
  final _map = RunMapController();
  late List<PaceRoutePiece> _pieces;

  void _updateRoute() {
    // 원본 거리로 페이스 색 경계를 정한 뒤 각 조각의 표시 좌표만 정리합니다.
    _pieces = [
      for (final piece in paceColoredRoute(widget.route, widget.splits))
        PaceRoutePiece(cleanDisplayRoute(piece.points), piece.color),
    ];
    _fit();
  }

  void _fit() => _map.fit(_pieces.expand((piece) => piece.points));

  @override
  void initState() {
    super.initState();
    _updateRoute();
  }

  @override
  void didUpdateWidget(covariant SavedRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route || oldWidget.splits != widget.splits) {
      _updateRoute();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pieces = _pieces;
    final colored = pieces.map((piece) => piece.color).toSet().length > 1;
    return Column(
      children: [
        SizedBox(
          height: 320,
          child: Stack(
            children: [
              RunMap(
                controller: _map,
                segments: [for (final piece in pieces) piece.points],
                segmentColors: [
                  for (final piece in pieces) paceColorHex(piece.color),
                ],
                endpoints: true,
                bridgeFactory: widget.mapBridgeFactory,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: AppColors.surface,
                  child: IconButton(
                    tooltip: '전체 경로 보기',
                    icon: const Icon(Icons.fit_screen),
                    onPressed: _fit,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.trip_origin, size: 16, color: Color(0xFF16836F)),
              const SizedBox(width: 4),
              const Text('출발'),
              const SizedBox(width: 20),
              const Icon(Icons.flag, size: 16, color: Color(0xFFC13647)),
              const SizedBox(width: 4),
              const Text('도착'),
              if (colored) ...[
                const Spacer(),
                // 경로 색이 무엇을 뜻하는지 보여줍니다.
                const Text('빠름', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Container(
                  width: 56,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [paceFast, paceMiddle, paceSlow],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('느림', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
