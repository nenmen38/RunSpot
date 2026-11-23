import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import '../../../shared/maps/run_map.dart';
import '../../../shared/formatters/run_format.dart';
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
  ({Duration fastest, Duration slowest})? _range;

  void _updateRoute() {
    // 원본 거리로 페이스 색 경계를 정한 뒤 각 조각의 표시 좌표만 정리합니다.
    _pieces = [
      for (final piece in paceColoredRoute(widget.route, widget.splits))
        PaceRoutePiece(cleanDisplayRoute(piece.points), piece.color),
    ];
    _range = _pieces.any((piece) => piece.color != paceDefault)
        ? paceRange(widget.splits?.map((split) => split.pace) ?? const [])
        : null;
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
    final range = _range;
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
            ],
          ),
        ),
        if (range != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _PaceLegend(fastest: range.fastest, slowest: range.slowest),
          ),
      ],
    );
  }
}

class _PaceLegend extends StatelessWidget {
  const _PaceLegend({required this.fastest, required this.slowest});

  final Duration fastest;
  final Duration slowest;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('이번 러닝의 구간 페이스', style: text.labelMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatPaceDuration(fastest)} /km',
                style: text.labelSmall,
              ),
              Text(
                '${formatPaceDuration(slowest)} /km',
                style: text.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final band in paceBands)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: band.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            band.label,
                            style: text.labelSmall,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
