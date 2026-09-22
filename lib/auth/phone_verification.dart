import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String? normalizePhone(String input) {
  final value = input.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^010\d{8}$').hasMatch(value)) {
    return '+82${value.substring(1)}';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value) ? value : null;
}

abstract class PhoneVerificationService {
  Future<bool> isVerified();
  Future<void> send(String phone);
  Future<void> verify(String phone, String code);
  Future<void> signOut();
}

class SupabasePhoneVerification implements PhoneVerificationService {
  SupabasePhoneVerification(this.client);
  final SupabaseClient client;

  @override
  Future<bool> isVerified() async {
    return await client.rpc('my_phone_verified') == true;
  }

  @override
  Future<void> send(String phone) async {
    await client.auth.updateUser(UserAttributes(phone: phone));
  }

  @override
  Future<void> verify(String phone, String code) async {
    final expectedId = client.auth.currentUser?.id;
    if (expectedId == null) throw const AuthException('인증 세션이 만료되었습니다.');
    final result = await client.auth.verifyOTP(
      phone: phone,
      token: code,
      type: OtpType.phoneChange,
    );
    if (result.user?.id != expectedId) {
      await client.auth.signOut();
      throw const AuthException('계정 확인에 실패했습니다. 다시 로그인해 주세요.');
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}

class PhoneVerificationGate extends StatefulWidget {
  const PhoneVerificationGate({
    required this.service,
    required this.child,
    super.key,
  });
  final PhoneVerificationService service;
  final Widget child;

  @override
  State<PhoneVerificationGate> createState() => _PhoneVerificationGateState();
}

class _PhoneVerificationGateState extends State<PhoneVerificationGate>
    with WidgetsBindingObserver {
  bool? _verified;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _verified == true) _check();
  }

  Future<void> _check() async {
    final request = ++_request;
    setState(() {
      _verified = null;
      _failed = false;
    });
    try {
      final verified = await widget.service.isVerified();
      if (mounted && request == _request) setState(() => _verified = verified);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verified == true) return widget.child;
    if (_verified == false) {
      return PhoneVerificationScreen(
        service: widget.service,
        onVerified: _check,
      );
    }
    return Scaffold(
      body: Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('인증 상태를 확인하지 못했습니다.'),
                  TextButton(onPressed: _check, child: const Text('다시 시도')),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({
    required this.service,
    required this.onVerified,
    this.allowBack = false,
    super.key,
  });
  final PhoneVerificationService service;
  final Future<void> Function() onVerified;
  final bool allowBack;

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentPhone;
  String? _message;
  bool _busy = false;
  DateTime? _nextSend;
  Timer? _timer;

  int get _remaining {
    final milliseconds =
        _nextSend?.difference(DateTime.now()).inMilliseconds ?? 0;
    return milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String _error(Object error) {
    if (error is AuthException) {
      switch (error.code) {
        case 'over_sms_send_rate_limit':
        case 'over_request_rate_limit':
          return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
        case 'otp_expired':
          return '인증번호가 올바르지 않거나 만료되었습니다.';
        case 'phone_exists':
          return '이 번호를 사용할 수 없습니다. 기존 계정을 확인해 주세요.';
        case 'sms_send_failed':
        case 'phone_provider_disabled':
          return '문자 발송을 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      }
    }
    return '인증을 처리하지 못했습니다. 다시 시도해 주세요.';
  }

  Future<void> _send() async {
    if (_busy || _remaining > 0) return;
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
        _nextSend = DateTime.now().add(const Duration(seconds: 60));
        _message = '인증번호를 보냈습니다.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _remaining == 0) timer.cancel();
        if (mounted) setState(() {});
      });
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _sentPhone == null) return;
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
      if (!await widget.service.isVerified()) {
        throw const AuthException('전화번호 인증이 완료되지 않았습니다.');
      }
      if (mounted) await widget.onVerified();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.service.signOut();
      if (mounted && widget.allowBack) await Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => _message = '로그아웃에 실패했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('휴대폰 인증'),
        automaticallyImplyLeading: widget.allowBack,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _phone,
                enabled: !_busy && _sentPhone == null,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: '휴대폰 번호',
                  hintText: '01012345678',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy || _remaining > 0 ? null : _send,
                child: Text(
                  _remaining > 0
                      ? '재전송 ($_remaining초)'
                      : _sentPhone == null
                      ? '인증번호 받기'
                      : '인증번호 재전송',
                ),
              ),
              if (_sentPhone != null) ...[
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
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  enabled: !_busy,
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: const Text('인증 완료'),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_message!, semanticsLabel: _message),
                ),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
