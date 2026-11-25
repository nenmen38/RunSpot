import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../monetization/coin_frames.dart';
import '../monetization/cosmetics.dart';
import 'character_outfit.dart';
import 'runner_character.dart';

/// 프로필의 '내 러너' 칸입니다. 위에 '꾸미기'(산 캐릭터 아이템만)가 있고,
/// 누르면 바로 캐릭터에 입혀집니다. 캐릭터는 좌우로 밀어 모든 방향에서 볼 수 있습니다.
class RunnerCharacterCard extends StatelessWidget {
  const RunnerCharacterCard({this.wallet, super.key});

  final WalletController? wallet;

  @override
  Widget build(BuildContext context) {
    final controller = wallet;
    if (controller == null) return const _Card(owned: [], worn: {});
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.wallet;
        final owned = [
          for (final item in CosmeticItem.values)
            if (item.slot.isCharacter &&
                current?.cosmetics.contains(item) == true)
              item,
        ];
        final worn = {
          for (final entry in (current?.equippedCosmetics ?? const {}).entries)
            if (entry.key.isCharacter) entry.key: entry.value,
        };
        return _Card(
          owned: owned,
          worn: worn,
          busy: controller.busy,
          onToggle: (item) async {
            final wearing = worn[item.slot] == item;
            final message = await controller.equipCosmetic(
              item.slot,
              wearing ? null : item,
            );
            if (message != null && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(message)));
            }
          },
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.owned,
    required this.worn,
    this.busy = false,
    this.onToggle,
  });

  final List<CosmeticItem> owned;
  final Map<CosmeticSlot, CosmeticItem> worn;
  final bool busy;
  final ValueChanged<CosmeticItem>? onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '꾸미기',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                owned.isEmpty ? '' : '누르면 바로 입혀져요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: AppColors.gray),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 74,
          child: owned.isEmpty
              ? Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    "아이템 > 상점의 '내 러너 캐릭터 꾸미기'에서 모자·운동화 같은 아이템을 사면 여기에 나와요.",
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(height: 1.4),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: owned.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = owned[index];
                    final wearing = worn[item.slot] == item;
                    return _OutfitChip(
                      key: ValueKey('outfit-${item.code}'),
                      item: item,
                      wearing: wearing,
                      onTap: busy || onToggle == null
                          ? null
                          : () => onToggle!(item),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: RunnerCharacterStage(
            outfit: characterOutfit(worn.values),
            height: 300,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swipe, size: 16, color: AppColors.gray),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '좌우로 밀면 돌아가요 · 두 번 누르면 정면',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: AppColors.gray),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutfitChip extends StatelessWidget {
  const _OutfitChip({
    required this.item,
    required this.wearing,
    this.onTap,
    super.key,
  });

  final CosmeticItem item;
  final bool wearing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: wearing,
    label: '${item.label} ${wearing ? '벗기' : '입히기'}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 76,
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        decoration: BoxDecoration(
          color: wearing ? AppColors.blueSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: wearing ? AppColors.blue : AppColors.line,
            width: wearing ? 2 : 1,
          ),
        ),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CharacterItemPreview(item: item, size: 38),
                  if (wearing)
                    const Positioned(
                      right: -4,
                      top: -4,
                      child: CircleAvatar(
                        radius: 8,
                        backgroundColor: AppColors.blue,
                        child: Icon(Icons.check, size: 11, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: wearing ? FontWeight.w800 : FontWeight.w600,
                  color: wearing ? AppColors.blueText : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
