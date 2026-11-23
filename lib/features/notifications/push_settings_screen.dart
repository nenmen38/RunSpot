import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/skeleton.dart';
import 'data/push_service.dart';

/// 알림 설정을 읽거나(빈 값) 바꾼 항목만 저장하고, 저장 뒤의 전체 설정을 돌려줍니다.
typedef PushPreferencesUpdate = Future<Map<String, dynamic>> Function(
  Map<String, dynamic>? changes,
);

/// 설정 화면에 보여줄 알림 항목입니다. 키는 서버 설정 이름과 같습니다.
class PushPreferenceItem {
  const PushPreferenceItem(this.key, this.title, this.subtitle, this.icon);
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

class PushPreferenceGroup {
  const PushPreferenceGroup(this.title, this.items);
  final String title;
  final List<PushPreferenceItem> items;
}

const pushPreferenceGroups = [
  PushPreferenceGroup('대화', [
    PushPreferenceItem(
      'friend_message',
      '1:1 메시지',
      '친구가 보낸 메시지',
      Icons.chat_bubble_outline,
    ),
    PushPreferenceItem(
      'room_message',
      '단체·크루 대화방',
      '단톡과 크루 대화방의 새 메시지',
      Icons.forum_outlined,
    ),
  ]),
  PushPreferenceGroup('친구·모임', [
    PushPreferenceItem(
      'friend_request',
      '친구 요청',
      '누군가 나에게 친구 요청을 보냈을 때',
      Icons.person_add_alt_1_outlined,
    ),
    PushPreferenceItem(
      'group_invite',
      '함께 달리기 초대',
      '친구가 함께 달리기에 초대했을 때',
      Icons.directions_run,
    ),
    PushPreferenceItem(
      'crew_invite',
      '크루 초대',
      '크루장이 크루에 초대했을 때',
      Icons.groups_outlined,
    ),
  ]),
  PushPreferenceGroup('게시판', [
    PushPreferenceItem(
      'board_comment',
      '댓글·답글',
      '내 글의 댓글과 내 댓글의 답글',
      Icons.mode_comment_outlined,
    ),
    PushPreferenceItem(
      'board_like',
      '좋아요',
      '내 글에 좋아요가 달렸을 때',
      Icons.favorite_border,
    ),
  ]),
  PushPreferenceGroup('표시 방식', [
    PushPreferenceItem(
      'show_preview',
      '이름과 내용 미리보기',
      '알림에 보낸 사람 이름과 메시지·댓글 내용을 보여줘요. 끄면 종류만 알려요.',
      Icons.visibility_outlined,
    ),
  ]),
];

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({
    this.update,
    this.enable,
    this.notificationsAllowed,
    super.key,
  });

  /// 테스트에서 바꿔 끼울 수 있게 합니다. 없으면 서버 설정을 씁니다.
  final PushPreferencesUpdate? update;

  /// 휴대폰 알림 권한을 요청합니다. 없으면 기기 알림 서비스를 씁니다.
  final Future<void> Function()? enable;

  /// 기기 설정에서 알림이 켜져 있는지 확인합니다. 없으면 기기 알림 서비스를 씁니다.
  final Future<bool> Function()? notificationsAllowed;

  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen>
    with WidgetsBindingObserver {
  SupabaseClient get _client => Supabase.instance.client;
  late final String? _owner = widget.update == null
      ? _client.auth.currentUser?.id
      : null;
  Map<String, dynamic>? _values;
  bool _loading = false;
  bool _enabling = false;
  String? _error;

  /// 저장 중인 항목입니다. 같은 항목을 연달아 눌러도 한 번씩만 보냅니다.
  final _saving = <String>{};

  /// 기기에서 알림이 꺼져 있으면 false입니다. 확인 전(null)에는 안내를 띄우지 않습니다.
  bool? _deviceAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkDevice();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 휴대폰 설정에서 알림을 켜고 돌아오면 바로 다시 확인해 안내를 없앱니다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDevice();
  }

  Future<void> _checkDevice() async {
    try {
      final allowed =
          await (widget.notificationsAllowed ??
              PushService.instance.notificationsAllowed)();
      if (mounted) setState(() => _deviceAllowed = allowed);
    } catch (_) {
      // 확인하지 못하면 안내를 띄우지 않습니다.
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic>? changes) async {
    if (widget.update case final update?) return update(changes);
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != _owner) {
      throw StateError('로그인이 바뀌었습니다.');
    }
    final values = await _client
        .rpc('my_push_preferences', params: changes)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    return Map<String, dynamic>.from(values as Map);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await _call(null);
      if (mounted) setState(() => _values = values);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '알림 설정을 불러오지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 스위치는 바로 바꿔 보여주고, 저장에 실패하면 원래대로 되돌립니다.
  Future<void> _toggle(String key, bool value) async {
    final values = _values;
    if (values == null || _saving.contains(key)) return;
    final before = values[key];
    setState(() {
      _saving.add(key);
      _values = {...values, key: value};
    });
    try {
      final saved = await _call({key: value});
      if (mounted) setState(() => _values = saved);
    } catch (_) {
      if (mounted) {
        setState(() => _values = {...?_values, key: before});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림 설정을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _enable() async {
    setState(() => _enabling = true);
    try {
      await (widget.enable ??
          () => PushService.instance.sync(requestPermission: true))();
      await _checkDevice();
      if (!mounted) return;
      // 권한을 허용했으면 안내가 사라지고, 여전히 꺼져 있으면 휴대폰 설정 방법을 알려줍니다.
      if (_deviceAllowed == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('휴대폰 설정 > 애플리케이션 > 뜀터 > 알림에서 알림을 켜 주세요.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림 등록에 실패했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final values = _values;
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 휴대폰(기기) 설정에서 알림이 꺼져 있을 때만 켜기 안내를 보여줍니다.
          if (_deviceAllowed == false)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.blueText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '앱을 닫아도 휴대폰으로 알림을 받으려면 알림 권한을 켜 주세요.',
                      style: text.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _enabling ? null : _enable,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('휴대폰 알림 켜기'),
                  ),
                ],
              ),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error)),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          if (values == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SkeletonList(count: 5),
            ),
          if (values != null)
            for (final group in pushPreferenceGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                child: Text(
                  group.title,
                  style: text.labelLarge?.copyWith(color: AppColors.gray),
                ),
              ),
              // 누를 때 물결 효과가 보이도록 바탕을 Material로 그립니다.
              Material(
                color: AppColors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.line),
                ),
                child: Column(
                  children: [
                    for (final (index, item) in group.items.indexed) ...[
                      if (index > 0)
                        Divider(height: 1, indent: 56, color: AppColors.line),
                      SwitchListTile(
                        key: ValueKey('push-${item.key}'),
                        secondary: Icon(item.icon, color: AppColors.gray),
                        title: Text(item.title),
                        subtitle: Text(item.subtitle),
                        value: values[item.key] != false,
                        onChanged: _saving.contains(item.key)
                            ? null
                            : (value) => _toggle(item.key, value),
                      ),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}
