import 'package:flutter/material.dart';
import 'package:runquest/features/course/models/route_plan.dart';
import 'package:runquest/features/course/widgets/route_cards.dart';
import 'package:runquest/features/profile/widgets/quick_stats.dart';
import 'package:runquest/shared/widgets/page_layout.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.plan, required this.onCourseTap, super.key});

  final RoutePlan plan;
  final VoidCallback onCourseTap;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: 'RunQuest', subtitle: '오늘에 맞는 러닝 코스'),
          const SizedBox(height: 10),
          Text(
            '오늘은\n어디로 달릴까요?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 8,
            child: RouteCard(plan: plan, onCourseTap: onCourseTap),
          ),
          const SizedBox(height: 10),
          Expanded(flex: 4, child: QuickStats()),
        ],
      ),
    );
  }
}
