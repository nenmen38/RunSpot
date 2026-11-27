import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'network_status.dart';

/// 인터넷이 끊기면 화면 맨 위에 '오프라인' 띠를 보여 줍니다. 띠가 보이는 동안은
/// 그 아래 화면을 띠만큼 내려서 겹치지 않게 합니다. 다시 연결되면 잠깐 '다시 연결됐어요'를 보여 줍니다.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({required this.child, this.status, super.key});

  final Widget child;
  final NetworkStatus? status;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final NetworkStatus _status = widget.status ?? NetworkStatus.instance;
  late bool _wasOnline;
  bool _showBack = false;
  Timer? _hideBack;

  @override
  void initState() {
    super.initState();
    _wasOnline = _status.online;
    _status.addListener(_changed);
  }

  void _changed() {
    final online = _status.online;
    if (online == _wasOnline) return;
    _wasOnline = online;
    _hideBack?.cancel();
    setState(() => _showBack = online);
    if (online) {
      _hideBack = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showBack = false);
      });
    }
  }

  @override
  void dispose() {
    _hideBack?.cancel();
    _status.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = !_status.online;
    final visible = offline || _showBack;
    final media = MediaQuery.of(context);
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !visible
              ? const SizedBox(width: double.infinity)
              : Material(
                  key: ValueKey(offline ? 'offline-banner' : 'online-banner'),
                  color: offline
                      ? const Color(0xFF4E5968)
                      : const Color(0xFF2BB673),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      media.padding.top + 6,
                      16,
                      7,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          Icon(
                            offline ? Icons.wifi_off_rounded : Icons.wifi,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              offline
                                  ? context.l10n.offlineBanner
                                  : context.l10n.onlineAgain,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          // 띠가 상태 표시줄 자리를 차지했으니 아래 화면의 위쪽 여백을 없앱니다.
          child: visible
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.child,
                )
              : widget.child,
        ),
      ],
    );
  }
}

/// 연결이 다시 되면 [onReconnect]를 부릅니다(오류 화면이 알아서 다시 불러오게).
class ReconnectListener extends StatefulWidget {
  const ReconnectListener({
    required this.child,
    required this.onReconnect,
    super.key,
  });

  final Widget child;
  final VoidCallback? onReconnect;

  @override
  State<ReconnectListener> createState() => _ReconnectListenerState();
}

class _ReconnectListenerState extends State<ReconnectListener> {
  final _status = NetworkStatus.instance;
  late int _seen;

  @override
  void initState() {
    super.initState();
    _seen = _status.reconnects;
    _status.addListener(_changed);
  }

  void _changed() {
    if (_status.reconnects != _seen) {
      _seen = _status.reconnects;
      widget.onReconnect?.call();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _status.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
