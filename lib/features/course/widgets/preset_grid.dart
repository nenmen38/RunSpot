import 'package:flutter/material.dart';
import 'package:runquest/features/course/data/presets.dart';
import 'package:runquest/features/course/models/run_preset.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class PresetGrid extends StatelessWidget {
  const PresetGrid({required this.onPresetTap, super.key});

  final ValueChanged<RunPreset> onPresetTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (final preset in presets.take(3)) ...[
                Expanded(
                  child: PresetTile(
                    preset: preset,
                    onTap: () => onPresetTap(preset),
                  ),
                ),
                if (preset != presets[2]) const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: Row(
            children: [
              for (final preset in presets.skip(3)) ...[
                Expanded(
                  child: PresetTile(
                    preset: preset,
                    onTap: () => onPresetTap(preset),
                  ),
                ),
                if (preset != presets.last) const SizedBox(width: 7),
              ],
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}

class PresetTile extends StatelessWidget {
  const PresetTile({required this.preset, required this.onTap, super.key});

  final RunPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(preset.icon, color: preset.color, size: 20),
            const SizedBox(height: 4),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            Text(
              preset.short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.gray,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
