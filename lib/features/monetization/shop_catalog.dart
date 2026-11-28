import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../crew/crew_controller.dart';
import '../run_history/run_history_controller.dart';
import 'coin_frames.dart';
import 'cosmetic_shop.dart';
import 'cosmetics.dart';
import 'share_card_shop.dart';

/// 상점의 큰 분류입니다. 위의 칩을 눌러 한 분류씩만 보여 줘서 길게 스크롤하지 않아도 됩니다.
enum ShopCategory {
  character('캐릭터', Icons.accessibility_new),
  map('지도', Icons.map_outlined),
  profile('칭호·채팅', Icons.badge_outlined),
  shareCard('공유 카드', Icons.image_outlined),
  crew('크루', Icons.groups_outlined);

  const ShopCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 캐릭터 분류 안의 작은 묶음입니다. 칸이 11개라 비슷한 것끼리 묶어 한 화면에 들어오게 합니다.
enum CharacterShopGroup {
  hair('헤어스타일', [CosmeticSlot.charHair]),
  colorFace('머리색·표정', [CosmeticSlot.charHairColor, CosmeticSlot.charFace]),
  accessory('모자·선글라스', [CosmeticSlot.charHead, CosmeticSlot.charEyes]),
  clothes('옷', [
    CosmeticSlot.charTop,
    CosmeticSlot.charBottom,
    CosmeticSlot.charSleeves,
    CosmeticSlot.charSeason,
  ]),
  shoes('운동화', [CosmeticSlot.charShoes]),
  pet('반려동물', [CosmeticSlot.charPet]);

  const CharacterShopGroup(this.label, this.slots);
  final String label;
  final List<CosmeticSlot> slots;
}

/// 상점 목록입니다. 위에 분류 칩(캐릭터·지도·칭호/채팅·공유 카드·크루)을 두고 고른 분류만 보여 줍니다.
class ShopCatalog extends StatefulWidget {
  const ShopCatalog({
    required this.wallet,
    required this.onMessage,
    this.history,
    this.crew,
    this.initialCategory = ShopCategory.character,
    super.key,
  });

  /// 처음 보여 줄 분류입니다. 바뀌면(예: 보관함의 '상점 보기') 그 분류로 옮겨 갑니다.
  final ShopCategory initialCategory;

  final WalletController wallet;
  final ValueChanged<String> onMessage;
  final RunHistoryController? history;
  final CrewController? crew;

  @override
  State<ShopCatalog> createState() => _ShopCatalogState();
}

class _ShopCatalogState extends State<ShopCatalog> {
  late ShopCategory _category = widget.initialCategory;
  CharacterShopGroup _group = CharacterShopGroup.hair;

  @override
  void didUpdateWidget(ShopCatalog old) {
    super.didUpdateWidget(old);
    if (old.initialCategory != widget.initialCategory) {
      _category = widget.initialCategory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = switch (_category) {
      ShopCategory.character => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            '산 아이템은 프로필 카드의 옷걸이 버튼에서 바로 입혀 볼 수 있어요. 눈 모양을 눌러 미리 돌려 보세요.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          CategoryChipRow(
            keyPrefix: 'shop-group',
            values: CharacterShopGroup.values,
            selected: _group,
            label: (group) => group.label,
            code: (group) => group.name,
            dense: true,
            onSelected: (group) => setState(() => _group = group),
          ),
          CosmeticShop(
            key: ValueKey('shop-character-${_group.name}'),
            controller: widget.wallet,
            onMessage: widget.onMessage,
            slots: _group.slots,
          ),
        ],
      ),
      ShopCategory.map => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FrameShop(
            controller: widget.wallet,
            onMessage: widget.onMessage,
            showCrewTicket: false,
          ),
          CosmeticShop(
            controller: widget.wallet,
            onMessage: widget.onMessage,
            slots: const [CosmeticSlot.route],
          ),
        ],
      ),
      ShopCategory.profile => CosmeticShop(
        controller: widget.wallet,
        onMessage: widget.onMessage,
        slots: const [CosmeticSlot.titleStyle, CosmeticSlot.chatBubble],
      ),
      ShopCategory.shareCard => ShareCardShop(
        wallet: widget.wallet,
        history: widget.history,
        onMessage: widget.onMessage,
      ),
      ShopCategory.crew => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FrameShop(
            controller: widget.wallet,
            onMessage: widget.onMessage,
            showFrames: false,
          ),
          if (widget.crew case final crew?)
            CrewExpansionShop(
              controller: widget.wallet,
              crew: crew,
              onMessage: widget.onMessage,
            ),
        ],
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryChipRow(
          keyPrefix: 'shop-category',
          values: ShopCategory.values,
          selected: _category,
          label: (category) => category.label,
          code: (category) => category.name,
          icon: (category) => category.icon,
          onSelected: (category) => setState(() => _category = category),
        ),
        body,
      ],
    );
  }
}

/// 옆으로 밀리는 선택 칩 한 줄입니다(상점·보관함의 분류).
class CategoryChipRow<T> extends StatelessWidget {
  const CategoryChipRow({
    super.key,
    required this.keyPrefix,
    required this.values,
    required this.selected,
    required this.label,
    required this.code,
    required this.onSelected,
    this.icon,
    this.dense = false,
  });

  final String keyPrefix;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final String Function(T) code;
  final IconData Function(T)? icon;
  final ValueChanged<T> onSelected;
  final bool dense;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        for (final value in values) ...[
          ChoiceChip(
            key: ValueKey('$keyPrefix-${code(value)}'),
            selected: value == selected,
            showCheckmark: false,
            visualDensity: dense ? VisualDensity.compact : null,
            avatar: switch (icon) {
              final icon? => Icon(
                icon(value),
                size: 18,
                color: value == selected ? AppColors.blueText : null,
              ),
              null => null,
            },
            label: Text(
              label(value),
              style: TextStyle(
                fontWeight: value == selected
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
            onSelected: (_) => onSelected(value),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}
