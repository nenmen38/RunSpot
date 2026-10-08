import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/live_runner.dart';

class RunRouteLayer extends StatefulWidget {
  const RunRouteLayer({required this.segments, super.key});

  final List<List<LocationFix>> segments;

  @override
  State<RunRouteLayer> createState() => _RunRouteLayerState();
}

class _RunRouteLayerState extends State<RunRouteLayer> {
  List<List<LocationFix>>? _previous;
  List<Polyline> _polylines = [];

  @override
  Widget build(BuildContext context) {
    // 타이머 갱신마다 좌표를 변환하지 않고 경로가 바뀔 때만 선을 만듭니다.
    if (!identical(_previous, widget.segments)) {
      _previous = widget.segments;
      _polylines = [
        for (final segment in widget.segments)
          if (segment.length > 1)
            Polyline(
              points: [
                for (final fix in segment) LatLng(fix.latitude, fix.longitude),
              ],
              color: const Color(0xFF16836F),
              strokeWidth: 5,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
      ];
    }
    return IgnorePointer(child: PolylineLayer(polylines: _polylines));
  }
}
