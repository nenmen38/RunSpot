import 'dart:async';

import 'package:runquest/features/home/data/live_runner_service.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/models/live_runner.dart';

LocationFix testFix({double latitude = 37.5665, double accuracy = 10}) =>
    LocationFix(
      latitude: latitude,
      longitude: 126.978,
      accuracy: accuracy,
      recordedAt: DateTime.now(),
    );

class FakeLocationService implements LocationService {
  final updates = StreamController<LocationFix>.broadcast();
  LocationFix? fix;
  LocationFailure? failure;

  @override
  Future<LocationFix> current({bool requestPermission = false}) async {
    if (failure != null) throw failure!;
    return fix ?? testFix();
  }

  @override
  Stream<LocationFix> watch() => updates.stream;

  @override
  Future<void> openSettings(LocationProblem problem) async {}
}

class FakeRunnerService implements LiveRunnerService {
  final actions = <String>[];
  List<LiveRunner> runners = [];
  Object? publishFailure;
  Completer<void>? pendingPublish;
  void Function()? onChanged;
  void Function(bool)? onConnection;
  int? lastRadius;

  @override
  Future<void> publish(LocationFix fix) async {
    actions.add('publish');
    if (pendingPublish != null) await pendingPublish!.future;
    if (publishFailure != null) throw publishFailure!;
  }

  @override
  Future<void> stopSharing() async {
    actions.add('stop');
  }

  @override
  Future<List<LiveRunner>> nearby(int radiusMeters) async {
    lastRadius = radiusMeters;
    return runners;
  }

  @override
  Future<void> connect(
    void Function() changed,
    void Function(bool) connection,
  ) async {
    onChanged = changed;
    onConnection = connection;
    connection(true);
  }

  @override
  Future<void> disconnect() async {
    onChanged = null;
    onConnection = null;
  }
}
