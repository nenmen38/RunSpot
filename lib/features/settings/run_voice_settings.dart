import 'package:flutter/foundation.dart';

import 'appearance/app_appearance.dart';

/// 러닝 중 1km마다 음성 안내를 할지 정합니다. 기본은 켜짐이며 기기에 저장합니다.
class RunVoiceSettings extends ChangeNotifier {
  RunVoiceSettings({AppearanceStore? store}) : _given = store;

  static final instance = RunVoiceSettings();
  static const _key = 'run.voice_guide';

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
