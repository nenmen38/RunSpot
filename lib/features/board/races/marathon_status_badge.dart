import 'package:flutter/material.dart';

import '../widgets/board_theme.dart';
import 'marathon_event.dart';

class MarathonStatusBadge extends StatelessWidget {
  const MarathonStatusBadge({required this.status, super.key});
  final MarathonStatus status;

  @override
  Widget build(BuildContext context) =>
      BoardLabel(text: status.label, emphasized: status == MarathonStatus.open);
}
