import 'dart:async';

import 'package:runquest/features/profile/data/run_sharing_preference_service.dart';

class FakeRunSharingPreferenceService implements RunSharingPreferenceService {
  @override
  bool isCurrentOwner = true;
  bool enabled = false;
  Object? loadFailure;
  Object? saveFailure;
  Completer<bool>? pendingLoad;
  Completer<void>? pendingSave;
  final saves = <bool>[];

  @override
  Future<bool> load() async {
    if (loadFailure != null) throw loadFailure!;
    return pendingLoad == null ? enabled : await pendingLoad!.future;
  }

  @override
  Future<void> save(bool value) async {
    saves.add(value);
    await pendingSave?.future;
    if (saveFailure != null) throw saveFailure!;
    enabled = value;
  }
}
