import 'package:supabase_flutter/supabase_flutter.dart';

import '../monetization/cosmetics.dart';

/// 칭호 하나의 진행입니다. [progress]가 [goal]에 닿으면 얻은 칭호입니다.
class TitleProgress {
  const TitleProgress({
    required this.title,
    required this.progress,
    required this.goal,
    required this.earned,
  });

  final RunnerTitle title;
  final int progress;
  final int goal;
  final bool earned;

  double get ratio => goal <= 0 ? 0 : (progress / goal).clamp(0, 1).toDouble();

  /// 사람이 읽기 쉬운 진행 표시입니다. 예: 7.2 / 10km, 3 / 10회
  String get label => switch (title) {
    RunnerTitle.tenK || RunnerTitle.half =>
      '${(progress / 1000).toStringAsFixed(1)} / ${(goal / 1000).toStringAsFixed(1)}km',
    RunnerTitle.steady => '$progress / $goal주',
    RunnerTitle.crewLeader => '$progress / $goal명',
    _ => '$progress / $goal회',
  };
}

class TitlesState {
  const TitlesState({required this.selected, required this.titles});

  TitlesState.fromJson(Map<String, dynamic> json)
    : selected = RunnerTitle.fromCode(json['selected']),
      titles = [
        for (final row in json['titles'] as List? ?? const [])
          if (RunnerTitle.fromCode((row as Map)['code']) case final title?)
            TitleProgress(
              title: title,
              progress: (row['progress'] as num).toInt(),
              goal: (row['goal'] as num).toInt(),
              earned: row['earned'] == true,
            ),
      ];

  final RunnerTitle? selected;
  final List<TitleProgress> titles;
}

/// 다른 사람에게 보이는 칭호와 꾸미기입니다.
class UserBadge {
  const UserBadge({this.title, this.titleStyle, this.chatBubble});

  UserBadge.fromJson(Map<String, dynamic> json)
    : title = RunnerTitle.fromCode(json['title']),
      titleStyle = CosmeticItem.fromCode(json['title_style']),
      chatBubble = CosmeticItem.fromCode(json['chat_bubble']);

  final RunnerTitle? title;
  final CosmeticItem? titleStyle;
  final CosmeticItem? chatBubble;
}

abstract interface class TitleService {
  bool get isCurrentOwner;
  Future<TitlesState> load();

  /// [title]이 null이면 칭호를 뗍니다.
  Future<TitlesState> select(RunnerTitle? title);

  /// 사용자 ID별 칭호·꾸미기입니다.
  Future<Map<String, UserBadge>> userBadges(List<String> userIds);

  /// 게시글 ID별 글쓴이의 칭호·모양입니다.
  Future<Map<String, UserBadge>> postBadges(List<String> postIds);
}

class SupabaseTitleService implements TitleService {
  SupabaseTitleService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return result;
  }

  Map<String, UserBadge> _badges(dynamic result) => {
    for (final entry in Map<String, dynamic>.from(result as Map).entries)
      entry.key: UserBadge.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      ),
  };

  @override
  Future<TitlesState> load() async => TitlesState.fromJson(
    Map<String, dynamic>.from(await _rpc('my_titles') as Map),
  );

  @override
  Future<TitlesState> select(RunnerTitle? title) async => TitlesState.fromJson(
    Map<String, dynamic>.from(
      await _rpc('set_title', {'requested': title?.code}) as Map,
    ),
  );

  @override
  Future<Map<String, UserBadge>> userBadges(List<String> userIds) async =>
      _badges(await _rpc('user_badges', {'user_ids': userIds}));

  @override
  Future<Map<String, UserBadge>> postBadges(List<String> postIds) async =>
      _badges(await _rpc('post_author_badges', {'post_ids': postIds}));
}
