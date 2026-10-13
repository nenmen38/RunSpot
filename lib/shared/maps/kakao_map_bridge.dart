import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'kakao_map_config.dart';

typedef MapBridgeFactory = MapBridge Function();

abstract interface class MapBridge {
  Future<void> initialize(
    void Function(String) onMessage,
    void Function(String) onError,
  );
  Future<void> update(Map<String, Object?> data);
  Widget build();
  void dispose();
}

class KakaoMapBridge implements MapBridge {
  KakaoMapBridge({this.config = const KakaoMapConfig.fromEnvironment()});
  final KakaoMapConfig config;
  WebViewController? _web;
  bool _disposed = false;

  @override
  Future<void> initialize(
    void Function(String) onMessage,
    void Function(String) onError,
  ) async {
    final error = config.validate(release: kReleaseMode);
    if (error != null) {
      onError(error);
      return;
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      onError('카카오 지도는 Android·iOS 앱에서 확인해 주세요.');
      return;
    }
    final web = _web = WebViewController();
    await web.setJavaScriptMode(JavaScriptMode.unrestricted);
    await web.setBackgroundColor(const Color(0xFFF8FAFC));
    await web.addJavaScriptChannel(
      'RunSpotMap',
      onMessageReceived: (message) {
        if (!_disposed) onMessage(message.message);
      },
    );
    await web.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (request.url == 'about:blank' ||
              request.url == config.origin ||
              request.url == '${config.origin}/') {
            return NavigationDecision.navigate;
          }
          if (uri?.scheme == 'https' &&
              const {
                'map.kakao.com',
                'www.kakaocorp.com',
                'apis.map.kakao.com',
              }.contains(uri!.host)) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (!_disposed && error.isForMainFrame == true) {
            onError('지도를 불러오지 못했습니다. 연결을 확인해 주세요.');
          }
        },
      ),
    );
    final html = await rootBundle.loadString('assets/maps/kakao_map.html');
    if (_disposed) return;
    final script = Uri.https('dapi.kakao.com', '/v2/maps/sdk.js', {
      'appkey': config.javaScriptKey,
      'autoload': 'false',
    });
    await web.loadHtmlString(
      html.replaceFirst(
        '__KAKAO_SDK_URL__',
        const HtmlEscape().convert(script.toString()),
      ),
      baseUrl: config.origin,
    );
  }

  @override
  Future<void> update(Map<String, Object?> data) async {
    if (_disposed || _web == null) return;
    // JSON 문자열을 다시 인코딩하여 이름이나 식별자가 실행 코드로 해석되지 않게 합니다.
    await _web!.runJavaScript(
      'window.runspotMap.update(JSON.parse(${jsonEncode(jsonEncode(data))}));',
    );
  }

  @override
  Widget build() => _web == null
      ? const SizedBox.expand()
      : WebViewWidget(
          controller: _web!,
          gestureRecognizers: {
            Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
          },
        );

  @override
  void dispose() {
    _disposed = true;
  }
}
