import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/data/account_rpc.dart';

class FriendInviteScreen extends StatefulWidget {
  const FriendInviteScreen({required this.client, this.invite, super.key});
  final SupabaseClient client;
  final String? invite;
  @override
  State<FriendInviteScreen> createState() => _FriendInviteScreenState();
}

class _FriendInviteScreenState extends State<FriendInviteScreen> {
  late final rpc = AccountRpc(widget.client);
  late final input = TextEditingController(text: widget.invite ?? '');
  Map<String, dynamic>? _mine;
  String? _target;
  String? _previewToken;
  String? _message;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  String? _token() {
    final raw = input.text.trim();
    final uri = Uri.tryParse(raw);
    final token = uri?.scheme == 'runspot' && uri?.host == 'friend'
        ? uri?.queryParameters['token']
        : raw;
    return token != null &&
            RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(token)
        ? token
        : null;
  }

  Future<void> _load({bool renew = false}) async {
    await _work(() async {
      final data = await rpc.call('friend_invite', {
        'operation': renew ? 'renew' : 'mine',
      });
      if (mounted) {
        setState(() => _mine = Map<String, dynamic>.from(data as Map));
      }
    });
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is PostgrestException
              ? e.message
              : '초대를 처리하지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _mine == null
        ? null
        : 'runspot://friend?token=${_mine!['token']}';
    return Scaffold(
      appBar: AppBar(title: const Text('친구 초대')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '상대방에게 QR 또는 초대 링크를 보내세요. 상대방이 친구 요청을 보내고 본인이 수락해야 친구가 됩니다.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
          if (link != null) ...[
            Center(
              child: QrImageView(
                data: link,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            Text(
              '만료 ${DateTime.parse(_mine!['expires_at'] as String).toLocal().toString().substring(0, 16)}',
            ),
            Builder(
              builder: (buttonContext) => FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final box =
                            buttonContext.findRenderObject() as RenderBox?;
                        try {
                          await SharePlus.instance.share(
                            ShareParams(
                              text:
                                  '뜀터 친구 초대\n$link\n앱의 친구 초대 화면에 링크를 붙여 넣을 수도 있습니다.',
                              sharePositionOrigin: box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size,
                            ),
                          );
                        } catch (_) {
                          if (mounted) {
                            setState(() => _message = '초대 링크를 공유하지 못했습니다.');
                          }
                        }
                      },
                child: const Text('초대 링크 공유'),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _load(renew: true),
              child: const Text('기존 링크 폐기하고 새로 발급'),
            ),
          ],
          const Divider(),
          TextField(
            controller: input,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '받은 초대 링크 또는 코드'),
            onChanged: (_) => setState(() {
              _target = null;
              _previewToken = null;
            }),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _work(() async {
                    final token = _token();
                    if (token == null) {
                      setState(() => _message = '초대 링크를 확인해 주세요.');
                      return;
                    }
                    final result = await rpc.call('friend_invite', {
                      'operation': 'preview',
                      'token': token,
                    }) as Map;
                    if (mounted) {
                      setState(() {
                        _target = result['nickname'] as String;
                        _previewToken = token;
                      });
                    }
                  }),
            child: const Text('초대한 사람 확인'),
          ),
          if (_target != null)
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _work(() async {
                      await rpc.call('friend_invite', {
                        'operation': 'request',
                        'token': _previewToken,
                      });
                      if (mounted) {
                        setState(() {
                          _target = null;
                          _previewToken = null;
                          _message = '친구 요청을 보냈습니다.';
                        });
                      }
                    }),
              child: Text('$_target님에게 친구 요청'),
            ),
        ],
      ),
    );
  }
}
