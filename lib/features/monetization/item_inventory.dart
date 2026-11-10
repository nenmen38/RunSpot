import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'store_catalog.dart';

/// 보관함의 아이템 한 개입니다.
class InventoryItem {
  const InventoryItem(this.item, {required this.equipped});

  final Cosmetic item;
  final bool equipped;
}

/// 가진 꾸미기 아이템을 착용하거나 해제합니다. 해제는 착용 중일 때만 누를 수 있습니다.
class ItemInventory extends StatelessWidget {
  const ItemInventory({
    required this.items,
    required this.onChanged,
    this.busy = false,
    this.message,
    this.header,
    super.key,
  });

  final List<InventoryItem> items;
  final void Function(Cosmetic item, bool equip) onChanged;
  final bool busy;
  final String? message;

  /// 꾸미기 아이템 위에 보여줄 영역입니다. 코인으로 산 테두리를 넣습니다.
  final Widget? header;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 16),
    children: [
      ?header,
      if (busy) const LinearProgressIndicator(),
      if (message case final feedback?)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(feedback),
        ),
      if (items.isEmpty && header == null)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Text('보관함이 비어 있어요.', textAlign: TextAlign.center),
        ),
      for (final entry in items) ...[
        _InventoryTile(
          entry: entry,
          busy: busy,
          onChanged: (equip) => onChanged(entry.item, equip),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.entry,
    required this.busy,
    required this.onChanged,
  });

  final InventoryItem entry;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = entry.item;
    return Material(
      key: ValueKey('inventory-${item.id}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: entry.equipped ? AppColors.blue : AppColors.line,
          width: entry.equipped ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(child: CosmeticArtwork(item: item)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Badge(item.category),
                    if (entry.equipped) const _Badge('착용 중', highlighted: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(item.description, style: text.bodySmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: busy || entry.equipped
                            ? null
                            : () => onChanged(true),
                        child: const Text('착용'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // 해제는 착용 중일 때만 누를 수 있습니다.
                      child: OutlinedButton(
                        onPressed: busy || !entry.equipped
                            ? null
                            : () => onChanged(false),
                        child: const Text('해제'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: highlighted ? AppColors.blue : AppColors.blueSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: highlighted ? Colors.white : AppColors.blueDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
