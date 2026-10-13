import 'dart:async';

import 'package:flutter/foundation.dart';

import '../home/models/live_runner.dart';
import '../run_history/models/run_temperature.dart';
import 'data/conditions_service.dart';
import 'models/running_conditions.dart';

class ConditionsController extends ChangeNotifier {
  ConditionsController(this.service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final ConditionsService service;
  final DateTime Function() _clock;
  RunningConditions? data;
  String? error;
  bool loading = false;
  LocationFix? _location;
  String? _area;
  DateTime? _lastAttempt;
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  DateTime get now => _clock();

  static String? _areaFor(LocationFix? location) =>
      location != null && location.isUsable
      ? '${(location.latitude * 100).round()}:${(location.longitude * 100).round()}'
      : null;

  RunTemperature? temperatureAt(LocationFix? location, DateTime endedAt) {
    final area = _areaFor(location);
    final weather = data?.weather;
    if (_disposed ||
        area == null ||
        area != _area ||
        weather?.temperature == null ||
        weather?.observedAt == null ||
        !RunningConditions.isFresh(weather!.observedAt, endedAt) ||
        !weather.temperature!.isFinite ||
        weather.temperature! < -80 ||
        weather.temperature! > 60) {
      return null;
    }
    return RunTemperature(
      celsius: weather.temperature!,
      observedAt: weather.observedAt!,
    );
  }

  void setActive(bool value) {
    if (_disposed || value == _active) return;
    _active = value;
    _timer?.cancel();
    if (value) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
      _tick();
    } else {
      _generation++;
      loading = false;
    }
  }

  void setLocation(LocationFix? location) {
    if (_disposed) return;
    _location = location;
    final area = _areaFor(location);
    if (_area == area) return;
    _area = area;
    _generation++;
    loading = false;
    data = null;
    error = area == null ? '현재 위치를 확인하면 러닝 환경이 표시됩니다.' : null;
    notifyListeners();
    if (_active) unawaited(refresh(manual: false));
  }

  void _tick() {
    setLocation(_location);
    if (_disposed) return;
    // 화면에 남아 있는 관측값도 시간이 지나면 판단 불가 상태로 바뀝니다.
    notifyListeners();
    if (_lastAttempt == null ||
        _clock().difference(_lastAttempt!) >= const Duration(minutes: 5) ||
        data == null) {
      unawaited(refresh(manual: false));
    }
  }

  Future<void> refresh({bool manual = true}) async {
    if (_disposed ||
        !_active ||
        loading ||
        _area == null ||
        _location == null) {
      return;
    }
    if (_lastAttempt != null &&
        _clock().difference(_lastAttempt!) <
            Duration(seconds: manual ? 10 : 60)) {
      return;
    }
    final generation = ++_generation;
    final position = _location!;
    _lastAttempt = _clock();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await service.load(position.latitude, position.longitude);
      if (_disposed || !_active || generation != _generation) return;
      data = result;
    } catch (failure) {
      if (_disposed || !_active || generation != _generation) return;
      data = null;
      error = failure is ConditionsFailure
          ? failure.message
          : const ConditionsFailure('unavailable').message;
    } finally {
      if (!_disposed && _active && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
