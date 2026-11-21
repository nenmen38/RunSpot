import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../shared/formatters/run_format.dart';
import '../models/run_session.dart';

/// 러닝 중 바깥으로 알려 주는 곳입니다. 앱에서는 알림창·음성을, 테스트에서는 기록용 가짜를 씁니다.
abstract interface class RunGuideOutput {
  /// 러닝 측정 알림의 내용을 바꿉니다. (Android의 화면 꺼짐 중 측정 알림)
  Future<void> showProgress(String text);

  /// 음성으로 읽어 줍니다.
  Future<void> speak(String text);
}

class DeviceRunGuideOutput implements RunGuideOutput {
  static const _channel = MethodChannel('runspot/run_notification');
  FlutterTts? _tts;

  @override
  Future<void> showProgress(String text) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': '러닝 측정 중',
        'text': text,
      });
    } catch (_) {
      // 알림을 바꾸지 못해도 측정은 계속합니다.
    }
  }

  Future<FlutterTts> _engine() async {
    if (_tts case final tts?) return tts;
    final tts = FlutterTts();
    await tts.setLanguage('ko-KR');
    await tts.setSpeechRate(.5);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // 음악을 듣는 중이면 소리를 잠깐 줄이고 안내한 뒤 다시 키웁니다.
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions
            .interruptSpokenAudioAndMixWithOthers,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
    return _tts = tts;
  }

  @override
  Future<void> speak(String text) async {
    try {
      final tts = await _engine();
      // Android에서는 안내하는 동안 다른 앱 소리를 잠깐 줄입니다.
      await tts.speak(text, focus: true);
    } catch (_) {
      // 음성 엔진이 없는 기기에서도 측정은 계속합니다.
    }
  }
}

/// 러닝 중 진행 상황을 알림에 보여주고 1km마다 음성으로 안내합니다.
/// 화면이 꺼져 있어도 위치가 들어올 때마다 [update]를 부릅니다.
class RunGuide {
  RunGuide(
    this.output, {
    bool Function()? voiceEnabled,
    DateTime Function()? now,
  }) : _voiceEnabled = voiceEnabled ?? (() => true),
       _now = now ?? DateTime.now;

  final RunGuideOutput output;
  final bool Function() _voiceEnabled;
  final DateTime Function() _now;

  /// 알림 내용을 바꾸는 최소 간격입니다. 너무 자주 바꾸면 배터리를 씁니다.
  static const progressInterval = Duration(seconds: 5);

  String? _runId;
  int _announced = 0;
  DateTime? _lastProgress;
  String? _lastText;

  void update(RunSession session) {
    if (session.isFinished) return;
    // 새 러닝이거나 복구한 러닝이면 이미 지난 구간은 다시 읽지 않습니다.
    if (_runId != session.clientRunId) {
      _runId = session.clientRunId;
      _announced = session.completedSplits.length;
      _lastProgress = null;
      _lastText = null;
    }
    if (!session.isRunning) return;

    final now = _now();
    final text = progressText(session);
    if (text != _lastText &&
        (_lastProgress == null ||
            now.difference(_lastProgress!) >= progressInterval)) {
      _lastProgress = now;
      _lastText = text;
      unawaited(output.showProgress(text));
    }

    final splits = session.completedSplits;
    if (splits.length > _announced) {
      _announced = splits.length;
      if (_voiceEnabled()) {
        unawaited(
          output.speak(
            kilometerAnnouncement(
              kilometers: splits.length,
              splitDuration: splits.last.duration,
              total: session.duration,
              averagePace: session.averagePace,
            ),
          ),
        );
      }
    }
  }

  /// 알림에 보여줄 한 줄입니다. 예: "3.24km · 18:32 · 평균 5’43”/km"
  static String progressText(RunSession session) {
    final km = (session.distanceMeters / 1000).toStringAsFixed(2);
    final pace = session.averagePace;
    return [
      '${km}km',
      formatRunDuration(session.duration),
      if (pace != null) '평균 ${formatPaceDuration(pace)}/km',
    ].join(' · ');
  }

  /// 1km마다 읽어 줄 문장입니다. 예: "3킬로미터. 이번 구간 5분 40초. 총 시간 17분 2초. 평균 페이스 5분 41초."
  static String kilometerAnnouncement({
    required int kilometers,
    required Duration splitDuration,
    required Duration total,
    Duration? averagePace,
  }) => [
    '$kilometers킬로미터.',
    '이번 구간 ${spokenDuration(splitDuration)}.',
    '총 시간 ${spokenDuration(total)}.',
    if (averagePace != null) '평균 페이스 ${spokenDuration(averagePace)}.',
  ].join(' ');

  /// 시간을 읽기 쉬운 말로 바꿉니다. 예: 1시간 2분 5초, 5분 40초, 45초
  static String spokenDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return [
      if (hours > 0) '$hours시간',
      if (minutes > 0) '$minutes분',
      if (seconds > 0 || (hours == 0 && minutes == 0)) '$seconds초',
    ].join(' ');
  }
}
