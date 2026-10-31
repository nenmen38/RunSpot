import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 푸시 데이터는 화면 이동 힌트로만 사용하며 실제 조회 권한은 서버에서 확인합니다.
class PushDestination {
  const PushDestination(this.kind, this.targetId, this.recipientId);
  final String kind;
  final String targetId;
  final String recipientId;

  static PushDestination? parse(Map<String, dynamic> data, String? owner) {
    final kind = data['kind'];
    final target = data['target_id'];
    if (owner == null ||
        data['recipient_id'] != owner ||
        !['friend_request', 'group_invite', 'board_comment'].contains(kind) ||
        target is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(target)) {
      return null;
    }
    return PushDestination(kind as String, target, owner);
  }
}

class PushService with WidgetsBindingObserver {
  PushService._();
  static final instance = PushService._();
  final destinations = StreamController<PushDestination>.broadcast();
  final messages = StreamController<PushDestination>.broadcast();
  PushDestination? pending;
  Future<void> _work = Future.value();
  bool _started = false;
  bool _foreground = true;
  Timer? _retry;
  int _failures = 0;
  bool _suspended = false;
  SupabaseClient get _client => Supabase.instance.client;
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);

  void start() {
    if (_started || !supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    FirebaseMessaging.onMessage.listen((message) {
      final destination = PushDestination.parse(
        message.data,
        _client.auth.currentUser?.id,
      );
      if (destination != null) messages.add(destination);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => syncQuietly());
    _client.auth.onAuthStateChange.listen((state) {
      if (state.session == null) {
        _retry?.cancel();
        pending = null;
        _work = _work
            .then((_) => FirebaseMessaging.instance.deleteToken())
            .catchError((_) {});
      } else {
        _suspended = false;
        syncQuietly();
      }
    });
    unawaited(
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((message) {
            if (message != null) _open(message);
          })
          .catchError((_) {}),
    );
    syncQuietly();
  }

  void _open(RemoteMessage message) {
    final destination = PushDestination.parse(
      message.data,
      _client.auth.currentUser?.id,
    );
    if (destination == null) return;
    pending = destination;
    destinations.add(destination);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      syncQuietly();
    } else {
      _retry?.cancel();
    }
  }

  void syncQuietly() {
    _retry?.cancel();
    unawaited(
      sync()
          .then((_) {
            _failures = 0;
          })
          .catchError((_) {
            if (!_foreground ||
                _suspended ||
                _client.auth.currentSession == null) {
              return;
            }
            const delays = [30, 60, 120, 240, 300];
            final delay = delays[_failures.clamp(0, delays.length - 1)];
            _failures++;
            _retry = Timer(Duration(seconds: delay), syncQuietly);
          }),
    );
  }

  /// 권한 요청은 설정 화면에서 사용자가 알림 켜기를 선택했을 때만 실행합니다.
  Future<void> sync({bool requestPermission = false}) {
    final owner = _client.auth.currentUser?.id;
    final session = _client.auth.currentSession;
    if (!supported || owner == null || session == null || _suspended) {
      return Future.value();
    }
    final operation = _work.then((_) async {
      if (_suspended ||
          _client.auth.currentSession?.accessToken != session.accessToken) {
        return;
      }
      final messaging = FirebaseMessaging.instance;
      final settings = requestPermission
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        await _client
            .rpc('unregister_push_device')
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await messaging.getAPNSToken() == null) {
        return;
      }
      final token = await messaging.getToken();
      if (token == null ||
          _suspended ||
          _client.auth.currentSession?.accessToken != session.accessToken) {
        return;
      }
      await _client
          .rpc(
            'register_push_device',
            params: {
              'requested_token': token,
              'requested_platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
    });
    _work = operation.catchError((_) {});
    return operation;
  }

  /// 등록 요청이 끝난 뒤 해제하여 로그아웃과 늦은 토큰 등록의 경합을 막습니다.
  Future<void> detach() async {
    if (!supported) return;
    _suspended = true;
    _retry?.cancel();
    await _work;
    try {
      await _client.rpc('unregister_push_device');
      await FirebaseMessaging.instance.deleteToken();
      pending = null;
    } catch (_) {
      _suspended = false;
      rethrow;
    }
  }
}
