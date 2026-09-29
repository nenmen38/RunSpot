import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
