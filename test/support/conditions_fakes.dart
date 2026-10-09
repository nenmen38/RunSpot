import 'dart:async';

import 'package:runquest/features/run_conditions/data/conditions_service.dart';
import 'package:runquest/features/run_conditions/models/running_conditions.dart';

RunningConditions fixture(
  DateTime now, {
  double? pm10 = 20,
  double? pm25 = 10,
  double temp = 20,
  int precipitation = 0,
  double wind = 2,
  Duration age = Duration.zero,
}) => RunningConditions(
  fetchedAt: now,
  weather: WeatherObservation(
    observedAt: now.subtract(age),
    temperature: temp,
    rain: 0,
    precipitation: precipitation,
    wind: wind,
  ),
  dust: DustObservation(
    observedAt: now.subtract(age),
    station: '종로구',
    distanceKm: 2,
    pm10: pm10,
    pm25: pm25,
  ),
);

class FakeConditionsService implements ConditionsService {
  int calls = 0;
  Completer<RunningConditions>? pending;
  ConditionsFailure? failure;
  @override
  Future<RunningConditions> load(double latitude, double longitude) async {
    calls++;
    if (failure != null) throw failure!;
    return pending != null ? pending!.future : fixture(DateTime.now());
  }
}
