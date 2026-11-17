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
