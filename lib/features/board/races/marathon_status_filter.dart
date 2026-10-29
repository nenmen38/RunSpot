import 'package:flutter/material.dart';

import '../widgets/board_filter_menu.dart';
import 'marathon_event.dart';

class MarathonStatusFilter extends StatelessWidget {
  const MarathonStatusFilter({
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final MarathonStatus? selected;
  final ValueChanged<MarathonStatus?> onChanged;

  @override
  Widget build(BuildContext context) => BoardFilterMenu<MarathonStatus>(
    values: MarathonStatus.values,
    selected: selected,
    labelOf: (status) => status.label,
    onChanged: onChanged,
    tooltip: '접수 상태 선택',
  );
}
