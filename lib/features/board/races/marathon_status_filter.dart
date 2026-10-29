import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import 'marathon_event.dart';
import 'marathon_style.dart';

/// 가로로 숨겨진 선택지 없이 모든 접수 상태를 한 메뉴에서 고릅니다.
class MarathonStatusFilter extends StatelessWidget {
  const MarathonStatusFilter({
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final MarathonStatus? selected;
  final ValueChanged<MarathonStatus?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '접수 상태 선택',
    initialValue: selected?.code ?? 'all',
    onSelected: (code) => onChanged(
      code == 'all'
          ? null
          : MarathonStatus.values.firstWhere((s) => s.code == code),
    ),
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    itemBuilder: (_) => [
      for (final status in <MarathonStatus?>[null, ...MarathonStatus.values])
        PopupMenuItem<String>(
          value: status?.code ?? 'all',
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  status?.label ?? '전체',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (status == selected)
                const Icon(Icons.check, size: 20, color: AppColors.blueDark),
            ],
          ),
        ),
    ],
    child: Semantics(
      button: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected?.label ?? '전체',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.expand_more,
              size: 20,
              color: MarathonStyle.secondary,
            ),
          ],
        ),
      ),
    ),
  );
}
