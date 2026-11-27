import 'package:flutter/material.dart';

import '../settings/appearance/app_appearance.dart';

/// 프로필 화면에서 접고 펼 수 있는 구역입니다.
enum ProfileSection {
  /// 캐릭터 프로필 카드(캐릭터·레벨).
  card('profile.card_open'),

  /// 이번 주 퀘스트.
  quest('profile.quest_open');

  const ProfileSection(this.key);
  final String key;
}

/// 구역별 펼침 상태입니다. 기기에 저장하고 처음에는 모두 펼쳐 둡니다.
class ProfileSections extends ChangeNotifier {
  ProfileSections({AppearanceStore? store}) : _given = store;

  static final instance = ProfileSections();

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();
  final _closed = <ProfileSection>{};

  bool isOpen(ProfileSection section) => !_closed.contains(section);

  Future<void> load() async {
    try {
      for (final section in ProfileSection.values) {
        if (await _store.read(section.key) == '0') _closed.add(section);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle(ProfileSection section) async {
    final open = !isOpen(section);
    if (open) {
      _closed.remove(section);
    } else {
      _closed.add(section);
    }
    notifyListeners();
    try {
      await _store.write(section.key, open ? '1' : '0');
    } catch (_) {}
  }
}

/// 접힌 상태에서 [child]를 부드럽게 숨기고 펼칩니다.
class Collapsible extends StatelessWidget {
  const Collapsible({required this.open, required this.child, super.key});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: open ? child : const SizedBox(width: double.infinity, height: 0),
  );
}

/// 구역 맨 위에 놓는 접기/펼치기 줄입니다. 누르면 [section]이 접히거나 펼쳐집니다.
class SectionToggle extends StatelessWidget {
  const SectionToggle({
    required this.section,
    required this.label,
    this.sections,
    super.key,
  });

  final ProfileSection section;

  /// 화면 낭독과 도움말에 쓰는 구역 이름입니다.
  final String label;
  final ProfileSections? sections;

  @override
  Widget build(BuildContext context) {
    final state = sections ?? ProfileSections.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final open = state.isOpen(section);
        return Semantics(
          button: true,
          expanded: open,
          label: '$label ${open ? '접기' : '펼치기'}',
          child: ExcludeSemantics(
            child: IconButton(
              key: ValueKey('toggle-${section.name}'),
              tooltip: '$label ${open ? '접기' : '펼치기'}',
              visualDensity: VisualDensity.compact,
              onPressed: () => state.toggle(section),
              icon: AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
          ),
        );
      },
    );
  }
}
