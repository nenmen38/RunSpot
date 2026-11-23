import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../crew/models/crew.dart';
import 'chat_room_style.dart';

/// 새 대화에서 고른 사람과 대화방 이름입니다.
class NewChatSelection {
  const NewChatSelection(this.members, this.name);

  /// 고른 사람(사용자 ID → 닉네임)입니다. 나는 빼고 담습니다.
  final Map<String, String> members;
  final String? name;
}

/// 대화를 시작할 사람을 고르는 화면입니다. 친구 목록과 크루별 크루원 목록(펼치기·접기)에서
/// 여러 명을 고르면 단톡을, 친구 한 명을 고르면 1:1 대화를 엽니다.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({
    required this.friends,
    required this.crews,
    required this.ownerId,
    super.key,
  });

  /// 친구(사용자 ID, 닉네임)입니다.
  final List<({String id, String nickname})> friends;
  final List<Crew> crews;
  final String? ownerId;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _selected = <String, String>{};
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(String id, String nickname, bool on) => setState(() {
    if (on) {
      _selected[id] = nickname;
    } else {
      _selected.remove(id);
    }
  });

  Widget _person(String id, String nickname) => CheckboxListTile(
    key: ValueKey('pick-$id'),
    value: _selected.containsKey(id),
    onChanged: (on) => _toggle(id, nickname, on ?? false),
    secondary: ChatAvatar(nickname: nickname, userId: id, size: 36),
    title: Text(nickname),
    controlAffinity: ListTileControlAffinity.trailing,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final count = _selected.length;
    return Scaffold(
      appBar: AppBar(title: const Text('새 대화')),
      body: Column(
        children: [
          if (count > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in _selected.entries)
                      InputChip(
                        label: Text(entry.value),
                        onDeleted: () => _toggle(entry.key, entry.value, false),
                      ),
                  ],
                ),
              ),
            ),
          if (count >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                key: const ValueKey('room-name'),
                controller: _name,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '대화방 이름 (선택)',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    '친구 ${widget.friends.length}',
                    style: text.titleSmall,
                  ),
                ),
                if (widget.friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('아직 친구가 없어요.'),
                  ),
                for (final friend in widget.friends)
                  _person(friend.id, friend.nickname),
                if (widget.crews.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('크루', style: text.titleSmall),
                  ),
                for (final crew in widget.crews)
                  _CrewSection(
                    key: ValueKey('crew-section-${crew.id}'),
                    crew: crew,
                    members: [
                      for (final member in crew.members)
                        if (member.userId != widget.ownerId) member,
                    ],
                    selected: _selected,
                    person: _person,
                    onSelectAll: (members, on) => setState(() {
                      for (final member in members) {
                        if (on) {
                          _selected[member.userId] = member.nickname;
                        } else {
                          _selected.remove(member.userId);
                        }
                      }
                    }),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  onPressed: count == 0
                      ? null
                      : () => Navigator.of(context).pop(
                          NewChatSelection(
                            Map.of(_selected),
                            _name.text.trim().isEmpty
                                ? null
                                : _name.text.trim(),
                          ),
                        ),
                  child: Text(
                    count == 0
                        ? '대화할 사람을 골라 주세요'
                        : count == 1
                        ? '대화 시작'
                        : '단톡 만들기 ($count명)',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 크루 이름을 누르면 크루원 목록을 펼치고 접습니다.
class _CrewSection extends StatelessWidget {
  const _CrewSection({
    required this.crew,
    required this.members,
    required this.selected,
    required this.person,
    required this.onSelectAll,
    super.key,
  });

  final Crew crew;
  final List<CrewMember> members;
  final Map<String, String> selected;
  final Widget Function(String id, String nickname) person;
  final void Function(List<CrewMember> members, bool on) onSelectAll;

  @override
  Widget build(BuildContext context) {
    final all =
        members.isNotEmpty &&
        members.every((m) => selected.containsKey(m.userId));
    return ExpansionTile(
      leading: Icon(crew.icon.icon, color: crew.icon.color),
      title: Text(crew.name),
      subtitle: Text('크루원 ${members.length}명'),
      children: [
        if (members.isEmpty)
          const ListTile(title: Text('함께 대화할 크루원이 아직 없어요.'))
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onSelectAll(members, !all),
              child: Text(
                all ? '모두 해제' : '크루원 모두 선택',
                style: TextStyle(color: AppColors.blueText),
              ),
            ),
          ),
          for (final member in members) person(member.userId, member.nickname),
        ],
      ],
    );
  }
}
