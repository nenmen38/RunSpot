import 'package:flutter/foundation.dart';

import 'appearance/app_appearance.dart';

/// 러닝 중 10초 이상 멈추면 자동으로 일시정지할지 정합니다. 기본은 켜짐이며 기기에 저장합니다.
class RunAutoPauseSettings extends ChangeNotifier {
  RunAutoPauseSettings({AppearanceStore? store}) : _given = store;

  static final instance = RunAutoPauseSettings();
  static const _key = 'run.auto_pause';

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  bool enabled = true;

  Future<void> load() async {
    try {
      enabled = await _store.read(_key) != 'off';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    try {
      await _store.write(_key, value ? 'on' : 'off');
    } catch (_) {}
  }
}
