import 'package:flutter/material.dart';
import 'package:runquest/features/admin/admin_screen.dart';
import 'package:runquest/features/admin/models/review_case.dart';
import 'package:runquest/features/course/course_screen.dart';
import 'package:runquest/features/course/course_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/profile/profile_screen.dart';
import 'package:runquest/features/social/social_screen.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class RunQuestShell extends StatefulWidget {
  const RunQuestShell({super.key});

  @override
  State<RunQuestShell> createState() => _RunQuestShellState();
}

class _RunQuestShellState extends State<RunQuestShell> {
  int _tab = 0;
  final _course = CourseController();
  int _rankingMode = 0;
  ReviewCase _review = const ReviewCase(
    user: 'speed_ghost',
    reason: '순간 속도 34.2km/h 감지',
    summary: '10.02km · 22:18 · 페이스 변동 1.2%',
    risk: 92,
    status: '검토 필요',
  );

  @override
  void initState() {
    super.initState();
    _course.addListener(_onCourseChanged);
  }

  void _onCourseChanged() => setState(() {});

  @override
  void dispose() {
    _course.removeListener(_onCourseChanged);
    _course.dispose();
    super.dispose();
  }

  void _setReviewStatus(String status) {
    setState(() => _review = _review.copyWith(status: status));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_review.user}님에게 "$status" 알림을 보냈습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        plan: _course.plan,
        onCourseTap: () => setState(() => _tab = 1),
      ),
      CourseScreen(
        plan: _course.plan,
        distance: _course.distance,
        slope: _course.slope,
        flow: _course.flow,
        environment: _course.environment,
        safety: _course.safety,
        onDistance: (value) => _course.updatePlan(distance: value),
        onSlope: (value) => _course.updatePlan(slope: value),
        onFlow: (value) => _course.updatePlan(flow: value),
        onEnvironment: (value) => _course.updatePlan(environment: value),
        onSafety: (value) => _course.updatePlan(safety: value),
        onPresetTap: _course.applyPreset,
      ),
      SocialScreen(
        rankingMode: _rankingMode,
        onModeChanged: (value) => setState(() => _rankingMode = value),
      ),
      const ProfileScreen(),
      AdminScreen(review: _review, onAction: _setReviewStatus),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: pages[_tab],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        selectedIndex: _tab,
        indicatorColor: AppColors.blueSoft,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: '코스',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '소셜',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '프로필',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: '관리',
          ),
        ],
      ),
    );
  }
}
