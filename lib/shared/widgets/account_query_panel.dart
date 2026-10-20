import 'dart:async';

import 'package:flutter/material.dart';

/// 계정에 고정된 조회를 화면 복귀와 새로고침에 맞춰 갱신합니다.
class AccountQueryPanel<T> extends StatefulWidget {
  const AccountQueryPanel({
    required this.source,
    required this.load,
    required this.isCurrentOwner,
    required this.builder,
    required this.errorMessage,
    this.revision = 0,
    super.key,
  });

  final Object source;
  final Future<T> Function() load;
  final bool Function() isCurrentOwner;
  final Widget Function(BuildContext, T) builder;
  final String errorMessage;
  final int revision;

  @override
  State<AccountQueryPanel<T>> createState() => _AccountQueryPanelState<T>();
}

class _AccountQueryPanelState<T> extends State<AccountQueryPanel<T>>
    with WidgetsBindingObserver {
  T? _value;
  bool _loading = false;
  bool _failed = false;
  bool _active = true;
  int _generation = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _schedule();
    if (_active) unawaited(_load());
  }

  void _schedule() {
    _timer?.cancel();
    if (_active) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_loading) unawaited(_load());
      });
    }
  }

  @override
  void didUpdateWidget(covariant AccountQueryPanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.revision != widget.revision) {
      // 계정·친구 관계가 바뀌면 진행 중인 이전 조회도 폐기합니다.
      ++_generation;
      _loading = false;
      _value = null;
      if (_active) unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _schedule();
    if (_active) {
      unawaited(_load());
    } else {
      ++_generation;
      setState(() {
        _loading = false;
        _value = null;
      });
    }
  }

  Future<void> _load() async {
    if (_loading || !_active) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      // 접근 권한이 회수된 경우 이전 집계가 남지 않도록 조회 전에 지웁니다.
      _value = null;
    });
    try {
      if (!widget.isCurrentOwner()) throw StateError('계정이 변경되었습니다.');
      final value = await widget.load().timeout(const Duration(seconds: 15));
      if (mounted && generation == _generation) {
        setState(() {
          if (widget.isCurrentOwner()) {
            _value = value;
          } else {
            _failed = true;
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed || !widget.isCurrentOwner())
          Text(widget.errorMessage)
        else if (value != null)
          widget.builder(context, value),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_failed ? '다시 시도' : '새로고침'),
          ),
        ),
      ],
    );
  }
}
