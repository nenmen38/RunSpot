import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationGate extends StatefulWidget {
  const RegistrationGate({required this.child, super.key});

  final Widget child;

  @override
  State<RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends State<RegistrationGate> {
  bool? _complete;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var complete = await Supabase.instance.client.rpc(
        'my_registration_complete',
      ) as bool;
      if (!complete) {
        await Supabase.instance.client.rpc('complete_registration');
        complete =
            await Supabase.instance.client.rpc('my_registration_complete') ==
            true;
      }
      if (mounted) {
        setState(() {
          _complete = complete;
          if (!complete) {
            _error = '가입 상태를 완료하지 못했습니다.';
          }
        });
      }
    } on PostgrestException {
      if (mounted) setState(() => _error = '가입 상태를 완료하지 못했습니다.');
    } catch (_) {
      if (mounted) setState(() => _error = '가입 상태를 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('가입 처리 중', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 10),
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
