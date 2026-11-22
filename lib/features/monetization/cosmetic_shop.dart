import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../crew/crew_controller.dart';
import '../titles/badge_directory.dart';
import 'coin_frames.dart';
import 'cosmetics.dart';

/// 아이템 미리보기입니다. 칭호 모양은 배지로, 나머지는 색 동그라미로 보여줍니다.
class CosmeticPreview extends StatelessWidget {
  const CosmeticPreview({required this.item, this.size = 44, super.key});

  final CosmeticItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (item.slot == CosmeticSlot.titleStyle) {
      return SizedBox(
        width: size * 2,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: TitleBadge(title: RunnerTitle.tenK, style: item),
        ),
      );
    }
    final colors = item.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.length == 1 ? colors.first : null,
        gradient: colors.length > 1
            ? SweepGradient(colors: [...colors, colors.first])
            : null,
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Icon(
        switch (item.slot) {
          CosmeticSlot.route => Icons.route,
          CosmeticSlot.chatBubble => Icons.chat_bubble,
          CosmeticSlot.titleStyle => Icons.badge,
        },
        size: size * .45,
        color: Colors.white,
      ),
    );
  }
}

/// 상점의 꾸미기 아이템 목록입니다. 칸(경로 색·칭호 모양·오라 효과·말풍선)별로 묶습니다.
class CosmeticShop extends StatelessWidget {
  const CosmeticShop({
    required this.controller,
    required this.onCharge,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final VoidCallback onCharge;
  final ValueChanged<String> onMessage;

  Future<void> _buy(BuildContext context, CosmeticItem item) async {
    final wallet = controller.wallet;
    if (wallet == null) return;
    if (wallet.coins < item.defaultPrice) {
      onCharge();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.slot.label} · ${item.label}를 살까요?'),
        content: Text(
          '${formatNumber(item.defaultPrice)}코인을 써요. 산 아이템은 보관함에서 착용할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('구매'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (await controller.buyCosmetic(item) case final message?) {
      onMessage(message);
    } else {
      onMessage('${item.label}를 샀어요. 보관함에서 착용해 보세요.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = controller.wallet;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final slot in CosmeticSlot.values) ...[
            const SizedBox(height: 20),
            Text(
              slot.label,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(slot.description, style: text.bodySmall),
            const SizedBox(height: 10),
            for (final item in CosmeticItem.values.where((i) => i.slot == slot))
              _ItemRow(
                key: ValueKey('shop-${item.code}'),
                item: item,
                trailing: wallet?.cosmetics.contains(item) == true
                    ? const OutlinedButton(onPressed: null, child: Text('보유 중'))
                    : FilledButton(
                        onPressed: wallet == null || controller.busy
                            ? null
                            : () => _buy(context, item),
                        child: Text(
                          (wallet?.coins ?? 0) < item.defaultPrice
                              ? '코인 충전'
                              : '구매',
                        ),
                      ),
                subtitle: '${formatNumber(item.defaultPrice)}코인',
              ),
          ],
        ],
      );
    },
  );
}

/// 보관함의 내 꾸미기 아이템입니다. 칸마다 하나만 착용하고, 해제는 착용 중일 때만 됩니다.
class CosmeticInventory extends StatelessWidget {
  const CosmeticInventory({
    required this.controller,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = controller.wallet;
      if (wallet == null || wallet.cosmetics.isEmpty) {
        return const SizedBox.shrink();
      }
      Future<void> run(Future<String?> action) async {
        if (await action case final message?) {
          onMessage(message);
        } else {
          // 칭호 모양·말풍선은 다른 화면에서도 바로 바뀌게 합니다.
          BadgeDirectory.instance.refreshAll();
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final slot in CosmeticSlot.values)
            if (wallet.cosmetics.any((item) => item.slot == slot)) ...[
              const SizedBox(height: 20),
              Text(
                '내 ${slot.label}',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final item in CosmeticItem.values.where(
                (i) => i.slot == slot && wallet.cosmetics.contains(i),
              ))
                _ItemRow(
                  key: ValueKey('inventory-${item.code}'),
                  item: item,
                  subtitle: wallet.equippedCosmetics[slot] == item
                      ? '착용 중'
                      : null,
                  trailing: wallet.equippedCosmetics[slot] == item
                      ? OutlinedButton(
                          onPressed: controller.busy
                              ? null
                              : () => run(controller.equipCosmetic(slot, null)),
                          child: const Text('해제'),
                        )
                      : FilledButton(
                          onPressed: controller.busy
                              ? null
                              : () => run(controller.equipCosmetic(slot, item)),
                          child: const Text('착용'),
                        ),
                ),
            ],
        ],
      );
    },
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.trailing,
    this.subtitle,
    super.key,
  });

  final CosmeticItem item;
  final Widget trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        CosmeticPreview(item: item),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (subtitle case final value?)
                Text(
                  value,
                  style: TextStyle(color: AppColors.blueText, fontSize: 12),
                ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

/// 크루 정원 확장권입니다. 내가 크루장인 크루마다 한 번, 30명에서 50명으로 늘립니다.
class CrewExpansionShop extends StatelessWidget {
  const CrewExpansionShop({
    required this.controller,
    required this.crew,
    required this.onCharge,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final CrewController crew;
  final VoidCallback onCharge;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, crew]),
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = controller.wallet;
      final price = wallet?.crewExpansionPrice ?? 1000;
      final mine = crew.crews.where((c) => c.isOwner).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            '크루 정원 확장권',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            '크루 정원을 30명에서 50명으로 늘려요. 크루마다 한 번 · ${formatNumber(price)}코인',
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),
          if (mine.isEmpty)
            Text('내가 크루장인 크루가 있으면 살 수 있어요.', style: text.bodySmall)
          else
            for (final item in mine)
              Container(
                key: ValueKey('expand-${item.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Icon(item.icon.icon, color: item.icon.color, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${item.members.length}/${item.sizeLimit}명',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (item.expanded)
                      const OutlinedButton(onPressed: null, child: Text('확장됨'))
                    else
                      FilledButton(
                        onPressed: wallet == null || controller.busy
                            ? null
                            : () async {
                                if (wallet.coins < price) {
                                  onCharge();
                                  return;
                                }
                                final message = await controller.expandCrew(
                                  item.id,
                                );
                                if (message != null) {
                                  onMessage(message);
                                  return;
                                }
                                await crew.refresh();
                                onMessage('${item.name} 정원을 50명으로 늘렸어요.');
                              },
                        child: Text(
                          (wallet?.coins ?? 0) < price ? '코인 충전' : '정원 늘리기',
                        ),
                      ),
                  ],
                ),
              ),
        ],
      );
    },
  );
}
