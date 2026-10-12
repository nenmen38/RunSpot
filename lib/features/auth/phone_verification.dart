import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/phone_verification_service.dart';

class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({
    required this.service,
    this.now = DateTime.now,
    super.key,
  });
  final PhoneVerificationService service;
  final DateTime Function() now;

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen>
    with WidgetsBindingObserver {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  PhoneVerificationState? _state;
  String? _sentPhone;
  String? _message;
  bool _busy = false;
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
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _accept(PhoneVerificationState state) {
    if (!mounted) return;
    _phone.text = state.pendingPhone ?? state.phone ?? _phone.text;
    setState(() {
      _state = state;
      _sentPhone = state.pendingPhone;
      if (state.verified) {
        _sentPhone = null;
        _code.clear();
        _message = null;
      }
    });
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = null;
      _message = null;
    });
    try {
      _accept(await widget.service.load());
    } catch (_) {
      if (mounted) setState(() => _message = '전화번호 인증 상태를 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _error(Object error) {
    if (error is AuthException) {
      return switch (error.code) {
        'over_sms_send_rate_limit' ||
        'over_request_rate_limit' => '요청이 많습니다. 잠시 후 다시 시도해 주세요.',
        'otp_expired' => '인증번호가 올바르지 않거나 만료되었습니다.',
        'phone_exists' => '이 번호를 사용할 수 없습니다. 기존 계정을 확인해 주세요.',
        'sms_send_failed' ||
        'phone_provider_disabled' => '문자 발송이 연결되어 있지 않습니다.',
        _ => '전화번호 인증을 처리하지 못했습니다.',
      };
    }
    return '전화번호 인증을 처리하지 못했습니다.';
  }

  Future<void> _send() async {
    if (_busy || _remaining > 0 || _state == null || _state!.verified) return;
    final phone = normalizePhone(_phone.text);
    if (phone == null) {
      setState(() => _message = '올바른 휴대폰 번호를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.send(phone);
      if (!mounted) return;
      setState(() {
        _sentPhone = phone;
        _code.clear();
        _nextSend = widget.now().add(const Duration(seconds: 60));
        _message = '인증번호를 보냈습니다.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _remaining == 0) timer.cancel();
        if (mounted) setState(() {});
      });
      _accept(await widget.service.load());
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _state == null || _state!.verified || _sentPhone == null) {
      return;
    }
    if (!RegExp(r'^\d{6,10}$').hasMatch(_code.text)) {
      setState(() => _message = '문자로 받은 인증번호를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.verify(_sentPhone!, _code.text);
      final state = await widget.service.load();
      _accept(state);
      if (mounted && !state.verified) {
        setState(() => _message = '전화번호 인증이 아직 완료되지 않았습니다.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('전화번호 인증')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_state?.verified == true) const Text('전화번호 인증 완료'),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled:
                  !_busy &&
                  _state != null &&
                  _state?.verified != true &&
                  _sentPhone == null,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: '휴대폰 번호',
                hintText: '01012345678',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_state?.verified != true)
              OutlinedButton(
                onPressed: _busy || _state == null || _remaining > 0
                    ? null
                    : _send,
                child: Text(
                  _remaining > 0
                      ? '재전송 ($_remaining초)'
                      : _sentPhone == null
                      ? '인증번호 받기'
                      : '인증번호 재전송',
                ),
              ),
            if (_sentPhone != null && _state?.verified != true) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _sentPhone = null;
                        _code.clear();
                        _message = null;
                      }),
                child: const Text('번호 수정'),
              ),
              TextField(
                controller: _code,
                enabled: !_busy && _state != null,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: '인증번호',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              FilledButton(
                onPressed: _busy || _state == null ? null : _verify,
                child: const Text('인증번호 확인'),
              ),
            ],
            TextButton.icon(
              onPressed: _busy ? null : _check,
              icon: const Icon(Icons.refresh),
              label: const Text('인증 상태 확인'),
            ),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    ),
  );
}
