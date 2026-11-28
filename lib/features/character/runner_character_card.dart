import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../monetization/coin_frames.dart';
import '../monetization/cosmetics.dart';
import 'character_background.dart';
import 'character_outfit.dart';
import 'runner_character.dart';
import 'runner_character_directory.dart';

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
  const RunnerCharacterCard({
    this.wallet,
    this.onShare,
    this.showActions = false,
    super.key,
  });

  final WalletController? wallet;

  /// 켜면 캐릭터 그림 오른쪽 위에 반투명 '꾸미기'(옷걸이)·'배경 사진' 버튼을 띄웁니다.
  final bool showActions;

  /// 있으면 캐릭터 아래에 '프로필 카드 공유' 버튼을 보여 줍니다.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final controller = wallet;
    if (controller == null) {
      return _CharacterView(
        worn: const {},
        onShare: onShare,
        showActions: showActions,
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _CharacterView(
        worn: wornCharacterItems(controller.wallet),
        onShare: onShare,
        wallet: controller,
        showActions: showActions,
      ),
    );
  }
}

class _CharacterView extends StatelessWidget {
  const _CharacterView({
    required this.worn,
    this.onShare,
    this.wallet,
    this.showActions = false,
  });

  final Map<CosmeticSlot, CosmeticItem> worn;
  final VoidCallback? onShare;
  final WalletController? wallet;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ListenableBuilder(
                listenable: CharacterBackground.instance,
                builder: (context, _) => RunnerCharacterStage(
                  outfit: characterOutfit(worn.values),
                  height: 280,
                  background: CharacterBackground.instance.provider,
                ),
              ),
            ),
            // 그림 위 오른쪽 위에 반투명 버튼: 꾸미기(옷걸이)와 배경 사진.
            if (showActions)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (wallet case final wallet?) ...[
                      CharacterDressButton(wallet: wallet),
                      const SizedBox(width: 6),
                    ],
                    const CharacterBackgroundButton(),
                  ],
                ),
              ),
          ],
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
        if (onShare case final share?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('share-character-card'),
              onPressed: share,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('프로필 카드 공유'),
            ),
          ),
      ],
    );
  }
}

/// 캐릭터 그림 위에 띄우는 반투명 원형 아이콘 버튼 모양입니다(어떤 배경 사진 위에서도 보이도록).
final characterOverlayButtonStyle = IconButton.styleFrom(
  backgroundColor: Colors.black.withValues(alpha: 0.32),
  foregroundColor: Colors.white,
  hoverColor: Colors.white.withValues(alpha: 0.12),
  highlightColor: Colors.white.withValues(alpha: 0.2),
  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
);

/// 프로필 카드 그림 위의 반투명 '꾸미기'(옷걸이) 버튼입니다. 누르면 카테고리별 꾸미기 창이 열립니다.
class CharacterDressButton extends StatelessWidget {
  const CharacterDressButton({required this.wallet, super.key});

  final WalletController wallet;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('character-dress-button'),
    tooltip: '꾸미기',
    style: characterOverlayButtonStyle,
    onPressed: () => showCharacterDresser(context, wallet),
    icon: const Icon(Icons.checkroom, size: 20),
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
    if (message == null) RunnerCharacterDirectory.instance.invalidate();
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
                      child: ListenableBuilder(
                        listenable: CharacterBackground.instance,
                        builder: (context, _) => RunnerCharacterStage(
                          outfit: characterOutfit(worn.values),
                          height: compact ? 170 : 220,
                          background: CharacterBackground.instance.provider,
                        ),
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
