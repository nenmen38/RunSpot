import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/push_service.dart';

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({super.key});
  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen> {
  final _client = Supabase.instance.client;
  late final _owner = _client.auth.currentUser?.id;
  Map<String, dynamic>? _values;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update([Map<String, dynamic>? params]) async {
    final session = _client.auth.currentSession;
    if (_busy || session == null || session.user.id != _owner) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await _client
          .rpc('my_push_preferences', params: params)
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (mounted && _client.auth.currentUser?.id == _owner) {
        setState(() => _values = Map<String, dynamic>.from(values as Map));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '알림 설정을 저장하거나 불러오지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PushService.instance.sync(requestPermission: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('권한을 허용하면 알림을 받을 수 있어요. 이미 거부한 경우 휴대폰 설정에서 알림을 켜 주세요.'),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '알림 등록에 실패했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('알림 설정')),
    body: ListView(
      children: [
        const ListTile(
          title: Text('활동 알림'),
          subtitle: Text('잠금 화면에는 닉네임과 댓글 내용을 표시하지 않습니다.'),
        ),
        ListTile(
          title: const Text('휴대폰 알림 켜기'),
          trailing: const Icon(Icons.notifications_active_outlined),
          onTap: _busy ? null : _enable,
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: TextButton(
              onPressed: _busy ? null : _update,
              child: const Text('다시 시도'),
            ),
          ),
        if (_values != null)
          for (final entry in const {
            'friend_request': '친구 요청',
            'group_invite': '함께 달리기 초대',
            'board_comment': '내 글의 댓글·답글',
          }.entries)
            SwitchListTile(
              title: Text(entry.value),
              value: _values![entry.key] == true,
              onChanged: _busy ? null : (value) => _update({entry.key: value}),
            ),
      ],
    ),
  );
}
