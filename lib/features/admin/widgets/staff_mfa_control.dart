import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffMfaControl extends StatefulWidget {
  const StaffMfaControl({
    required this.client,
    required this.isCurrentOwner,
    required this.onVerified,
    super.key,
  });
  final SupabaseClient client;
  final bool Function() isCurrentOwner;
  final VoidCallback onVerified;
  @override
  State<StaffMfaControl> createState() => _StaffMfaControlState();
}

class _StaffMfaControlState extends State<StaffMfaControl> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _factorId;
  String? _secret;
  String? _error;

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.isCurrentOwner()) return;
      final factors = await widget.client.auth.mfa.listFactors();
      if (!mounted || !widget.isCurrentOwner()) return;
      if (factors.totp.isNotEmpty) {
        _factorId = factors.totp.first.id;
      } else {
        final enrollment = await widget.client.auth.mfa.enroll(
          friendlyName: '런스팟 관리 인증',
        );
        if (!mounted || !widget.isCurrentOwner()) return;
        _factorId = enrollment.id;
        _secret = enrollment.totp?.secret;
      }
    } catch (_) {
      if (mounted) _error = '인증 준비에 실패했습니다. 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text) || !widget.isCurrentOwner()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final factorId = _factorId!;
      final challenge = await widget.client.auth.mfa.challenge(
        factorId: factorId,
      );
      if (!mounted || !widget.isCurrentOwner()) return;
      await widget.client.auth.mfa.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: _code.text,
      );
      if (!mounted || !widget.isCurrentOwner()) return;
      _secret = null;
      _code.clear();
      _factorId = null;
      widget.onVerified();
    } catch (_) {
      if (mounted) _error = '인증 코드를 확인해 주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _secret = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.isCurrentOwner()
      ? const Text('다시 로그인해 주세요.')
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_factorId == null)
              TextButton(
                onPressed: _busy ? null : _prepare,
                child: const Text('관리자 다중 인증'),
              ),
            if (_secret != null) ...[
              const Text(
                '인증 앱에 아래 키를 등록한 뒤 6자리 코드를 입력하세요. 키를 다른 사람에게 공유하지 마세요.',
              ),
              SelectableText(_secret!),
            ],
            if (_factorId != null) ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '인증 앱의 6자리 코드'),
              ),
              TextButton(
                onPressed: _busy ? null : _verify,
                child: const Text('인증 확인'),
              ),
            ],
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
          ],
        );
}
