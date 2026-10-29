import 'package:flutter/material.dart';

import 'board_theme.dart';

/// 게시판 종류와 무관하게 같은 위치·동작으로 조건을 선택합니다.
class BoardFilterMenu<T> extends StatelessWidget {
  const BoardFilterMenu({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    required this.tooltip,
    super.key,
  });
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: tooltip,
    initialValue: selected == null ? 0 : values.indexOf(selected as T) + 1,
    onSelected: (index) => onChanged(index == 0 ? null : values[index - 1]),
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    itemBuilder: (_) => [
      for (var index = 0; index <= values.length; index++)
        PopupMenuItem<int>(
          value: index,
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  index == 0 ? '전체' : labelOf(values[index - 1]),
                  style: BoardStyle.body,
                ),
              ),
              if ((index == 0 && selected == null) ||
                  (index > 0 && values[index - 1] == selected))
                const Icon(Icons.check, color: BoardStyle.accent, size: 20),
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
          color: BoardStyle.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected == null ? '전체' : labelOf(selected as T),
              style: const TextStyle(
                color: BoardStyle.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.expand_more,
              size: 20,
              color: BoardStyle.secondary,
            ),
          ],
        ),
      ),
    ),
  );
}
