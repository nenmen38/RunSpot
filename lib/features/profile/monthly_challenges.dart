import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/account_query_panel.dart';
import '../../shared/widgets/panel.dart';
import '../monetization/cosmetics.dart';

/// 한 달 동안의 개인 챌린지 하나입니다.
@immutable
class Challenge {
  const Challenge({
    required this.code,
    required this.progress,
    required this.goal,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
    code: json['code'] as String,
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    goal: (json['goal'] as num?)?.toInt() ?? 1,
  );

  final String code;
  final int progress;
  final int goal;

  bool get done => progress >= goal;
  double get ratio => goal <= 0 ? 0 : (progress / goal).clamp(0.0, 1.0);

  String get title => switch (code) {
    'distance_50k' => '이번 달 50km 달리기',
    'weekend_4' => '주말에 4번 달리기',
    'days_10' => '10일 달리기',
    _ => code,
  };

  String get detail => switch (code) {
    'distance_50k' =>
      '${(progress / 1000).toStringAsFixed(1)} / ${goal ~/ 1000}km',
    'weekend_4' => '$progress / $goal번',
    'days_10' => '$progress / $goal일',
    _ => '$progress / $goal',
  };

  IconData get icon => switch (code) {
    'distance_50k' => Icons.route_outlined,
    'weekend_4' => Icons.weekend_outlined,
    _ => Icons.calendar_month_outlined,
  };
}

/// 이번 달 챌린지 묶음입니다.
@immutable
class MonthlyChallenges {
  const MonthlyChallenges({
    required this.month,
    required this.challenges,
    required this.allDone,
    this.reward,
    this.completedMonths = 0,
  });

  factory MonthlyChallenges.fromJson(Map<String, dynamic> json) =>
      MonthlyChallenges(
        month: DateTime.parse(json['month'] as String),
        challenges: [
          for (final item in json['challenges'] as List? ?? const [])
            Challenge.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        allDone: json['all_done'] == true,
        reward: CosmeticItem.fromCode(json['reward_item']),
        completedMonths: (json['completed_months'] as num?)?.toInt() ?? 0,
      );

  final DateTime month;
  final List<Challenge> challenges;
  final bool allDone;

  /// 모두 마치면 받는 캐릭터 아이템입니다(12월은 산타 러닝캡).
  final CosmeticItem? reward;

  /// 지금까지 세 가지를 모두 마친 달 수입니다.
  final int completedMonths;
}

abstract interface class ChallengeService {
  bool get isCurrentOwner;
  Future<MonthlyChallenges> load();
}

class SupabaseChallengeService implements ChallengeService {
  SupabaseChallengeService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentUser?.id == _owner;

  @override
  Future<MonthlyChallenges> load() async => MonthlyChallenges.fromJson(
    Map<String, dynamic>.from(await client.rpc('my_challenges') as Map),
  );
}

/// 프로필의 '이번 달 챌린지' 카드입니다. 달성하면 서버가 완료로 기록하고 보상을 줍니다.
class MonthlyChallengeCard extends StatelessWidget {
  const MonthlyChallengeCard({required this.service, super.key});

  final ChallengeService service;

  @override
  Widget build(BuildContext context) => Panel(
    child: AccountQueryPanel<MonthlyChallenges>(
      source: service,
      load: service.load,
      isCurrentOwner: () => service.isCurrentOwner,
      errorMessage: '챌린지를 불러오지 못했어요.',
      showRefresh: false,
      builder: (context, data) => _ChallengeBody(data: data),
    ),
  );
}

class _ChallengeBody extends StatelessWidget {
  const _ChallengeBody({required this.data});

  final MonthlyChallenges data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = data.challenges.where((c) => c.done).length;
    return Column(
      key: const ValueKey('monthly-challenges'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_outlined, color: AppColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${data.month.month}월 챌린지',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '$done / ${data.challenges.length}',
              style: text.titleSmall?.copyWith(
                color: AppColors.blueText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          data.allDone
              ? switch (data.reward) {
                  final item? => '🎉 모두 완료! ${item.label}을 선물로 받았어요.',
                  null => '🎉 이번 달 챌린지를 모두 완료했어요!',
                }
              : switch (data.reward) {
                  final item? => '세 가지를 모두 마치면 🎅 ${item.label}을 선물로 받아요.',
                  null => '세 가지를 모두 마치면 이번 달 챌린지 완주예요.',
                },
          style: text.bodySmall?.copyWith(color: AppColors.gray),
        ),
        const SizedBox(height: 8),
        for (final challenge in data.challenges)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label:
                  '${challenge.title}, ${challenge.detail}${challenge.done ? ', 완료' : ''}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(
                      challenge.done ? Icons.check_circle : challenge.icon,
                      size: 22,
                      color: challenge.done ? AppColors.green : AppColors.gray,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  challenge.title,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                challenge.detail,
                                style: text.bodySmall?.copyWith(
                                  color: AppColors.gray,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          LinearProgressIndicator(
                            value: challenge.ratio,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(6),
                            backgroundColor: AppColors.line,
                            color: challenge.done
                                ? AppColors.green
                                : AppColors.blue,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (data.completedMonths > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '지금까지 챌린지 완주 ${data.completedMonths}번',
              style: text.bodySmall?.copyWith(color: AppColors.gray),
            ),
          ),
      ],
    );
  }
}
