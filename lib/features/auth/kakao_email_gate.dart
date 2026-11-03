import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/email_verification_service.dart';
import 'email_verification.dart';

class KakaoEmailGate extends StatefulWidget {
  const KakaoEmailGate({required this.child, super.key});
  final Widget child;

  @override
  State<KakaoEmailGate> createState() => _KakaoEmailGateState();
}

class _KakaoEmailGateState extends State<KakaoEmailGate> {
  bool _verified = false;
  String? _error;

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) setState(() => _error = '로그아웃하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final kakao =
        user?.identities?.any((identity) => identity.provider == 'kakao') ??
        false;
    if (!kakao || _verified) return widget.child;
    return Column(
      children: [
        if (_error != null) SafeArea(child: Text(_error!)),
        Expanded(
          child: EmailVerificationScreen(
            service: SupabaseEmailVerification(client),
            onSignOut: _signOut,
            onVerified: () async {
              if (mounted) setState(() => _verified = true);
            },
          ),
        ),
      ],
    );
  }
}
