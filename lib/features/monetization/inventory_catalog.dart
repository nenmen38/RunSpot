import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../run_history/run_history_controller.dart';
import 'coin_frames.dart';
import 'cosmetic_shop.dart';
import 'cosmetics.dart';
import 'share_card_shop.dart';
import 'shop_catalog.dart';

/// 내 보관함입니다. 상점과 같은 분류 칩(캐릭터·지도·칭호/채팅·공유 카드·크루)으로 나눠
/// 고른 분류의 가진 아이템만 보여 줍니다. 분류는 [category]로 부모가 정합니다.
class InventoryCatalog extends StatefulWidget {
  const InventoryCatalog({
    required this.wallet,
    required this.category,
    required this.onCategory,
    required this.onShop,
    required this.onMessage,
    this.history,
    this.onUseCrewTicket,
    this.hasLegacyItems = false,
    super.key,
  });

  final WalletController wallet;

  /// 고른 분류입니다. null이면 가진 아이템이 있는 첫 분류(없으면 캐릭터)를 보여 줍니다.
  final ShopCategory? category;
  final ValueChanged<ShopCategory> onCategory;

  /// 비어 있는 분류의 '상점 보기': 상점의 같은 분류를 엽니다.
  final ValueChanged<ShopCategory> onShop;
  final ValueChanged<String> onMessage;
  final RunHistoryController? history;
  final VoidCallback? onUseCrewTicket;

  /// 예전 프로필 꾸미기 아이템이 있는지입니다. 그 목록은 칭호·채팅 분류 아래에 보관함이 붙입니다.
  final bool hasLegacyItems;

  @override
  State<InventoryCatalog> createState() => _InventoryCatalogState();
}

class _InventoryCatalogState extends State<InventoryCatalog> {
  CharacterShopGroup _group = CharacterShopGroup.hair;

  /// 이 분류에 가진 아이템이 하나라도 있는지입니다.
  bool _has(Wallet wallet, ShopCategory category) => switch (category) {
    ShopCategory.character => wallet.cosmetics.any(
      (item) => item.slot.isCharacter,
    ),
    ShopCategory.map =>
      wallet.owned.isNotEmpty ||
          wallet.cosmetics.any((item) => item.slot == CosmeticSlot.route),
    ShopCategory.profile =>
      widget.hasLegacyItems ||
          wallet.cosmetics.any(
            (item) =>
                item.slot == CosmeticSlot.titleStyle ||
                item.slot == CosmeticSlot.chatBubble,
          ),
    ShopCategory.shareCard => wallet.cosmetics.any(
      (item) => item.slot == CosmeticSlot.shareCard,
    ),
    ShopCategory.crew => wallet.crewTickets > 0,
  };

  Widget _empty(BuildContext context, ShopCategory category) => Container(
    key: ValueKey('inventory-empty-${category.name}'),
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.blueSoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(switch (category) {
            ShopCategory.character => '아직 산 캐릭터 아이템이 없어요.',
            ShopCategory.map => '아직 테두리나 경로 색이 없어요.',
            ShopCategory.profile => '아직 칭호 모양이나 말풍선이 없어요.',
            ShopCategory.shareCard => '아직 공유 카드가 없어요.',
            ShopCategory.crew => '쓰지 않은 크루 생성권이 없어요.',
          }),
        ),
        TextButton(
          onPressed: () => widget.onShop(category),
          child: const Text('상점 보기'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.wallet,
    builder: (context, _) {
      final wallet = widget.wallet.wallet;
      final category =
          widget.category ??
          (wallet == null
              ? ShopCategory.character
              : ShopCategory.values
                        .where((value) => _has(wallet, value))
                        .firstOrNull ??
                    ShopCategory.character);
      final text = Theme.of(context).textTheme;
      Widget body;
      if (wallet == null) {
        // 아직 못 불러왔으면 테두리 칸이 불러오기·다시 시도를 보여 줍니다.
        body = FrameInventory(
          controller: widget.wallet,
          onShop: () => widget.onShop(ShopCategory.map),
          onMessage: widget.onMessage,
          showCrewTicket: false,
        );
      } else if (!_has(wallet, category)) {
        body = _empty(context, category);
      } else {
        body = switch (category) {
          ShopCategory.character => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                '여기서 바로 입고 벗을 수 있어요. 프로필 카드의 옷걸이 버튼으로 입은 모습을 보며 고를 수도 있어요.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              CategoryChipRow(
                keyPrefix: 'inventory-group',
                values: CharacterShopGroup.values,
                selected: _group,
                label: (group) => group.label,
                code: (group) => group.name,
                dense: true,
                onSelected: (group) => setState(() => _group = group),
              ),
              if (wallet.cosmetics.any(
                (item) => _group.slots.contains(item.slot),
              ))
                CosmeticInventory(
                  key: ValueKey('inventory-character-${_group.name}'),
                  controller: widget.wallet,
                  onMessage: widget.onMessage,
                  slots: _group.slots,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_group.label} 아이템이 아직 없어요.',
                          style: text.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onShop(category),
                        child: const Text('상점 보기'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          ShopCategory.map => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              FrameInventory(
                controller: widget.wallet,
                onShop: () => widget.onShop(ShopCategory.map),
                onMessage: widget.onMessage,
                showCrewTicket: false,
              ),
              CosmeticInventory(
                controller: widget.wallet,
                onMessage: widget.onMessage,
                slots: const [CosmeticSlot.route],
              ),
            ],
          ),
          ShopCategory.profile => CosmeticInventory(
            controller: widget.wallet,
            onMessage: widget.onMessage,
            slots: const [CosmeticSlot.titleStyle, CosmeticSlot.chatBubble],
          ),
          ShopCategory.shareCard => ShareCardShop(
            wallet: widget.wallet,
            history: widget.history,
            onMessage: widget.onMessage,
            ownedOnly: true,
          ),
          ShopCategory.crew => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              FrameInventory(
                controller: widget.wallet,
                onShop: () => widget.onShop(ShopCategory.crew),
                onMessage: widget.onMessage,
                onUseCrewTicket: widget.onUseCrewTicket,
                showFrames: false,
              ),
            ],
          ),
        };
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryChipRow(
            keyPrefix: 'inventory-category',
            values: ShopCategory.values,
            selected: category,
            label: (value) => value.label,
            code: (value) => value.name,
            icon: (value) => value.icon,
            onSelected: widget.onCategory,
          ),
          body,
          const SizedBox(height: 12),
        ],
      );
    },
  );
}
