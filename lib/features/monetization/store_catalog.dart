import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';

enum Cosmetic {
  border(
    'blue_profile_border',
    '파란 프로필 테두리',
    '테두리',
    '선명한 파란 테두리로 프로필 카드를 강조합니다.',
  ),
  theme('blue_profile_theme', '파란 프로필 테마', '테마', '프로필 카드 주위에 부드러운 파란빛을 더합니다.');

  const Cosmetic(this.id, this.label, this.category, this.description);
  final String id;
  final String label;
  final String category;
  final String description;
}

Widget decorateProfile(Widget child, Set<Cosmetic> items) {
  if (items.isEmpty) return child;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: items.contains(Cosmetic.border)
          ? Border.all(color: const Color(0xFF2862D7), width: 3)
          : null,
      boxShadow: items.contains(Cosmetic.theme)
          ? const [
              BoxShadow(
                color: Color(0xFFC0D8FF),
                blurRadius: 16,
                spreadRadius: 3,
              ),
            ]
          : null,
    ),
    child: child,
  );
}

/// 아이템 페이지의 상점 목록입니다. 제목과 구매 복원은 페이지 머리에 있습니다.
class StoreCatalog extends StatelessWidget {
  const StoreCatalog({
    required this.items,
    required this.onOpen,
    this.header,
    this.onRestore,
    this.onRetry,
    this.message,
    this.loading = false,
    super.key,
  });

  final Map<Cosmetic, String> items;
  final ValueChanged<Cosmetic> onOpen;

  /// 꾸미기 상품 위에 보여줄 영역입니다. 코인 테두리를 넣습니다.
  final Widget? header;
  final VoidCallback? onRestore;
  final VoidCallback? onRetry;
  final String? message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ?header,
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF12295B), Color(0xFF235CBF)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                color: Color(0xFFC6DEFF),
                size: 23,
              ),
              const SizedBox(height: 16),
              Text(
                '블루 컬렉션',
                style: text.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '테두리와 테마로 내 프로필을 꾸며보세요.',
                style: text.bodyMedium?.copyWith(
                  color: const Color(0xFFE0ECFF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '꾸미기 아이템',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (message case final feedback?) Text(feedback),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        if (!loading && items.isEmpty && message == null)
          const Text('등록된 상품이 없습니다.'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 19
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in items.entries)
                  SizedBox(
                    width: width,
                    child: _ItemTile(
                      item: entry.key,
                      status: entry.value,
                      onTap: () => onOpen(entry.key),
                    ),
                  ),
              ],
            );
          },
        ),
        if (onRestore != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onRestore, child: const Text('구매 복원')),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.status,
    required this.onTap,
  });

  final Cosmetic item;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(child: CosmeticArtwork(item: item)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StoreTag(item.category),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    status,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.blueDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CosmeticArtwork extends StatelessWidget {
  const CosmeticArtwork({required this.item, this.large = false, super.key});

  final Cosmetic item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: large ? 144 : 96),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: large ? 32 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item == Cosmetic.border
              ? const [Color(0xFFEBF4FF), Color(0xFFCDDCFC)]
              : const [Color(0xFFE9F7FF), Color(0xFFE4E5FF)],
        ),
      ),
      child: Center(
        child: decorateProfile(
          Container(
            width: large ? 210 : 108,
            padding: EdgeInsets.all(large ? 14 : 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: large ? 18 : 11,
                  backgroundColor: AppColors.blueSoft,
                  child: Icon(
                    Icons.person_outline,
                    color: AppColors.blueDark,
                    size: large ? 20 : 13,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: large
                      ? const Text(
                          '러너 프로필',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        )
                      : Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.blueSoft,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                ),
              ],
            ),
          ),
          {item},
        ),
      ),
    );
  }
}

class StoreTag extends StatelessWidget {
  const StoreTag(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.blueSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
