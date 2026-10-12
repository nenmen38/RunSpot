import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_redirect.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _message;
  String? _confirmationEmail;
  bool _resendCoolingDown = false;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: authRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '소셜 로그인 처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = '이메일과 비밀번호를 모두 입력해 주세요.');
      return;
    }

    if (password.length < 6) {
      setState(() => _message = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }

    if (_isSignUp) {
      if (password != _passwordConfirmationController.text) {
        setState(() => _message = '비밀번호가 일치하지 않습니다.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _message = null;
      _confirmationEmail = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        final response = await auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: authRedirectUrl,
        );
        if (mounted && response.session == null) {
          setState(() {
            _message = '가입 확인 메일을 확인해 주세요.';
            _confirmationEmail = email;
          });
          _startResendCooldown();
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _message = _authErrorMessage(error));
        if (error.code == 'email_not_confirmed') {
          setState(() => _confirmationEmail = email);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = _fallbackAuthErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCoolingDown = true);
    _resendTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) setState(() => _resendCoolingDown = false);
    });
  }

  Future<void> _resendConfirmation() async {
    final email = _confirmationEmail;
    if (_loading || _resendCoolingDown || email == null) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: authRedirectUrl,
      );
      if (mounted) {
        setState(() => _message = '가입 확인 메일을 확인해 주세요.');
        _startResendCooldown();
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.code) {
            'over_email_send_rate_limit' ||
            'over_request_rate_limit' => '메일 요청이 많습니다. 잠시 후 다시 시도해 주세요.',
            _ => '인증 메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '인증 메일을 보내지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? '회원가입' : '로그인';
    final actionLabel = _isSignUp ? '회원가입' : '이메일로 로그인';
    final switchLabel = _isSignUp ? '이미 계정이 있어요' : '새 계정 만들기';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.directions_run,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'RunSpot',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '러닝 조건을 확인하고 주변 러너와 함께 달려요.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        prefixIcon: Icon(Icons.mail_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: [
                        _isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(
                        labelText: '비밀번호',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _loading ? null : _submit(),
                    ),
                    if (_isSignUp) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordConfirmationController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: '비밀번호 확인',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: _message == '가입 확인 메일을 확인해 주세요.'
                              ? AppColors.green
                              : AppColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(actionLabel),
                    ),
                    if (_confirmationEmail != null)
                      TextButton.icon(
                        onPressed: _loading || _resendCoolingDown
                            ? null
                            : _resendConfirmation,
                        icon: const Icon(Icons.mark_email_unread_outlined),
                        label: Text(
                          _resendCoolingDown ? '인증 메일 재전송 대기 중' : '인증 메일 재전송',
                        ),
                      ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _message = null;
                              _confirmationEmail = null;
                              _passwordConfirmationController.clear();
                            }),
                      child: Text(switchLabel),
                    ),
                    const Divider(height: 24),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _signInWithOAuth(OAuthProvider.google),
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Google로 계속하기'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _signInWithOAuth(OAuthProvider.kakao),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Kakao로 계속하기'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '소셜 로그인은 브라우저 인증 후 앱으로 돌아옵니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _authErrorMessage(AuthException error) {
  if (error.code == 'email_not_confirmed') {
    return '이메일 인증을 완료한 후 로그인해 주세요.';
  }
  if (_isMissingSupabaseHostError(error.message)) {
    return 'Supabase URL 설정이 필요합니다. config/dev.json 값을 확인하거나 실행 옵션을 다시 확인해 주세요.';
  }
  if (error.code == 'unexpected_failure') {
    return '가입하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }
  return error.message;
}

String _fallbackAuthErrorMessage(Object error) {
  if (_isMissingSupabaseHostError(error.toString())) {
    return 'Supabase URL 설정이 필요합니다. config/dev.json 값을 확인하거나 실행 옵션을 다시 확인해 주세요.';
  }
  return '로그인 처리 중 오류가 발생했습니다.';
}

bool _isMissingSupabaseHostError(String message) =>
    message.contains('No host specified');
