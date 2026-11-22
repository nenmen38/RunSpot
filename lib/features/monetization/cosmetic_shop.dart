import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../chat/chat_room_style.dart';
import '../crew/crew_controller.dart';
import '../titles/badge_directory.dart';
import 'coin_frames.dart';
import 'cosmetics.dart';
import 'shop_item_actions.dart';

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
          CosmeticSlot.shareCard => Icons.image_outlined,
        },
        size: size * .45,
        color: Colors.white,
      ),
    );
  }
}

Future<void> _showCosmeticPreview(BuildContext context, CosmeticItem item) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.slot.label} · ${item.label}'),
        content: switch (item.slot) {
          CosmeticSlot.route => SizedBox(
            width: 240,
            height: 112,
            child: CustomPaint(painter: _RouteExample(item)),
          ),
          CosmeticSlot.chatBubble => SizedBox(
            width: 240,
            child: ChatMessageBubble(
              body: '오늘 같이 달릴래요?',
              nickname: '러너',
              mine: true,
              showAvatar: false,
              showTime: false,
              sentAt: null,
              showDay: false,
              bubble: item,
            ),
          ),
          CosmeticSlot.titleStyle => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('러너'),
              const SizedBox(width: 8),
              Flexible(
                child: TitleBadge(title: RunnerTitle.tenK, style: item),
              ),
            ],
          ),
          CosmeticSlot.shareCard => CosmeticPreview(item: item),
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );

class _RouteExample extends CustomPainter {
  const _RouteExample(this.item);

  final CosmeticItem item;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset(size.width * .08, size.height * .76),
      Offset(size.width * .24, size.height * .62),
      Offset(size.width * .38, size.height * .28),
      Offset(size.width * .59, size.height * .37),
      Offset(size.width * .73, size.height * .70),
      Offset(size.width * .92, size.height * .51),
    ];
    final route = skinRoute([points], item, chunk: 1);
    for (final (index, segment) in route.segments.indexed) {
      final color = Color(
        0xff000000 | int.parse(route.colors![index].substring(1), radix: 16),
      );
      canvas.drawPoints(
        PointMode.polygon,
        segment,
        Paint()
          ..color = color
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RouteExample oldDelegate) => oldDelegate.item != item;
}

/// 상점의 꾸미기 아이템 목록입니다. 칸(경로 색·칭호 모양·오라 효과·말풍선)별로 묶습니다.
class CosmeticShop extends StatelessWidget {
  const CosmeticShop({
    required this.controller,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final ValueChanged<String> onMessage;

  Future<void> _buy(BuildContext context, CosmeticItem item) async {
    final wallet = controller.wallet;
    if (wallet == null) return;
    final price = wallet.priceOf(item);
    if (!await checkCoinBalance(context, wallet, price) || !context.mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.slot.label} · ${item.label}를 살까요?'),
        content: Text('${formatNumber(price)}코인을 써요. 산 아이템은 보관함에서 착용할 수 있어요.'),
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
    if (await controller.buyCosmetic(
          item,
          expectedPrice: wallet.hasServerCosmeticPrices ? price : null,
        )
        case final message?) {
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
          for (final slot in CosmeticSlot.values.where(
            (slot) => slot != CosmeticSlot.shareCard,
          )) ...[
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
                        child: const Text('구매'),
                      ),
                subtitle:
                    '${formatNumber(wallet?.priceOf(item) ?? item.defaultPrice)}코인',
                onPreview: () => _showCosmeticPreview(context, item),
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
          for (final slot in CosmeticSlot.values.where(
            (slot) => slot != CosmeticSlot.shareCard,
          ))
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
    this.onPreview,
    super.key,
  });

  final CosmeticItem item;
  final Widget trailing;
  final String? subtitle;
  final VoidCallback? onPreview;

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
        CosmeticPreview(
          item: item,
          size: onPreview != null && item.slot == CosmeticSlot.titleStyle
              ? 32
              : 44,
        ),
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
        if (onPreview case final preview?) ...[
          const SizedBox(width: 8),
          ShopItemActions(onPreview: preview, purchase: trailing),
        ] else
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
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final CrewController crew;
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
                                if (!await checkCoinBalance(
                                      context,
                                      wallet,
                                      price,
                                    ) ||
                                    !context.mounted) {
                                  return;
                                }
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('크루 정원을 늘릴까요?'),
                                    content: Text(
                                      '${formatNumber(price)}코인을 사용해 ${item.name}의 정원을 ${item.sizeLimit}명에서 50명으로 늘려요.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('취소'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('구매'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !context.mounted)
                                  return;
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
                        child: const Text('구매'),
                      ),
                  ],
                ),
              ),
        ],
      );
    },
  );
}
