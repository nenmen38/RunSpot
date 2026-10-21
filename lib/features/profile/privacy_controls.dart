import 'package:runquest/features/auth/data/nickname_service.dart';
import 'package:runquest/features/auth/data/email_verification_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/email_verification.dart';
import '../auth/nickname.dart';
import '../auth/phone_verification.dart';
import '../auth/data/phone_verification_service.dart';
import '../home/live_map_controller.dart';
import 'widgets/run_sharing_control.dart';

class PrivacyControls extends StatefulWidget {
  const PrivacyControls({this.sharingController, super.key});
  final LiveMapController? sharingController;

  @override
  State<PrivacyControls> createState() => _PrivacyControlsState();
}

class _PrivacyControlsState extends State<PrivacyControls> {
  final _client = Supabase.instance.client;
  String _visibility = 'private';
  bool _verified = false;
  String? _nickname;
  bool _busy = true;
  String? _error;

  String? get _sharingProblem {
    if (_busy || _error != null) return '공개 설정을 확인한 뒤 다시 시도해 주세요.';
    if (!_verified) return '이메일 인증 후 위치 공유를 켤 수 있습니다.';
    if (_nickname == null) return '닉네임을 등록한 뒤 위치 공유를 켜 주세요.';
    if (_visibility != 'friends' && _visibility != 'public') {
      return '친구 또는 전체 공개로 설정한 뒤 위치 공유를 켜 주세요.';
    }
    return null;
  }

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
      final verified = await SupabaseEmailVerification(_client).isVerified();
      final profile = await _client
          .from('profiles')
          .select('visibility,nickname')
          .eq('id', _client.auth.currentUser!.id)
          .single();
      if (mounted) {
        setState(() {
          _verified = verified;
          _nickname = profile['nickname'] as String?;
          _visibility = verified && _nickname != null
              ? profile['visibility'] as String
              : 'private';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '공개 설정을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String value) async {
    if (_busy || ((!_verified || _nickname == null) && value != 'private')) {
      return;
    }
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
          return EmailVerificationScreen(
            service: SupabaseEmailVerification(_client),
            onVerified: () async => Navigator.of(routeContext).pop(),
          );
        },
      ),
    );
    if (mounted) await _load();
    if (mounted && _verified && _nickname == null && _error == null) {
      await _editNickname();
    }
  }

  Future<void> _editNickname() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            NicknameScreen(service: SupabaseNicknameService(_client)),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _verifyPhone() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          PhoneVerificationScreen(service: SupabasePhoneVerification(_client)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _verified ? (_nickname ?? '나') : '나',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_verified && !_busy && _error == null)
              IconButton(
                onPressed: _editNickname,
                tooltip: _nickname == null ? '닉네임 등록' : '닉네임 변경',
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'private', label: Text('비공개')),
            ButtonSegment(value: 'friends', label: Text('친구 공개')),
            ButtonSegment(value: 'public', label: Text('전체 공개')),
          ],
          selected: {_visibility},
          showSelectedIcon: false,
          onSelectionChanged:
              _busy || !_verified || _nickname == null || _error != null
              ? null
              : (values) => _save(values.single),
        ),
        if (!_verified && !_busy && _error == null)
          TextButton(onPressed: _verify, child: const Text('이메일 인증')),
        if (_verified && _nickname == null && !_busy && _error == null)
          TextButton(onPressed: _editNickname, child: const Text('닉네임 등록')),
        TextButton.icon(
          onPressed: _busy ? null : _verifyPhone,
          icon: const Icon(Icons.phone_outlined),
          label: const Text('전화번호 인증 (선택)'),
        ),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('다시 시도'),
          ),
        ],
        if (widget.sharingController != null) ...[
          const SizedBox(height: 10),
          RunSharingControl(
            controller: widget.sharingController!,
            enablingProblem: _sharingProblem,
          ),
        ],
      ],
    );
  }
}
