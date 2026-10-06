import 'package:geolocator/geolocator.dart';

import '../models/live_runner.dart';

enum LocationProblem { disabled, denied, deniedForever, unavailable }

class LocationFailure implements Exception {
  const LocationFailure(this.problem);
  final LocationProblem problem;

  String get message => switch (problem) {
    LocationProblem.disabled => '기기의 위치 서비스를 켜 주세요.',
    LocationProblem.denied => '현재 위치를 보려면 위치 권한이 필요합니다.',
    LocationProblem.deniedForever => '앱 설정에서 위치 권한을 허용해 주세요.',
    LocationProblem.unavailable => '현재 위치를 찾지 못했습니다. 다시 시도해 주세요.',
  };
}

abstract interface class LocationService {
  Future<LocationFix> current({bool requestPermission = false});
  Stream<LocationFix> watch();
  Future<void> openSettings(LocationProblem problem);
}

class DeviceLocationService implements LocationService {
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
    timeLimit: Duration(seconds: 20),
  );

  @override
  Future<LocationFix> current({bool requestPermission = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationProblem.disabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(LocationProblem.deniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(LocationProblem.denied);
    }
    try {
      return _fix(
        await Geolocator.getCurrentPosition(locationSettings: _settings),
      );
    } catch (_) {
      throw const LocationFailure(LocationProblem.unavailable);
    }
  }

  @override
  Stream<LocationFix> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map(_fix);

  static LocationFix _fix(Position position) => LocationFix(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    recordedAt: position.timestamp,
  );

  @override
  Future<void> openSettings(LocationProblem problem) async {
    if (problem == LocationProblem.disabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
