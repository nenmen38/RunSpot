import 'package:flutter/material.dart';

import '../../../shared/maps/run_map.dart';
import '../models/run_route.dart';

class SavedRunMap extends StatefulWidget {
  const SavedRunMap({required this.route, this.mapBridgeFactory, super.key});
  final RunRoute route;
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
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 320,
        child: Stack(
          children: [
            RunMap(
              controller: _map,
              segments: widget.route.segments,
              endpoints: true,
              bridgeFactory: widget.mapBridgeFactory,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white,
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
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.trip_origin, size: 16, color: Color(0xFF16836F)),
            SizedBox(width: 4),
            Text('출발'),
            SizedBox(width: 20),
            Icon(Icons.flag, size: 16, color: Color(0xFFC13647)),
            SizedBox(width: 4),
            Text('도착'),
          ],
        ),
      ),
    ],
  );
}
