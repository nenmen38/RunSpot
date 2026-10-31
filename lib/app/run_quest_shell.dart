import 'dart:async';

import '../features/notifications/data/push_service.dart';

import 'package:flutter/material.dart';

import '../shared/maps/run_map.dart';
import '../features/social/blocked_users_screen.dart';
import '../features/board/board_post_loader_screen.dart';
import '../features/board/board_screen.dart';
import '../features/board/data/board_service.dart';
import '../features/notifications/data/notification_service.dart';
import '../features/notifications/notification_controller.dart';
import '../features/settings/settings_screen.dart';

import 'package:runquest/features/admin/admin_screen.dart';
import 'package:runquest/features/admin/data/review_service.dart';
import 'package:runquest/features/profile/data/achievement_service.dart';
import 'package:runquest/features/group_running/data/group_service.dart';
import 'package:runquest/features/group_running/group_controller.dart';
import 'package:runquest/features/home/data/live_runner_service.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/data/run_checkpoint_store.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/profile/profile_screen.dart';
import 'package:runquest/features/profile/data/statistics_service.dart';
import 'package:runquest/features/profile/data/run_sharing_preference_service.dart';
import 'package:runquest/features/progress/data/progress_service.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/data/run_record_service.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/run_history_screen.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';
import 'package:runquest/features/run_conditions/data/conditions_service.dart';
import 'package:runquest/features/social/data/friend_service.dart';
import 'package:runquest/features/social/data/block_service.dart';
import 'package:runquest/features/social/data/ranking_service.dart';
import 'package:runquest/features/social/social_screen.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RunQuestShell extends StatefulWidget {
  const RunQuestShell({
    this.mapController,
    this.mapBridgeFactory,
    this.friendService,
    this.conditionsController,
    this.progressService,
    this.statisticsService,
    this.rankingService,
    this.boardService,
    super.key,
  });

  final LiveMapController? mapController;
  final MapBridgeFactory? mapBridgeFactory;
  final FriendService? friendService;
  final ConditionsController? conditionsController;
  final ProgressService? progressService;
  final StatisticsService? statisticsService;
  final RankingService? rankingService;
  final BoardService? boardService;

  @override
  State<RunQuestShell> createState() => _RunQuestShellState();
}

class _RunQuestShellState extends State<RunQuestShell> {
  int _tab = 0;
  StreamSubscription<PushDestination>? _pushSubscription;
  StreamSubscription<PushDestination>? _pushMessages;
  int _socialRevision = 0;
  int _socialInitialTab = 0;
  bool _openGroupOnStart = false;
  late final LiveMapController _map;
  ConditionsController? _conditions;
  ProgressService? _progress;
  StatisticsService? _statistics;
  RankingService? _ranking;
  BlockService? _blocks;
  AchievementService? _achievements;
  ReviewService? _reviews;
  GroupController? _groups;
  BoardService? _board;
  NotificationController? _notifications;

  @override
  void initState() {
    super.initState();
    if (widget.mapController != null) {
      _map = widget.mapController!;
      _conditions = widget.conditionsController;
      _progress = widget.progressService;
      _statistics = widget.statisticsService;
      _ranking = widget.rankingService;
      _board = widget.boardService;
    } else {
      final client = Supabase.instance.client;
      _pushSubscription = PushService.instance.destinations.stream.listen(
        _openPush,
      );
      _pushMessages = PushService.instance.messages.stream.listen((
        destination,
      ) {
        _notifications?.refreshCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('새 활동 알림이 도착했어요.'),
              action: SnackBarAction(
                label: '확인',
                onPressed: () {
                  _openPush(destination);
                },
              ),
            ),
          );
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final destination = PushService.instance.pending;
        if (destination != null) _openPush(destination);
      });
      _blocks = SupabaseBlockService(client);
      _achievements = SupabaseAchievementService(client);
      _reviews = SupabaseReviewService(client);
      _conditions =
          widget.conditionsController ??
          ConditionsController(SupabaseConditionsService(client));
      _progress = widget.progressService ?? SupabaseProgressService(client);
      _statistics =
          widget.statisticsService ?? SupabaseStatisticsService(client);
      _ranking = widget.rankingService ?? SupabaseRankingService(client);
      final records = SupabaseRunRecordService(client);
      _map = LiveMapController(
        checkpointStore: SqliteRunCheckpointStore(
          ownerId: records.ownerId,
          namespace: client.rest.url,
        ),
        sharingPreferenceService: SupabaseRunSharingPreferenceService(client),
        locationService: DeviceLocationService(),
        runnerService: SupabaseLiveRunnerService(client),
        runHistory: RunHistoryController(
          records,
          outbox: SqliteRunOutbox(
            ownerId: records.ownerId,
            namespace: client.rest.url,
          ),
        ),
      );
      _groups = GroupController(SupabaseGroupService(client), _map);
      _board = widget.boardService ?? SupabaseBoardService(client);
      _notifications = NotificationController(
        SupabaseNotificationService(client),
      );
    }
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    _pushMessages?.cancel();
    _groups?.dispose();
    _notifications?.dispose();
    if (widget.conditionsController == null) _conditions?.dispose();
    _map.runHistory.dispose();
    _map.dispose();
    super.dispose();
  }

  void _openPush(PushDestination destination) {
    if (!mounted ||
        !_map.runHistory.service.isCurrentOwner ||
        Supabase.instance.client.auth.currentUser?.id !=
            destination.recipientId) {
      return;
    }
    PushService.instance.pending = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (destination.kind == 'board_comment') {
      unawaited(_openPost(destination.targetId));
      return;
    }
    setState(() {
      _socialRevision++;
      _socialInitialTab = destination.kind == 'friend_request' ? 1 : 0;
      _openGroupOnStart = destination.kind == 'group_invite';
      _tab = 1;
    });
  }

  void _openHistory() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RunHistoryScreen(controller: _map.runHistory),
      ),
    );
  }

  Future<void> _openPost(String postId) async {
    final service = _board;
    if (service == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BoardPostLoaderScreen(service: service, postId: postId),
      ),
    );
    // 글에서 확인한 뒤 새로 온 알림이 있으면 바로 표시합니다.
    if (mounted) await _notifications?.refreshCount();
  }

  Future<void> _openBlockedUsers() async {
    final service = _blocks;
    if (service == null || !service.isCurrentOwner) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BlockedUsersScreen(service: service)),
    );
    if (mounted && service.isCurrentOwner) await _map.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SocialScreen(
        key: ValueKey(_socialRevision),
        initialTab: _socialInitialTab,
        openGroupOnStart: _openGroupOnStart,
        onInitialGroupOpened: () => _openGroupOnStart = false,
        rankingService: _ranking,
        friendService: widget.friendService,
        blockService: _blocks,
        groupController: _groups,
        onProfileTap: () => setState(() => _tab = 2),
      ),
      ProfileScreen(
        onHistoryTap: _openHistory,
        onSettingsTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              mapController: _map,
              managementAccess: _reviews is SupabaseReviewService
                  ? (_reviews as SupabaseReviewService).canAccessManagement()
                  : null,
              onBlockedUsersTap: _blocks == null ? null : _openBlockedUsers,
              isCurrentOwner: () => _map.runHistory.service.isCurrentOwner,
              adminBuilder: (_) => AdminScreen(service: _reviews),
            ),
          ),
        ),
        progressService: _progress,
        statisticsService: _statistics,
        mapController: _map,
        achievementService: _achievements,
      ),
      BoardScreen(service: _board),
    ];

    return Scaffold(
      backgroundColor: _tab == 3 ? Colors.white : null,
      body: SafeArea(
        child: Stack(
          children: [
            Offstage(
              offstage: _tab != 0,
              child: HomeScreen(
                groupController: _groups,
                controller: _map,
                conditionsController: _conditions,
                progressService: _progress,
                blockService: _blocks,
                notificationController: _notifications,
                onOpenPost: _openPost,
                isActive: _tab == 0,
                mapBridgeFactory: widget.mapBridgeFactory,
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
        backgroundColor: _tab == 3 ? Colors.white : null,
        surfaceTintColor: _tab == 3 ? Colors.transparent : null,
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
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: '게시판',
          ),
        ],
      ),
    );
  }
}
