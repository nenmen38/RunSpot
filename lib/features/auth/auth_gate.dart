import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:runquest/features/auth/registration.dart';
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
      setState(() => _signedIn = state.session != null);
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
        ? RegistrationGate(
            key: ValueKey(Supabase.instance.client.auth.currentUser?.id),
            child: widget.child,
          )
        : const AuthScreen();
  }
}
