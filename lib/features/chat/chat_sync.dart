import 'dart:async';

import 'package:flutter/widgets.dart';

import 'friend_chat.dart';

/// 친구 대화의 안 읽은 메시지 총 개수와 실시간 변경 신호를 앱 전체에 나눠 줍니다.
/// 서버가 메시지·읽음이 바뀔 때 신호를 보내면 [revision]을 올리고 개수를 다시 셉니다.
/// 실시간 연결이 끊겨도 [pollInterval]마다 다시 확인합니다.
class ChatSync extends ChangeNotifier with WidgetsBindingObserver {
  ChatSync(this.service, {this.pollInterval = const Duration(seconds: 30)});

  final FriendChatService service;
  final Duration pollInterval;

  /// 안 읽은 메시지 총 개수입니다.
  int unreadTotal = 0;

  /// 실시간 신호를 받을 때마다 올라갑니다. 대화 화면은 이 값이 바뀌면 다시 불러옵니다.
  int revision = 0;

  /// 실시간 연결이 살아 있는지 여부입니다. 끊겨 있으면 대화방이 더 자주 확인합니다.
  bool connected = false;

  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  Timer? _poll;
  void Function()? _unsubscribe;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _connect();
    unawaited(refresh());
    _poll = Timer.periodic(pollInterval, (_) {
      if (_foreground) unawaited(refresh());
    });
  }

  void _connect() {
    _unsubscribe?.call();
    try {
      _unsubscribe = service.listen(
        onChanged: () {
          if (_disposed) return;
          revision++;
          notifyListeners();
          unawaited(refresh());
        },
        onConnection: (value) {
          if (_disposed || connected == value) return;
          connected = value;
          notifyListeners();
        },
      );
    } catch (_) {
      _unsubscribe = null;
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final total = await service.unreadTotal();
      if (_disposed || total == unreadTotal) return;
      unreadTotal = total;
      notifyListeners();
    } catch (_) {
      // 개수를 못 세도 대화는 계속 쓸 수 있습니다.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // 백그라운드에 있던 동안 끊겼을 수 있으니 다시 연결하고 새로 셉니다.
      _connect();
      revision++;
      notifyListeners();
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _unsubscribe?.call();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
