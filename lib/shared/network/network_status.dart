import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 폰의 인터넷 연결 상태입니다. 와이파이·데이터가 모두 꺼지면 [online]이 false가 됩니다.
/// 연결이 돌아오면 [reconnects]가 1씩 늘어나 화면들이 알아서 다시 불러올 수 있습니다.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();
  static final instance = NetworkStatus._();

  bool _online = true;
  bool get online => _online;

  /// 끊겼다가 다시 연결된 횟수입니다.
  int reconnects = 0;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// 앱이 켜질 때 한 번 부릅니다. 플러그인이 없는 환경(테스트 등)에서는 조용히 넘어갑니다.
  Future<void> start([Connectivity? connectivity]) async {
    if (_subscription != null) return;
    final source = connectivity ?? Connectivity();
    try {
      _subscription = source.onConnectivityChanged.listen(
        _apply,
        onError: (_) {},
      );
      _apply(await source.checkConnectivity());
    } catch (_) {
      // 연결 상태를 알 수 없으면 연결된 것으로 둡니다.
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _apply(List<ConnectivityResult> results) =>
      setOnline(results.any((result) => result != ConnectivityResult.none));

  /// 연결 상태를 바꿉니다(테스트에서도 씁니다).
  @visibleForTesting
  void setOnline(bool online) {
    if (online == _online) return;
    _online = online;
    if (online) reconnects++;
    notifyListeners();
  }
}

/// 인터넷이 안 돼서 생긴 오류인지 봅니다(서버가 거절한 오류와 구분).
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HttpException ||
    error is AuthRetryableFetchException ||
    // http 패키지의 연결 실패(ClientException)는 이름으로 구분합니다.
    error.runtimeType.toString() == 'ClientException' ||
    !NetworkStatus.instance.online;

/// 연결이 끊겼을 때 모든 화면이 같은 문구를 씁니다.
const offlineMessage = '인터넷에 연결되어 있지 않아요.\n연결되면 자동으로 다시 불러올게요.';
