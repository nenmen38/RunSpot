import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class ChoiceMenu extends StatelessWidget {
  const ChoiceMenu({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: '$label 선택',
              onSelected: onChanged,
              itemBuilder: (context) => [
                for (final option in options)
                  PopupMenuItem(value: option, child: Text(option)),
              ],
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.gray,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
