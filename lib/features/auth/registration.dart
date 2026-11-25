import 'package:flutter/material.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/legal_links.dart';
import 'community_policy.dart';

class RegistrationGate extends StatefulWidget {
  const RegistrationGate({
    required this.child,
    required this.loading,
    required this.finishLoading,
    super.key,
  });

  final Widget child;
  final Widget loading;
  final Future<void> Function() finishLoading;

  @override
  State<RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends State<RegistrationGate> {
  bool? _complete;
  bool _busy = false;
  bool _needsConsent = false;
  bool _accepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check({bool accept = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final owner = client.auth.currentUser?.id;
      if (owner == null) return;
      var complete = await client.rpc('my_registration_complete') as bool;
      if (!complete) {
        if (!mounted || client.auth.currentUser?.id != owner) return;
        await client.rpc('complete_registration');
        complete = await client.rpc('my_registration_complete') == true;
      }
      if (!complete) {
        if (mounted) setState(() => _error = '가입 상태를 완료하지 못했습니다.');
        return;
      }
      final session = client.auth.currentSession;
      if (!mounted || session?.user.id != owner) return;
      if (accept) {
        await client
            .rpc(
              'accept_community_policy',
              params: {'shown_version': CommunityPolicy.version},
            )
            .setHeader('Authorization', 'Bearer ${session!.accessToken}');
      }
      final policyAccepted =
          await client.rpc('my_community_policy_accepted') == true;
      if (mounted) await widget.finishLoading();
      if (mounted && client.auth.currentUser?.id == owner) {
        setState(() {
          _complete = policyAccepted;
          _needsConsent = !policyAccepted;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == '22023' && accept
              ? '최신 앱에서 운영정책을 확인해 주세요.'
              : accept
              ? '운영정책 동의를 저장하지 못했습니다. 다시 시도해 주세요.'
              : '가입 상태를 완료하지 못했습니다.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '가입 상태를 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      if (await launchUrl(Uri.parse(LegalLinks.privacyPolicy))) return;
    } catch (_) {
      // 주소를 열 수 없으면 가입 화면에 안내합니다.
    }
    if (mounted) setState(() => _error = '개인정보처리방침을 열지 못했습니다.');
  }

  Future<void> _signOut() async {
    setState(() => _error = null);
    try {
      await PushService.instance.detach();
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) setState(() => _error = '로그아웃하지 못했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_complete == true) return widget.child;
    if (_busy && !_needsConsent) {
      return widget.loading;
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _needsConsent ? CommunityPolicy.title : '가입 처리 중',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                if (_needsConsent) ...[
                  CommunityPolicyAgreement(
                    accepted: _accepted,
                    onChanged: (value) {
                      if (!_busy) setState(() => _accepted = value);
                    },
                  ),
                  if (LegalLinks.privacyPolicy.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : _openPrivacyPolicy,
                      child: const Text('개인정보처리방침 보기'),
                    ),
                  FilledButton(
                    onPressed: _busy || !_accepted
                        ? null
                        : () => _check(accept: true),
                    child: const Text('동의하고 계속'),
                  ),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!_needsConsent)
                    FilledButton(
                      onPressed: _busy ? null : _check,
                      child: const Text('다시 시도'),
                    ),
                ],
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('로그아웃'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
