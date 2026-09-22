import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_verification.dart';

class PrivacyControls extends StatefulWidget {
  const PrivacyControls({super.key});

  @override
  State<PrivacyControls> createState() => _PrivacyControlsState();
}

class _PrivacyControlsState extends State<PrivacyControls> {
  final _client = Supabase.instance.client;
  String _visibility = 'private';
  bool _verified = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verified = await SupabasePhoneVerification(_client).isVerified();
      final profile = await _client
          .from('profiles')
          .select('visibility')
          .eq('id', _client.auth.currentUser!.id)
          .single();
      if (mounted) {
        setState(() {
          _verified = verified;
          _visibility = verified ? profile['visibility'] as String : 'private';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '공개 설정을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String value) async {
    if (_busy || (!_verified && value != 'private')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _client
          .from('profiles')
          .update({'visibility': value})
          .eq('id', _client.auth.currentUser!.id)
          .select('visibility')
          .single();
      if (mounted) setState(() => _visibility = result['visibility'] as String);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '공개 범위를 변경하지 못했습니다. 인증 상태를 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) {
          return PhoneVerificationScreen(
            allowBack: true,
            service: SupabasePhoneVerification(_client),
            onVerified: () async => Navigator.of(routeContext).pop(),
          );
        },
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'private', label: Text('비공개')),
            ButtonSegment(value: 'friends', label: Text('친구 공개')),
            ButtonSegment(value: 'public', label: Text('전체 공개')),
          ],
          selected: {_visibility},
          showSelectedIcon: false,
          onSelectionChanged: _busy || !_verified || _error != null
              ? null
              : (values) => _save(values.single),
        ),
        if (!_verified && !_busy && _error == null)
          TextButton(onPressed: _verify, child: const Text('전화번호 인증')),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('다시 시도'),
          ),
        ],
      ],
    );
  }
}
