import 'package:flutter/material.dart';

class ShopItemActions extends StatelessWidget {
  const ShopItemActions({required this.onPreview, this.purchase, super.key});

  final VoidCallback onPreview;
  final Widget? purchase;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: onPreview,
        tooltip: '미리보기',
        icon: const Icon(Icons.visibility_outlined, size: 20),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      if (purchase case final button?) button,
    ],
  );
}
