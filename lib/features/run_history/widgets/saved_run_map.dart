import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/run_route.dart';

class SavedRunMap extends StatefulWidget {
  const SavedRunMap({required this.route, this.tileProvider, super.key});
  final RunRoute route;
  final TileProvider? tileProvider;

  @override
  State<SavedRunMap> createState() => _SavedRunMapState();
}

class _SavedRunMapState extends State<SavedRunMap> {
  final _map = MapController();
  final _resetTiles = StreamController<void>.broadcast();
  late final _segments = widget.route.segments;
  late final _points = _segments.expand((segment) => segment).toList();
  late final _fit = CameraFit.coordinates(
    coordinates: _points,
    padding: const EdgeInsets.all(40),
    maxZoom: 17,
  );
  late final _polylines = _segments
      .where((segment) => segment.length > 1)
      .map(
        (segment) => Polyline(
          points: segment,
          color: const Color(0xFF16836F),
          strokeWidth: 5,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ),
      )
      .toList();
  bool _tileError = false;

  void _onTileError() {
    if (_tileError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileError) setState(() => _tileError = true);
    });
  }

  @override
  void dispose() {
    _map.dispose();
    unawaited(_resetTiles.close());
    super.dispose();
  }

  Marker _marker(LatLng point, IconData icon, Color color) => Marker(
    point: point,
    width: 36,
    height: 36,
    child: Icon(
      icon,
      color: color,
      size: 32,
      shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _points.first,
                initialZoom: 17,
                initialCameraFit: _fit,
                minZoom: 0,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'com.runspot.runquest',
                  maxNativeZoom: 19,
                  tileProvider: widget.tileProvider,
                  reset: _resetTiles.stream,
                  errorTileCallback: (_, _, _) => _onTileError(),
                ),
                IgnorePointer(child: PolylineLayer(polylines: _polylines)),
                MarkerLayer(
                  markers: [
                    _marker(
                      _points.first,
                      Icons.trip_origin,
                      const Color(0xFF16836F),
                    ),
                    if (_points.last != _points.first)
                      _marker(
                        _points.last,
                        Icons.flag,
                        const Color(0xFFC13647),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      const String.fromEnvironment(
                        'MAP_ATTRIBUTION',
                        defaultValue: 'OpenStreetMap contributors',
                      ),
                      onTap: () => unawaited(
                        launchUrl(
                          Uri.parse(
                            const String.fromEnvironment(
                              'MAP_ATTRIBUTION_URL',
                              defaultValue:
                                  'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white,
                child: IconButton(
                  tooltip: '전체 경로 보기',
                  icon: const Icon(Icons.fit_screen),
                  onPressed: () => _map.fitCamera(_fit),
                ),
              ),
            ),
            if (_tileError)
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.white,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _tileError = false);
                      _resetTiles.add(null);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('지도 다시 불러오기'),
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
