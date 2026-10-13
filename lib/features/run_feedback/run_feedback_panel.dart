import 'dart:async';

import 'package:flutter/material.dart';

import 'data/run_feedback_service.dart';

class RunFeedbackPanel extends StatefulWidget {
  const RunFeedbackPanel({
    required this.runId,
    required this.service,
    super.key,
  });
  final String runId;
  final RunFeedbackService service;

  @override
  State<RunFeedbackPanel> createState() => _RunFeedbackPanelState();
}

class _RunFeedbackPanelState extends State<RunFeedbackPanel>
    with WidgetsBindingObserver {
  RunFeedbackState? _state;
  String? _error;
  bool _busy = false;
  bool _confirming = false;
  Timer? _timer;
  int _polls = 0;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(RunFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runId != widget.runId ||
        oldWidget.service != widget.service) {
      _state = null;
      _epoch++;
      _busy = false;
      _confirming = false;
      _polls = 0;
      _timer?.cancel();
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _polls = 0;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.month}월 ${date.day}일 ${two(date.hour)}:${two(date.minute)}';
  }

  void _accept(RunFeedbackState state) {
    if (!mounted || !widget.service.isCurrentOwner) return;
    setState(() => _state = state);
    _timer?.cancel();
    // 결과 확인만 재시도하며 새로운 AI 생성 요청은 자동으로 보내지 않습니다.
    if (state.status == FeedbackStatus.processing && _polls++ < 24) {
      _timer = Timer(const Duration(seconds: 5), () => unawaited(_load()));
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    final service = widget.service;
    final runId = widget.runId;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await service.load(runId);
      if (epoch == _epoch &&
          widget.service == service &&
          widget.runId == runId) {
        _accept(state);
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = '피드백 상태를 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    if (_busy || _state?.status != FeedbackStatus.available) return;
    final service = widget.service;
    final runId = widget.runId;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _confirming = true;
    });
    try {
      final consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI 피드백 요청'),
          content: const Text(
            '이 기록의 거리·시간·페이스와 이전 최대 5회 기록의 숫자 요약을 Google Gemini에 전송합니다. 이메일·전화번호·위치 경로는 보내지 않습니다. Google API 요금제에 따라 요약이 서비스 개선에 사용될 수 있습니다.\n\n요청을 시작하면 실패한 경우에도 72시간 동안 새 요청이 제한됩니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('동의하고 요청'),
            ),
          ],
        ),
      );
      if (consent != true ||
          !mounted ||
          widget.service != service ||
          widget.runId != runId ||
          !service.isCurrentOwner) {
        return;
      }
      setState(() {
        _error = null;
        _confirming = false;
      });
      final state = await service.generate(runId);
      if (epoch == _epoch &&
          widget.service == service &&
          widget.runId == runId) {
        _accept(state);
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = '피드백 요청 결과를 확인하지 못했습니다. 상태를 다시 확인해 주세요.');
        _state = null;
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.isCurrentOwner) return const Text('로그인 상태를 확인해 주세요.');
    final state = _state;
    final status = state?.status;
    final description = switch (status) {
      FeedbackStatus.available => '생성 가능',
      FeedbackStatus.ready => state!.message!,
      FeedbackStatus.processing => '피드백 생성 중',
      FeedbackStatus.cooldown => '새 피드백 요청 대기 중',
      FeedbackStatus.generationFailed => '피드백 생성에 실패했습니다.',
      FeedbackStatus.emailRequired => '이메일 인증이 필요합니다.',
      FeedbackStatus.insufficientData => '분석할 거리와 시간이 부족합니다.',
      FeedbackStatus.notConfigured => 'AI 연결이 준비되지 않았습니다.',
      FeedbackStatus.budgetExhausted => '현재 서비스의 AI 요청 한도에 도달했습니다.',
      null => '피드백 상태 확인 중',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '러닝 피드백',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '피드백 상태 확인',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(description),
        if (state?.createdAt != null) ...[
          const SizedBox(height: 8),
          Text('AI 생성 · ${_date(state!.createdAt!)}'),
        ],
        if (state?.nextAvailableAt != null &&
            status != FeedbackStatus.ready) ...[
          const SizedBox(height: 8),
          Text('다음 요청: ${_date(state!.nextAvailableAt!)}'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (_busy && !_confirming) const LinearProgressIndicator(),
        if (status == FeedbackStatus.available)
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('AI 피드백 요청'),
          ),
      ],
    );
  }
}
