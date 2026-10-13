import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class RunMapCamera {
  const RunMapCamera(this.center, this.zoom);
  final LatLng center;
  final double zoom;
}

class RunMapController extends ChangeNotifier {
  RunMapCamera camera = const RunMapCamera(LatLng(37.5665, 126.978), 15.5);
  int _revision = 0;
  Map<String, Object?> get command => _command;
  Map<String, Object?> _command = {
    'revision': 0,
    'type': 'move',
    'center': [37.5665, 126.978],
    'zoom': 15.5,
  };

  void move(LatLng center, double zoom, {bool animate = false}) {
    if (center == camera.center &&
        zoom == camera.zoom &&
        _command['type'] == 'move') {
      return;
    }
    camera = RunMapCamera(center, zoom);
    _command = {
      'revision': ++_revision,
      'type': 'move',
      'center': [center.latitude, center.longitude],
      'zoom': zoom,
      'animate': animate,
    };
    notifyListeners();
  }

  void fit(Iterable<LatLng> points) {
    final coordinates = points.map((p) => [p.latitude, p.longitude]).toList();
    if (coordinates.isEmpty) return;
    _command = {
      'revision': ++_revision,
      'type': 'fit',
      'points': coordinates,
      'maxZoom': 17,
      'padding': 40,
    };
    notifyListeners();
  }

  void acceptCamera(LatLng center, double zoom) {
    camera = RunMapCamera(center, zoom);
  }
}
