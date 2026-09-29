import 'package:flutter/material.dart';
import 'package:runquest/shared/widgets/stat_card.dart';

class QuickStats extends StatelessWidget {
  const QuickStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: StatCard(
            label: '이번 주',
            value: '31.4km',
            icon: Icons.calendar_month,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(label: '평균 페이스', value: '5′42″', icon: Icons.speed),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '완주 코스',
            value: '18개',
            icon: Icons.route_outlined,
          ),
        ),
      ],
    );
  }
}
