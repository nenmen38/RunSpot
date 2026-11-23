import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/data/account_rpc.dart';
import '../moderation/report_dialog.dart';
import 'avatar_directory.dart';
import 'data/profile_avatar_service.dart';

typedef _Photo = ({String version, Uint8List bytes, AccountRpc api});

/// 프로필에 실제로 표시한 사진을 그대로 신고 창과 접수 요청에 사용합니다.
class ReportableAvatarHeader extends StatefulWidget {
  const ReportableAvatarHeader({
    required this.userId,
    required this.nickname,
    required this.size,
    super.key,
  });
  final String userId;
  final String nickname;
  final double size;

  @override
  State<ReportableAvatarHeader> createState() => _ReportableAvatarHeaderState();
}

class _ReportableAvatarHeaderState extends State<ReportableAvatarHeader> {
  late Future<_Photo?> _photo = _load();
  bool _busy = false;
  AccountRpc? get _api => AvatarDirectory.instance.reports;

  Future<_Photo?> _load() async {
    final api = _api;
    if (api == null || api.owner == widget.userId) return null;
    final data =
        await api.call('reportable_avatar', {'target': widget.userId}) as Map?;
    if (data == null) return null;
    return (
      api: api,
      version: data['version'] as String,
      bytes: decodeAvatarBase64(data['photo'] as String),
    );
  }

  @override
  void didUpdateWidget(ReportableAvatarHeader old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _photo = _load();
  }

  Future<void> _report(_Photo photo) async {
    final api = photo.api;
    if (_busy || !identical(_api, api)) return;
    final target = widget.userId;
    setState(() => _busy = true);
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => ReportDialog(
          title: '프로필 사진 신고',
          preview: Image.memory(photo.bytes, width: 112, height: 112),
          explanation: '이 사진이 신고 증거로 관리자에게 전달됩니다.',
        ),
      );
      if (!mounted || reason == null || target != widget.userId) return;
      await api.call('report_avatar', {
        'target': target,
        'version_id': photo.version,
        'jpeg': base64Encode(photo.bytes),
        'reason': reason,
      });
      _notice('프로필 사진 신고가 접수되었습니다.');
    } on PostgrestException catch (error) {
      _notice(error.message);
    } catch (_) {
      _notice('신고하지 못했습니다. 계정과 연결 상태를 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Photo?>(
    future: _photo,
    builder: (context, snapshot) {
      final photo = snapshot.connectionState == ConnectionState.done
          ? snapshot.data
          : null;
      return Row(
        children: [
          if (photo != null)
            CircleAvatar(
              radius: widget.size / 2,
              foregroundImage: MemoryImage(photo.bytes),
            )
          else
            UserAvatar(
              nickname: widget.nickname,
              userId: widget.userId,
              size: widget.size,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.nickname,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (snapshot.hasError)
            IconButton(
              tooltip: '프로필 사진 다시 불러오기',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _photo = _load()),
            ),
          if (photo != null)
            IconButton(
              tooltip: '프로필 사진 신고',
              icon: const Icon(Icons.flag_outlined),
              onPressed: _busy ? null : () => _report(photo),
            ),
        ],
      );
    },
  );
}
