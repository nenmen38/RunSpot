import 'data/nickname_service.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../profile/data/profile_avatar_service.dart';

/// 닉네임을 정합니다. [avatarService]가 있으면 프로필 편집 화면으로 열려 프로필 사진도 함께 바꿉니다.
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({
    required this.service,
    this.avatarService,
    this.pickPhoto = pickProfilePhoto,
    super.key,
  });
  final NicknameService service;
  final ProfileAvatarService? avatarService;

  /// 갤러리에서 사진을 고릅니다. 테스트에서 바꿔 끼울 수 있게 합니다.
  final Future<Uint8List?> Function() pickPhoto;

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _controller = TextEditingController();
  NicknameState? _state;
  bool _busy = true;
  String? _error;
  Uint8List? _photo;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _state = null;
    });
    // 사진은 닉네임과 따로 불러와 실패해도 닉네임 변경은 할 수 있게 합니다.
    if (widget.avatarService case final avatars?) {
      avatars
          .load()
          .then((photo) {
            if (mounted) setState(() => _photo = photo);
          })
          .catchError((Object _) {});
    }
    try {
      final state = await widget.service.load();
      if (!mounted) return;
      _controller.text = state.nickname ?? '';
      setState(() => _state = state);
    } catch (_) {
      if (mounted) setState(() => _error = '닉네임 정보를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _state?.canChange(DateTime.now()) != true) return;
    final error = validateNickname(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.save(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            '23505' => '이미 사용 중인 닉네임입니다.',
            '42501' => '이메일 인증 상태를 확인해 주세요.',
            'P0001' => '닉네임은 30일에 한 번 변경할 수 있습니다.',
            '22023' => '닉네임 형식을 확인해 주세요.',
            _ => '닉네임을 저장하지 못했습니다. 다시 시도해 주세요.',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '닉네임을 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// 사진을 누르면 앨범에서 고르거나 기본 이미지로 되돌릴 수 있습니다. 고르면 바로 저장합니다.
  Future<void> _changePhoto() async {
    final avatars = widget.avatarService;
    if (avatars == null || _photoBusy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 사진 선택'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.no_photography_outlined),
                title: const Text('기본 이미지로 변경'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      if (action == 'remove') {
        await avatars.remove();
        if (mounted) setState(() => _photo = null);
      } else {
        final photo = await widget.pickPhoto();
        if (photo == null) return;
        await avatars.save(photo);
        if (mounted) setState(() => _photo = photo);
      }
      if (mounted) _tell('프로필 사진을 바꿨어요.');
    } on ProfilePhotoException catch (error) {
      if (mounted) _tell(error.message);
    } on PostgrestException catch (error) {
      if (mounted) {
        _tell(
          error.code == 'P0001'
              ? '잠시 후 다시 바꿔 주세요.'
              : '프로필 사진을 저장하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } catch (_) {
      if (mounted) _tell('프로필 사진을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Widget _photoEditor() {
    final initial = _controller.text.trim().characters.firstOrNull ?? '나';
    final photo = _photo;
    return Center(
      child: Semantics(
        button: true,
        label: '프로필 사진 바꾸기',
        child: InkWell(
          key: const ValueKey('profile-photo'),
          customBorder: const CircleBorder(),
          onTap: _photoBusy ? null : _changePhoto,
          child: Stack(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5B9BFF), AppColors.blueDark],
                    ),
                  ),
                  child: photo != null
                      ? Image.memory(
                          photo,
                          width: 104,
                          height: 104,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              if (_photoBusy)
                const Positioned.fill(
                  child: Center(child: CircularProgressIndicator()),
                ),
              // 오른쪽 아래 카메라 표시로 누를 수 있음을 알려줍니다.
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    size: 18,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canChange = _state?.canChange(DateTime.now()) == true;
    final next = _state?.nextChangeAt?.toLocal();
    final editingProfile = widget.avatarService != null;
    return Scaffold(
      appBar: AppBar(title: Text(editingProfile ? '프로필 편집' : '닉네임')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (editingProfile) ...[
                _photoEditor(),
                const SizedBox(height: 8),
                Text(
                  '사진을 눌러 앨범에서 바꿀 수 있어요.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.gray),
                ),
                const SizedBox(height: 20),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_state != null && !_state!.verified)
                const Text('이메일 인증 후 닉네임을 등록할 수 있습니다.'),
              if (_state?.verified == true && !canChange && next != null)
                Text(
                  '변경 가능: ${next.year}년 ${next.month}월 ${next.day}일 ${next.hour}시 ${next.minute}분',
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_busy && canChange,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  helperText: '한글·영문·숫자·밑줄 2~30자',
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_state == null && !_busy)
                TextButton(onPressed: _load, child: const Text('다시 시도')),
              FilledButton(
                onPressed: !_busy && canChange ? _save : null,
                child: Text(editingProfile ? '닉네임 저장' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
