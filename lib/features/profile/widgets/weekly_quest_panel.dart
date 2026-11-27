import 'package:flutter/material.dart';

import '../../../shared/widgets/page_layout.dart';
import '../../../shared/widgets/panel.dart';
import '../../monetization/coin_frames.dart';
import '../profile_sections.dart';

class WeeklyQuestPanel extends StatelessWidget {
  const WeeklyQuestPanel({required this.controller, this.sections, super.key});

  final WalletController controller;

  /// 펼침 상태 저장소입니다(기본은 기기에 저장).
  final ProfileSections? sections;

  Future<void> _claim(BuildContext context, WeeklyCoinQuest quest) async {
    if (controller.busy) return;
    final error = await controller.claimWeeklyQuest(quest.code);
    if (!context.mounted || !controller.service.isCurrentOwner) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '${quest.reward}코인을 받았어요.')),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final wallet = controller.wallet;
      if (wallet == null || !controller.service.isCurrentOwner) {
        return const SizedBox.shrink();
      }
      final quests = wallet.weeklyQuests.isNotEmpty
          ? wallet.weeklyQuests
          : [?wallet.weeklyQuest];
      if (quests.isEmpty) return const SizedBox.shrink();

      final completed = quests.where((quest) => quest.completed).length;
      final reward = quests.fold(0, (total, quest) => total + quest.reward);
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Panel(
          child: ListenableBuilder(
            listenable: sections ?? ProfileSections.instance,
            builder: (context, _) {
              final open = (sections ?? ProfileSections.instance).isOpen(
                ProfileSection.quest,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeader(
                          title: '이번 주 퀘스트',
                          subtitle:
                              '$completed/${quests.length}개 완료 · 최대 $reward 코인',
                          icon: Icons.task_alt_outlined,
                        ),
                      ),
                      SectionToggle(
                        section: ProfileSection.quest,
                        label: '이번 주 퀘스트',
                        sections: sections,
                      ),
                    ],
                  ),
                  Collapsible(
                    open: open,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final quest in quests) ...[
                          const Divider(height: 24),
                          _QuestRow(
                            quest: quest,
                            busy: controller.busy,
                            onClaim: () => _claim(context, quest),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({
    required this.quest,
    required this.busy,
    required this.onClaim,
  });

  final WeeklyCoinQuest quest;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quest.label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: quest.completed
              ? 1
              : (quest.progress / quest.goal).clamp(0, 1),
          minHeight: 5,
          borderRadius: BorderRadius.circular(4),
          semanticsLabel: '${quest.label} 진행률',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                quest.completed
                    ? '${quest.reward}코인'
                    : '${quest.progressLabel} · ${quest.reward}코인',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (quest.awarded)
              Text('수령 완료', style: theme.textTheme.labelMedium)
            else if (quest.completed)
              FilledButton(
                onPressed: busy ? null : onClaim,
                child: const Text('보상 받기'),
              ),
          ],
        ),
      ],
    );
  }
}
