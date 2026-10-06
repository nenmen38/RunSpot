import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:runquest/features/admin/admin_screen.dart';
import 'package:runquest/features/admin/models/review_case.dart';
import 'package:runquest/features/home/data/live_runner_service.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/profile/profile_screen.dart';
import 'package:runquest/features/social/social_screen.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RunQuestShell extends StatefulWidget {
  const RunQuestShell({this.mapController, this.mapTileProvider, super.key});

  final LiveMapController? mapController;
  final TileProvider? mapTileProvider;

  @override
  State<RunQuestShell> createState() => _RunQuestShellState();
}

class _RunQuestShellState extends State<RunQuestShell> {
  int _tab = 0;
  late final LiveMapController _map;
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
    _map =
        widget.mapController ??
        LiveMapController(
          locationService: DeviceLocationService(),
          runnerService: SupabaseLiveRunnerService(Supabase.instance.client),
        );
  }

  @override
  void dispose() {
    _map.dispose();
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
      SocialScreen(
        rankingMode: _rankingMode,
        onModeChanged: (value) => setState(() => _rankingMode = value),
      ),
      const ProfileScreen(),
      AdminScreen(review: _review, onAction: _setReviewStatus),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Offstage(
              offstage: _tab != 0,
              child: HomeScreen(
                controller: _map,
                tileProvider: widget.mapTileProvider,
                onProfileTap: () => setState(() => _tab = 2),
              ),
            ),
            if (_tab != 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: pages[_tab - 1],
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        selectedIndex: _tab,
        indicatorColor: AppColors.blueSoft,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '홈',
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
