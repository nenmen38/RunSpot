import 'dart:async';

import 'package:runquest/features/home/data/live_runner_service.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/models/live_runner.dart';

LocationFix testFix({
  double latitude = 37.5665,
  double accuracy = 10,
  DateTime? recordedAt,
}) => LocationFix(
  latitude: latitude,
  longitude: 126.978,
  accuracy: accuracy,
  recordedAt: recordedAt ?? DateTime.now(),
);

class FakeLocationService implements LocationService {
  final updates = StreamController<LocationFix>.broadcast();
  LocationFix? fix;
  LocationFailure? failure;
  Completer<LocationFix>? pendingCurrent;
  Object? watchFailure;
  bool emitInitialFix = true;
  Completer<void>? pendingCancellation;
  final watchModes = <bool>[];
  int activeWatches = 0;

  @override
  Future<LocationFix> current({bool requestPermission = false}) async {
    if (failure != null) throw failure!;
    if (pendingCurrent != null) return pendingCurrent!.future;
    return fix ?? testFix();
  }

  @override
  Stream<LocationFix> watch({bool recording = false}) {
    watchModes.add(recording);
    if (watchFailure != null) throw watchFailure!;
    late StreamController<LocationFix> stream;
    StreamSubscription<LocationFix>? subscription;
    var cancelled = false;
    stream = StreamController<LocationFix>(
      onListen: () {
        activeWatches++;
        subscription = updates.stream.listen(
          stream.add,
          onError: stream.addError,
          onDone: stream.close,
        );
        if (emitInitialFix) {
          scheduleMicrotask(() {
            if (!cancelled) stream.add(fix ?? testFix());
          });
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        cancelled = true;
        unawaited(subscription?.cancel());
        final pending = pendingCancellation;
        if (pending == null) {
          activeWatches--;
          return Future<void>.value();
        }
        return pending.future.then<void>((_) {
          activeWatches--;
        });
      },
    );
    return stream.stream;
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {}
}

class FakeRunnerService implements LiveRunnerService {
  final actions = <String>[];
  List<LiveRunner> runners = [];
  Object? publishFailure;
  Completer<void>? pendingPublish;
  Completer<void>? pendingStop;
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
    if (pendingStop != null) await pendingStop!.future;
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
