import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../monetization/cosmetics.dart';
import 'character_outfit.dart';
import 'runner_character.dart';

/// 다른 러너들이 입은 캐릭터 아이템을 서버에 묻습니다. 결과는 {사용자 ID: 입은 아이템들}이며
/// 볼 수 없는 사람(차단·탈퇴 등)은 빠집니다.
abstract interface class RunnerCharacterSource {
  bool get isCurrentOwner;
  Future<Map<String, List<CosmeticItem>>> load(List<String> userIds);
}

class SupabaseRunnerCharacterSource implements RunnerCharacterSource {
  SupabaseRunnerCharacterSource(this.client)
    : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentUser?.id == _owner;

  @override
  Future<Map<String, List<CosmeticItem>>> load(List<String> userIds) async {
    final result = await client.rpc(
      'runner_characters',
      params: {'user_ids': userIds},
    );
    return {
      for (final entry in Map<String, dynamic>.from(
        result as Map? ?? const {},
      ).entries)
        entry.key: [
          for (final code in Map<String, dynamic>.from(
            entry.value as Map? ?? const {},
          ).values)
            ?CosmeticItem.fromCode(code),
        ],
    };
  }
}

/// 화면에 나온 러너들의 캐릭터 옷차림을 모아서 한 번에 불러오고 5분 동안 기억합니다.
class RunnerCharacterDirectory extends ChangeNotifier {
  RunnerCharacterDirectory._();
  static final instance = RunnerCharacterDirectory._();
  static const _maxAge = Duration(minutes: 5);

  RunnerCharacterSource? _source;
  final _cache = <String, (CharacterOutfit?, DateTime)>{};
  final _wanted = <String>{};
  bool _scheduled = false;
  int _generation = 0;

  void bind(RunnerCharacterSource source) {
    _source = source;
    _clear();
  }

  void unbind() {
    _source = null;
    _clear();
  }

  void _clear() {
    _generation++;
    _cache.clear();
    _wanted.clear();
    notifyListeners();
  }

  /// 내 옷을 바꾸면 크루 화면 등에 보이는 캐릭터도 다시 불러오게 합니다.
  void invalidate() {
    _cache.clear();
    notifyListeners();
  }

  /// 아직 모르면 null이고, 불러오면 알려 줍니다(볼 수 없는 사람은 맨몸 캐릭터).
  CharacterOutfit? outfitOf(String userId) {
    final entry = _cache[userId];
    if (entry == null || DateTime.now().difference(entry.$2) >= _maxAge) {
      _want(userId);
    }
    return entry?.$1;
  }

  void _want(String userId) {
    if (_source == null || userId.isEmpty) return;
    _wanted.add(userId);
    if (_scheduled) return;
    _scheduled = true;
    // 한 화면을 그리는 동안 모인 요청을 묶어서 보냅니다.
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    final source = _source;
    if (source == null || !source.isCurrentOwner) return;
    final generation = _generation;
    final batch = _wanted.take(100).toList();
    _wanted.removeAll(batch);
    if (batch.isEmpty) return;
    final now = DateTime.now();
    try {
      final found = await source.load(batch);
      if (generation != _generation) return;
      for (final id in batch) {
        _cache[id] = (characterOutfit(found[id] ?? const []), now);
      }
    } catch (_) {
      // 못 불러오면 맨몸 캐릭터로 보여 주고 잠시 뒤 다시 묻습니다.
      if (generation != _generation) return;
      for (final id in batch) {
        _cache[id] = (CharacterOutfit.none, now);
      }
    }
    notifyListeners();
    if (_wanted.isNotEmpty) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
  }
}

/// 다른 러너의 캐릭터입니다. [interactive]면 좌우로 돌려 볼 수 있는 트랙 무대로,
/// 아니면 작은 전신 그림으로 보여 줍니다.
class UserRunnerCharacter extends StatelessWidget {
  const UserRunnerCharacter({
    required this.userId,
    this.height = 220,
    this.interactive = true,
    this.yaw = -0.35,
    super.key,
  });

  final String userId;
  final double height;
  final bool interactive;
  final double yaw;

  @override
  Widget build(BuildContext context) {
    final directory = RunnerCharacterDirectory.instance;
    return ListenableBuilder(
      listenable: directory,
      builder: (context, _) {
        final outfit = directory.outfitOf(userId) ?? CharacterOutfit.none;
        if (interactive) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: RunnerCharacterStage(outfit: outfit, height: height),
          );
        }
        return SizedBox(
          height: height,
          child: CustomPaint(
            key: ValueKey('user-runner-$userId'),
            painter: RunnerCharacterPainter(yaw: yaw, outfit: outfit),
          ),
        );
      },
    );
  }
}

/// 크루 화면의 '우리 크루 러너들'입니다. 트랙 위에 크루원들의 캐릭터가 나란히 서 있습니다.
class CrewRunnersStrip extends StatelessWidget {
  const CrewRunnersStrip({required this.members, super.key});

  /// (사용자 ID, 닉네임, 크루장인지) 목록입니다.
  final List<({String userId, String nickname, bool owner})> members;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: TrackBackgroundPainter(dark: dark)),
            ListView.separated(
              key: const ValueKey('crew-runners'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final member = members[index];
                return Semantics(
                  label: '${member.nickname}의 러너',
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        Expanded(
                          child: ExcludeSemantics(
                            child: UserRunnerCharacter(
                              userId: member.userId,
                              interactive: false,
                              height: double.infinity,
                              // 서로 조금씩 다른 방향을 보게 해 자연스럽게 섭니다.
                              yaw: -0.5 + (index % 3) * 0.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: ExcludeSemantics(
                            child: Text(
                              member.owner
                                  ? '👑 ${member.nickname}'
                                  : member.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF191F28),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
