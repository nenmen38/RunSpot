import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../../../shared/maps/run_map.dart';
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
  void _fit() => _map.fit(widget.route.segments.expand((s) => s));
  @override
  void initState() {
    super.initState();
    _fit();
  }

  @override
  void didUpdateWidget(covariant SavedRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) _fit();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pieces = paceColoredRoute(widget.route, widget.splits);
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
