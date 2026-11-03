import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:runquest/features/auth/registration.dart';

import 'kakao_email_gate.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;
  late bool _signedIn;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _signedIn = auth.currentSession != null;
    _authSubscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) {
        return;
      }
      final signedIn = state.session != null;
      if (_signedIn && !signedIn) {
        // 로그인 화면 위에 남아 있는 설정·상세 화면을 함께 닫습니다.
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
      setState(() => _signedIn = signedIn);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _signedIn
        ? KakaoEmailGate(
            key: ValueKey(Supabase.instance.client.auth.currentUser?.id),
            child: RegistrationGate(child: widget.child),
          )
        : const AuthScreen();
  }
}
