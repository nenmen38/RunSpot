import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../monetization/coin_frames.dart';
import '../monetization/cosmetics.dart';
import 'character_outfit.dart';
import 'runner_character.dart';

/// 캐릭터 꾸미기 칸(모자·선글라스·상의·하의·팔토시·운동화) 순서입니다.
final characterSlots = [
  for (final slot in CosmeticSlot.values)
    if (slot.isCharacter) slot,
];

/// 지금 입고 있는 캐릭터 아이템입니다(칸마다 하나).
Map<CosmeticSlot, CosmeticItem> wornCharacterItems(Wallet? wallet) => {
  for (final entry in (wallet?.equippedCosmetics ?? const {}).entries)
    if (entry.key.isCharacter) entry.key: entry.value,
};

/// 프로필의 '내 러너' 칸입니다. 입은 아이템이 바로 보이고, 좌우로 밀어 모든 방향에서 볼 수 있습니다.
class RunnerCharacterCard extends StatelessWidget {
  const RunnerCharacterCard({this.wallet, super.key});

  final WalletController? wallet;

  @override
  Widget build(BuildContext context) {
    final controller = wallet;
    if (controller == null) return const _CharacterView(worn: {});
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) =>
          _CharacterView(worn: wornCharacterItems(controller.wallet)),
    );
  }
}

class _CharacterView extends StatelessWidget {
  const _CharacterView({required this.worn});

  final Map<CosmeticSlot, CosmeticItem> worn;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: RunnerCharacterStage(
            outfit: characterOutfit(worn.values),
            height: 280,
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

/// 프로필 편집 버튼 왼쪽의 '꾸미기' 버튼입니다. 누르면 카테고리별 꾸미기 창이 열립니다.
class CharacterDressButton extends StatelessWidget {
  const CharacterDressButton({required this.wallet, super.key});

  final WalletController wallet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: FilledButton.tonalIcon(
      key: const ValueKey('character-dress-button'),
      onPressed: () => showCharacterDresser(context, wallet),
      icon: const Icon(Icons.checkroom, size: 18),
      label: const Text('꾸미기', style: TextStyle(fontWeight: FontWeight.w800)),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// 캐릭터 꾸미기 창입니다. 위에서 캐릭터를 돌려 보며, 아래 카테고리 탭에서 산 아이템을 골라 입습니다.
Future<void> showCharacterDresser(
  BuildContext context,
  WalletController wallet,
) => showDialog<void>(
  context: context,
  builder: (_) => _CharacterDresser(wallet: wallet),
);

class _CharacterDresser extends StatelessWidget {
  const _CharacterDresser({required this.wallet});

  final WalletController wallet;

  Future<void> _toggle(
    BuildContext context,
    CosmeticSlot slot,
    CosmeticItem? item,
  ) async {
    final message = await wallet.equipCosmetic(slot, item);
    if (message != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: (screen.height - 48).clamp(360.0, 720.0),
        ),
        child: DefaultTabController(
          length: characterSlots.length,
          child: ListenableBuilder(
            listenable: wallet,
            builder: (context, _) {
              final owned = wallet.wallet?.cosmetics ?? const {};
              final worn = wornCharacterItems(wallet.wallet);
              final compact = screen.height < 640;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 6, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '캐릭터 꾸미기',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: '닫기',
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RunnerCharacterStage(
                        outfit: characterOutfit(worn.values),
                        height: compact ? 170 : 220,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                    tabs: [
                      for (final slot in characterSlots)
                        Tab(
                          key: ValueKey('dress-tab-${slot.code}'),
                          height: 40,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(slot.label),
                              if (worn[slot] != null) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: AppColors.blue,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  Flexible(
                    child: SizedBox(
                      height: compact ? 170 : 250,
                      child: TabBarView(
                        children: [
                          for (final slot in characterSlots)
                            _SlotItems(
                              slot: slot,
                              items: [
                                for (final item in CosmeticItem.values)
                                  if (item.slot == slot && owned.contains(item))
                                    item,
                              ],
                              worn: worn[slot],
                              busy: wallet.busy,
                              onSelect: (item) => _toggle(context, slot, item),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('완료'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 한 카테고리의 산 아이템들입니다. 맨 앞 '없음'을 고르면 그 칸을 벗습니다.
class _SlotItems extends StatelessWidget {
  const _SlotItems({
    required this.slot,
    required this.items,
    required this.worn,
    required this.busy,
    required this.onSelect,
  });

  final CosmeticSlot slot;
  final List<CosmeticItem> items;
  final CosmeticItem? worn;
  final bool busy;
  final ValueChanged<CosmeticItem?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checkroom, size: 34, color: AppColors.gray),
              const SizedBox(height: 8),
              Text(
                "아직 산 ${slot.label} 아이템이 없어요.\n아이템 > 상점의 '내 러너 캐릭터 꾸미기'에서 살 수 있어요.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.gray, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }
    return GridView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 108,
        mainAxisExtent: 104,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      children: [
        _ItemTile(
          key: ValueKey('dress-none-${slot.code}'),
          label: '없음',
          selected: worn == null,
          onTap: busy || worn == null ? null : () => onSelect(null),
          child: Icon(Icons.block, size: 30, color: AppColors.gray),
        ),
        for (final item in items)
          _ItemTile(
            key: ValueKey('dress-${item.code}'),
            label: item.label,
            selected: worn == item,
            onTap: busy || worn == item ? null : () => onSelect(item),
            child: CharacterItemPreview(item: item, size: 58),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.label,
    required this.selected,
    required this.child,
    this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: selected ? '$label, 착용 중' : '$label 입히기',
    child: Material(
      color: selected ? AppColors.blueSoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.blue : AppColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      child,
                      if (selected)
                        const Positioned(
                          right: 2,
                          top: -2,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: AppColors.blue,
                            child: Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.blueText : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
