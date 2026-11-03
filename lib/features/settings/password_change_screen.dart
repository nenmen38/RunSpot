import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/password_policy.dart';
import 'data/password_service.dart';

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({required this.service, super.key});
  final PasswordService service;
  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _needsCode = false;
  String? _message;
  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text != _confirm.text) {
      setState(() => _message = '새 비밀번호가 일치하지 않습니다.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.change(
        _current.text,
        _password.text,
        nonce: _needsCode ? _code.text.trim() : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('비밀번호를 변경했습니다.')));
      Navigator.pop(context);
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.code == 'reauthentication_needed') {
        try {
          await widget.service.sendConfirmation();
          if (mounted) {
            setState(() {
              _needsCode = true;
              _message = '이메일로 보낸 인증 코드를 입력해 주세요.';
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() => _message = '인증 메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.');
          }
        }
      } else {
        setState(
          () => _message = switch (error.code) {
            'invalid_credentials' ||
            'invalid_password' ||
            'current_password_mismatch' ||
            'current_password_required' => '현재 비밀번호를 확인해 주세요.',
            'weak_password' => PasswordPolicy.description,
            'same_password' => '현재 비밀번호와 다른 비밀번호를 입력해 주세요.',
            'reauthentication_not_valid' ||
            'otp_expired' => '인증 코드가 올바르지 않거나 만료되었습니다.',
            null => error.message,
            _ => '비밀번호를 변경하지 못했습니다. 다시 시도해 주세요.',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '비밀번호를 변경하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('비밀번호 변경')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.service.canChange)
            const Text('구글·카카오 계정의 비밀번호는 해당 서비스에서 변경해 주세요.')
          else ...[
            for (final field in [
              (controller: _current, label: '현재 비밀번호'),
              (controller: _password, label: '새 비밀번호'),
              (controller: _confirm, label: '새 비밀번호 확인'),
            ]) ...[
              TextField(
                controller: field.controller,
                obscureText: true,
                enabled: !_busy,
                autofillHints: [
                  field.controller == _current
                      ? AutofillHints.password
                      : AutofillHints.newPassword,
                ],
                decoration: InputDecoration(
                  labelText: field.label,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(PasswordPolicy.description),
            const SizedBox(height: 16),
            if (_needsCode)
              TextField(
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '이메일 인증 코드'),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '변경 중' : '비밀번호 변경'),
            ),
          ],
        ],
      ),
    ),
  );
}
