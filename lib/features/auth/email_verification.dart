import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/email_verification_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    required this.service,
    required this.onVerified,
    this.now = DateTime.now,
    super.key,
  });

  final EmailVerificationService service;
  final Future<void> Function() onVerified;
  final DateTime Function() now;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  final _email = TextEditingController();
  EmailVerificationState? _state;
  bool _busy = false;
  bool _completed = false;
  String? _message;
  DateTime? _nextSend;
  Timer? _timer;

  int get _remaining {
    final milliseconds =
        _nextSend?.difference(widget.now()).inMilliseconds ?? 0;
    return milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _accept(EmailVerificationState state) async {
    if (!mounted) return;
    _email.text = state.confirmationEmail ?? _email.text;
    setState(() => _state = state);
    if (state.verified && !_completed) {
      _completed = true;
      await widget.onVerified();
    }
  }

  Future<void> _check({bool manual = false}) async {
    if (_busy || _completed) return;
    setState(() {
      _busy = true;
      _message = null;
      _state = null;
    });
    try {
      final state = await widget.service.load();
      await _accept(state);
      if (mounted && manual && !state.verified) {
        setState(() => _message = '이메일 인증이 아직 완료되지 않았습니다.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '이메일 인증 상태를 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _remaining > 0 || _state == null || _completed) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _message = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.send(email);
      if (!mounted) return;
      setState(() {
        _nextSend = widget.now().add(const Duration(seconds: 60));
        _message = '인증 메일을 보냈습니다.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _remaining == 0) timer.cancel();
        if (mounted) setState(() {});
      });
      // 메일 전송만으로 인증 완료를 판단하지 않고 서버 상태를 다시 확인합니다.
      await _accept(await widget.service.load());
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.code) {
            'over_email_send_rate_limit' ||
            'over_request_rate_limit' => '메일 요청이 많습니다. 잠시 후 다시 시도해 주세요.',
            'email_exists' => '이 이메일을 사용할 수 없습니다. 기존 계정을 확인해 주세요.',
            'email_address_invalid' => '올바른 이메일 주소를 입력해 주세요.',
            _ => '인증 메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '인증 메일을 보내지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('이메일 인증')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_busy && _state != null && !_completed,
              readOnly: _state?.confirmationEmail != null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: '이메일',
                prefixIcon: Icon(Icons.mail_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy || _remaining > 0 || _state == null || _completed
                  ? null
                  : _send,
              child: Text(
                _remaining > 0
                    ? '재전송 ($_remaining초)'
                    : _state?.confirmationEmail == null
                    ? '인증 메일 보내기'
                    : '인증 메일 재전송',
              ),
            ),
            FilledButton(
              onPressed: _busy || _completed
                  ? null
                  : () => _check(manual: true),
              child: const Text('인증 상태 확인'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
          ],
        ),
      ),
    ),
  );
}
