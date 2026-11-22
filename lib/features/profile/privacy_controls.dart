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
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/skeleton.dart';
import '../titles/badge_directory.dart';

class PrivacyControls extends StatefulWidget {
  const PrivacyControls({
    this.sharingController,
    this.identityOnly = false,
    this.showIdentity = true,
    super.key,
  });
  final LiveMapController? sharingController;
  final bool identityOnly;
  final bool showIdentity;

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
        if (widget.showIdentity)
          ProfileIdentityHeader(
            name: _verified ? (_nickname ?? '나') : '나',
            userId: _client.auth.currentUser?.id,
            loading: _busy && _nickname == null,
            verified: _verified,
            onEdit: _verified && !_busy && _error == null
                ? _editNickname
                : null,
            editLabel: _nickname == null ? '닉네임 등록' : '닉네임 변경',
          ),
        if (!widget.identityOnly)
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
          _NextStep(
            icon: Icons.mark_email_read_outlined,
            message: '이메일을 인증하면 친구와 위치를 공유하고 함께 달릴 수 있어요.',
            action: '이메일 인증',
            onPressed: _verify,
          ),
        if (_verified && _nickname == null && !_busy && _error == null)
          _NextStep(
            icon: Icons.badge_outlined,
            message: '친구들이 나를 알아볼 수 있게 닉네임을 정해 주세요.',
            action: '닉네임 등록',
            onPressed: _editNickname,
          ),
        if (!widget.identityOnly)
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
        if (!widget.identityOnly && widget.sharingController != null) ...[
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

/// 프로필 맨 위의 내 정보입니다. 동그란 이니셜·닉네임·칭호·인증 상태를 보여줍니다.
class ProfileIdentityHeader extends StatelessWidget {
  const ProfileIdentityHeader({
    required this.name,
    required this.verified,
    this.userId,
    this.loading = false,
    this.onEdit,
    this.editLabel = '닉네임 변경',
    super.key,
  });

  final String name;
  final String? userId;
  final bool verified;
  final bool loading;
  final VoidCallback? onEdit;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (loading) {
      return const Shimmer(
        child: Row(
          children: [
            SkeletonBox.circle(size: 56),
            SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 110, height: 18),
                SizedBox(height: 8),
                SkeletonBox(width: 70, height: 12),
              ],
            ),
          ],
        ),
      );
    }
    final initial = name.trim().characters.firstOrNull ?? '나';
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B9BFF), AppColors.blueDark],
              ),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(fontSize: 19),
                    ),
                  ),
                  if (userId case final id?) UserTitle(userId: id),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    verified ? Icons.verified : Icons.info_outline,
                    size: 15,
                    color: verified ? AppColors.green : AppColors.gray,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      verified ? '인증된 러너' : '인증 전',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.gray,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            tooltip: editLabel,
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
    );
  }
}

/// 아직 하지 않은 준비 단계를 안내하고 바로 할 수 있는 버튼을 붙입니다.
class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.icon,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
    decoration: BoxDecoration(
      color: AppColors.blueSoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.blueText, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(action),
        ),
      ],
    ),
  );
}
