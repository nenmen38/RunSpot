import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/features/auth/auth_screen.dart';
import 'package:runquest/features/auth/registration.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/footprint_loader.dart';
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
  String? _restoredUserId;
  // 복원된 카카오 세션은 이메일 확인과 가입 확인 사이에도 같은 발걸음을 이어갑니다.
  final _footprintKey = GlobalKey<FootprintLoaderState>();
  Future<void> _finishStride() async {
    await _footprintKey.currentState?.firstStride;
  }

  bool _showedStartupBeforeEmailForm = false;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _signedIn = auth.currentSession != null;
    _restoredUserId = auth.currentSession?.user.id;
    _authSubscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) {
        return;
      }
      final signedIn = state.session != null;
      if (state.session?.user.id != _restoredUserId || !signedIn) {
        _restoredUserId = null;
        _showedStartupBeforeEmailForm = false;
      }
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
    final loading = Scaffold(
      backgroundColor: AppColors.blue,
      body: SafeArea(child: FootprintLoader(key: _footprintKey)),
    );
    return _signedIn
        ? KakaoEmailGate(
            key: ValueKey(Supabase.instance.client.auth.currentUser?.id),
            initialLoading: _restoredUserId != null ? loading : null,
            onInitialFormShown: _restoredUserId == null
                ? null
                : () async {
                    await _finishStride();
                    if (mounted && _restoredUserId != null) {
                      setState(() => _showedStartupBeforeEmailForm = true);
                    }
                  },
            child: RegistrationGate(
              finishLoading: _finishStride,
              loading: _showedStartupBeforeEmailForm
                  ? const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    )
                  : loading,
              child: widget.child,
            ),
          )
        : const AuthScreen();
  }
}
