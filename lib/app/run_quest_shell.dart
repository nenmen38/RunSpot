import '../shared/data/account_rpc.dart';

import 'package:runquest/features/settings/run_auto_pause_settings.dart';
import 'package:runquest/features/titles/title_service.dart';
import 'package:runquest/features/titles/badge_directory.dart';
import 'package:app_links/app_links.dart';

import '../features/character/runner_character_directory.dart';
import '../features/feedback/review_prompt.dart';
import '../features/home/home_widget_sync.dart';
import '../features/social/data/cheer_service.dart';
import '../features/profile/running_streak.dart';
import '../features/home/widgets/run_controls.dart';
import '../shared/network/network_status.dart';
import '../shared/network/offline_banner.dart';
import '../features/social/friend_invite_screen.dart';
import '../features/watch/watch_bridge.dart';
import '../features/profile/weekly_goal.dart';

import 'dart:async';

import '../features/notifications/data/push_service.dart';
import '../features/monetization/profile_cosmetics.dart';
import '../features/group_running/widgets/group_start_countdown.dart';

import 'package:flutter/material.dart';
import 'package:runquest/features/onboarding/app_tour.dart';
import 'package:runquest/features/profile/avatar_directory.dart';
import 'package:flutter/services.dart';
import 'package:runquest/features/chat/chat_sync.dart';
import 'package:runquest/features/profile/data/personal_records_service.dart';
import 'package:runquest/features/chat/friend_chat.dart';
import 'package:runquest/features/home/run_guide/run_guide.dart';
import 'package:runquest/features/settings/run_voice_settings.dart';
import 'package:runquest/shared/layout/readable_width.dart';

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
import 'package:runquest/features/crew/crew_controller.dart';
import 'package:runquest/features/crew/data/crew_service.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
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
    this.tour,
    this.mapBridgeFactory,
    this.friendService,
    this.conditionsController,
    this.progressService,
    this.statisticsService,
    this.rankingService,
    this.boardService,
    this.groupController,
    this.notificationController,
    super.key,
  });

  final LiveMapController? mapController;

  /// 처음 실행한 사람에게 보여주는 앱 둘러보기입니다. 없으면 실제 앱에서만 기기 기록을 씁니다.
  final AppTour? tour;
  final MapBridgeFactory? mapBridgeFactory;
  final FriendService? friendService;
  final ConditionsController? conditionsController;
  final ProgressService? progressService;
  final StatisticsService? statisticsService;
  final RankingService? rankingService;
  final BoardService? boardService;
  final GroupController? groupController;
  final NotificationController? notificationController;

  @override
  State<RunQuestShell> createState() => _RunQuestShellState();
}

class _RunQuestShellState extends State<RunQuestShell> {
  // 테스트(가짜 지도)에서는 둘러보기를 띄우지 않고, 실제 앱에서만 기기 기록을 봅니다.
  late final AppTour? _tour =
      widget.tour ?? (widget.mapController == null ? AppTour.instance : null);

  /// 하단(넓은 화면은 왼쪽) 메뉴 아이콘 자리입니다. 둘러보기가 눌러 볼 메뉴를 찾을 때 씁니다.
  final _navKeys = [for (var i = 0; i < 5; i++) (GlobalKey(), GlobalKey())];

  void _tourChanged() {
    if (mounted) setState(() {});
  }

  /// 메뉴 [tab]의 화면 위치(아이콘과 이름까지)입니다.
  Rect? _navTarget(int tab) {
    final (icon, selected) = _navKeys[tab];
    for (final key in [selected, icon]) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      return Rect.fromLTRB(
        rect.left - 22,
        rect.top - 8,
        rect.right + 22,
        rect.bottom + 26,
      );
    }
    return null;
  }

  int _tab = 0;
  WatchBridge? _watch;
  StreamSubscription<Uri>? _inviteLinks;
  HomeWidgetSync? _homeWidget;
  CheerService? _cheers;
  Uri? _lastInvite;
  void _openInvite(Uri uri) {
    // 홈 화면 위젯: runspot://run/start 는 러닝 시작, runspot://home 은 홈 열기입니다.
    if (mounted &&
        uri.scheme == 'runspot' &&
        (uri.host == 'run' || uri.host == 'home')) {
      _openFromWidget(start: uri.host == 'run' && uri.path == '/start');
      return;
    }
    if (!mounted ||
        uri.scheme != 'runspot' ||
        uri.host != 'friend' ||
        uri == _lastInvite) {
      return;
    }
    _lastInvite = uri;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => FriendInviteScreen(
            client: Supabase.instance.client,
            invite: uri.toString(),
          ),
        ),
      );
    });
  }

  void _openFromWidget({required bool start}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _tab = 0);
      if (start) RunControls.startRequested.value = true;
    });
  }

  StreamSubscription<PushDestination>? _pushSubscription;
  StreamSubscription<PushDestination>? _pushMessages;
  int _socialRevision = 0;
  int _socialInitialTab = 0;
  bool _openGroupOnStart = false;
  String? _countdownKey;
  late final LiveMapController _map;
  ConditionsController? _conditions;
  ProgressService? _progress;
  StatisticsService? _statistics;
  RankingService? _ranking;
  BlockService? _blocks;
  FriendService? _friends;
  AchievementService? _achievements;
  ReviewService? _reviews;
  GroupController? _groups;
  BoardService? _board;
  NotificationController? _notifications;
  WalletController? _wallet;
  CrewController? _crew;

  /// 친구 대화의 안 읽은 수와 실시간 신호입니다. 소셜 탭 배지와 대화 화면이 함께 씁니다.
  ChatSync? _chat;
  PersonalRecordsService? _records;
  TitleService? _titles;
  bool _socialShowChat = false;

  @override
  void initState() {
    super.initState();
    _tour?.addListener(_tourChanged);
    if (widget.mapController != null) {
      _map = widget.mapController!;
      _conditions = widget.conditionsController;
      _progress = widget.progressService;
      _statistics = widget.statisticsService;
      _ranking = widget.rankingService;
      _board = widget.boardService;
      _groups = widget.groupController;
      _notifications = widget.notificationController;
    } else {
      final client = Supabase.instance.client;
      // 인터넷 연결 상태를 지켜보며 끊기면 맨 위에 오프라인 띠를 보여 줍니다.
      unawaited(NetworkStatus.instance.start());
      // 평가 요청은 앱을 쓴 지 며칠 지난 뒤에만 하도록 처음 쓴 날을 기억합니다.
      unawaited(ReviewPrompt.instance.remember());
      WeeklyGoal.instance.bind(client);
      _blocks = SupabaseBlockService(client);
      _chat = ChatSync(FriendChatService(client))..start();
      _records = SupabasePersonalRecordsService(client);
      _titles = SupabaseTitleService(client);
      BadgeDirectory.instance.bind(_titles!);
      AvatarDirectory.instance.bind(
        SupabaseAvatarSource(client),
        reports: AccountRpc(client),
      );
      RunnerCharacterDirectory.instance.bind(
        SupabaseRunnerCharacterSource(client),
      );
      _friends = SupabaseFriendService(client);
      _cheers = SupabaseCheerService(client);
      _achievements = SupabaseAchievementService(client);
      final reviews = SupabaseReviewService(client);
      _reviews = reviews;
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
        runGuide: RunGuide(
          DeviceRunGuideOutput(),
          voiceEnabled: () => RunVoiceSettings.instance.enabled,
        ),
        autoPauseEnabled: () => RunAutoPauseSettings.instance.enabled,
        runHistory: RunHistoryController(
          records,
          outbox: SqliteRunOutbox(
            ownerId: records.ownerId,
            namespace: client.rest.url,
          ),
        ),
      );
      _groups =
          widget.groupController ??
          GroupController(SupabaseGroupService(client), _map);
      _board = widget.boardService ?? SupabaseBoardService(client);
      _notifications =
          widget.notificationController ??
          NotificationController(
            SupabaseNotificationService(client),
            reviewService: reviews,
            onGroupChanged: () => unawaited(_groups?.refresh()),
            onCrewChanged: () {
              unawaited(_crew?.refresh());
              unawaited(_wallet?.refresh());
            },
          );
      _wallet = WalletController(SupabaseWalletService(client));
      unawaited(_wallet!.refresh());
      _crew = CrewController(SupabaseCrewService(client));
      unawaited(_crew!.refresh());
    }
    if (widget.mapController == null) {
      final links = AppLinks();
      _inviteLinks = links.uriLinkStream.listen(
        _openInvite,
        onError: (Object _) {},
      );
      unawaited(
        links
            .getInitialLink()
            .then((uri) {
              if (uri != null) _openInvite(uri);
            })
            .catchError((Object _) {}),
      );
      _watch = WatchBridge(_map);
      unawaited(_watch!.start());
      // 연속 기록은 러닝 기록·주간 목표가 바뀔 때마다 다시 읽습니다.
      RunningStreakStore.instance.bind(Supabase.instance.client);
      _map.runHistory.addListener(RunningStreakStore.instance.refreshSoon);
      WeeklyGoal.instance.addListener(RunningStreakStore.instance.refreshSoon);
      // 안드로이드 홈 화면 위젯에 이번 주 기록을 계속 맞춰 줍니다.
      _homeWidget = HomeWidgetSync(history: _map.runHistory)..start();
    }
    _pushSubscription = PushService.instance.destinations.stream.listen(
      _openPush,
    );
    _pushMessages = PushService.instance.messages.stream.listen((destination) {
      if (!mounted ||
          !_map.runHistory.service.isCurrentOwner ||
          _map.runHistory.service.ownerId != destination.recipientId) {
        return;
      }
      _notifications?.refreshCount();
      if (destination.kind == 'group_invite') unawaited(_groups?.refresh());
      if (destination.kind == 'crew_invite') unawaited(_crew?.refresh());
      if (destination.kind == 'friend_message' ||
          destination.kind == 'room_message') {
        // 대화 화면은 실시간으로 바뀌므로 알림 대신 배지만 갱신합니다.
        unawaited(_chat?.refresh());
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (destination.kind) {
              'group_invite' => '함께 달리기 초대가 도착했어요.',
              'crew_invite' => '크루 초대가 도착했어요.',
              'board_like' => '내 글에 좋아요가 달렸어요.',
              'board_comment' => '내 글에 새 댓글이 달렸어요.',
              'friend_request' => '새 친구 요청이 도착했어요.',
              _ => '새 활동 알림이 도착했어요.',
            }),
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
    _groups?.addListener(_groupStateChanged);
  }

  void _groupStateChanged() {
    final group = _groups?.countdownGroup;
    final key = group == null ? null : '${group.id}:${group.startsAt}';
    if (_countdownKey == key) return;
    _countdownKey = key;
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _countdownKey != key) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _tab = 0);
    });
  }

  @override
  void dispose() {
    _tour?.removeListener(_tourChanged);
    _watch?.dispose();
    if (_homeWidget != null) {
      _map.runHistory.removeListener(RunningStreakStore.instance.refreshSoon);
      WeeklyGoal.instance.removeListener(
        RunningStreakStore.instance.refreshSoon,
      );
      RunningStreakStore.instance.unbind();
    }
    _homeWidget?.dispose();
    _inviteLinks?.cancel();
    if (widget.mapController == null) WeeklyGoal.instance.unbind();
    if (_titles != null) {
      BadgeDirectory.instance.unbind();
      AvatarDirectory.instance.unbind();
      RunnerCharacterDirectory.instance.unbind();
    }
    _pushSubscription?.cancel();
    _pushMessages?.cancel();
    _groups?.removeListener(_groupStateChanged);
    if (widget.groupController == null) _groups?.dispose();
    if (widget.notificationController == null) _notifications?.dispose();
    _wallet?.dispose();
    _crew?.dispose();
    _chat?.dispose();
    if (widget.conditionsController == null) _conditions?.dispose();
    _map.runHistory.dispose();
    _map.dispose();
    super.dispose();
  }

  void _openPush(PushDestination destination) {
    if (!mounted ||
        !_map.runHistory.service.isCurrentOwner ||
        _map.runHistory.service.ownerId != destination.recipientId) {
      return;
    }
    PushService.instance.pending = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    // 러닝 응원 알림을 누르면 바로 달릴 수 있게 홈을 엽니다.
    if (destination.kind == 'comeback') {
      setState(() => _tab = 0);
      return;
    }
    if (destination.kind == 'board_comment' ||
        destination.kind == 'board_like') {
      unawaited(_openPost(destination.targetId));
      return;
    }
    setState(() {
      _socialRevision++;
      // 크루 초대는 소셜의 크루 탭(-1)을, 친구 요청은 요청 탭을 엽니다.
      _socialInitialTab = switch (destination.kind) {
        'friend_request' => 1,
        'crew_invite' => -1,
        _ => 0,
      };
      _openGroupOnStart = destination.kind == 'group_invite';
      // 메시지 알림을 누르면 소셜 탭의 대화 목록을 엽니다.
      _socialShowChat =
          destination.kind == 'friend_message' ||
          destination.kind == 'room_message';
      _tab = 1;
    });
  }

  void _openHistory() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            RunHistoryScreen(controller: _map.runHistory, wallet: _wallet),
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
        showChatOnStart: _socialShowChat,
        chatSync: _chat,
        rankingService: _ranking,
        friendService: widget.friendService,
        blockService: _blocks,
        groupController: _groups,
        crewController: _crew,
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
        personalRecordsService: _records,
        titleService: _titles,
        wallet: _wallet,
        statisticsService: _statistics,
        mapController: _map,
        achievementService: _achievements,
        commerceClient: widget.mapController == null
            ? Supabase.instance.client
            : null,
      ),
      BoardScreen(service: _board),
      ProfileCosmetics.store(
        wallet: _wallet,
        history: _map.runHistory,
        crew: _crew,
        client: widget.mapController == null ? Supabase.instance.client : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = OfflineBanner(
          child: _layout(pages, wide: ReadableWidth.isWide(constraints)),
        );
        final tour = _tour;
        if (tour == null || !tour.showing) return layout;
        // 처음 실행이면 하단 메뉴를 하나씩 눌러 보는 둘러보기를 위에 띄웁니다.
        return Stack(
          children: [
            layout,
            Positioned.fill(
              child: AppTourOverlay(
                targetOf: _navTarget,
                onSelectTab: _selectTab,
                onDone: () => unawaited(tour.finish()),
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectTab(int index) => _selectTabImpl?.call(index);
  ValueChanged<int>? _selectTabImpl;

  Widget _layout(List<Widget> pages, {required bool wide}) {
    void select(int index) {
      // 홈과 아이템 탭을 열 때 코인과 착용 테두리를 다시 확인합니다.
      if (index == 0 || index == 2 || index == 4) unawaited(_wallet?.refresh());
      // 소셜·아이템 탭을 열 때 크루와 받은 초대를 다시 확인합니다.
      if (index == 1 || index == 4) unawaited(_crew?.refresh());
      if (index != _tab) unawaited(HapticFeedback.selectionClick());
      setState(() => _tab = index);
    }

    _selectTabImpl = select;

    final background = _tab == 3 ? AppColors.surface : null;
    final content = SafeArea(
      // 넓은 화면에서는 왼쪽 메뉴가 왼쪽 여백을 맡습니다.
      left: !wide,
      child: Stack(
        children: [
          Offstage(
            offstage: _tab != 0,
            child: HomeScreen(
              groupController: _groups,
              controller: _map,
              conditionsController: _conditions,
              progressService: _progress,
              personalRecordsService: _records,
              blockService: _blocks,
              friendService: widget.friendService ?? _friends,
              notificationController: _notifications,
              wallet: _wallet,
              cheerService: _cheers,
              onOpenPost: _openPost,
              isActive: _tab == 0,
              mapBridgeFactory: widget.mapBridgeFactory,
            ),
          ),
          if (_tab != 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              // 폴드를 펼친 화면에서도 글과 버튼이 읽기 좋은 폭을 넘지 않게 합니다.
              // 탭을 바꿀 때 화면이 툭 바뀌지 않도록 살짝 떠오르며 나타나게 합니다.
              child: _TabEntrance(
                key: ValueKey(_tab),
                child: ReadableWidth(child: pages[_tab - 1]),
              ),
            ),
          if (_groups case final groups?)
            Positioned.fill(child: GroupStartCountdown(controller: groups)),
        ],
      ),
    );

    if (wide) {
      // 폴드를 펼친 화면처럼 넓으면 메뉴를 왼쪽 세로로 옮겨 세로 공간을 넓힙니다.
      return Scaffold(
        backgroundColor: background,
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                backgroundColor: background,
                selectedIndex: _tab,
                indicatorColor: AppColors.blueSoft,
                labelType: NavigationRailLabelType.all,
                groupAlignment: 0,
                onDestinationSelected: select,
                destinations: [
                  for (final (index, item) in _destinations.indexed)
                    NavigationRailDestination(
                      icon: _navIcon(index, item.$1),
                      selectedIcon: _navIcon(index, item.$2, selected: true),
                      label: Text(item.$3),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      body: content,
      bottomNavigationBar: NavigationBar(
        backgroundColor: background,
        surfaceTintColor: _tab == 3 ? Colors.transparent : null,
        height: 66,
        selectedIndex: _tab,
        indicatorColor: AppColors.blueSoft,
        onDestinationSelected: select,
        destinations: [
          for (final (index, item) in _destinations.indexed)
            NavigationDestination(
              icon: _navIcon(index, item.$1),
              selectedIcon: _navIcon(index, item.$2, selected: true),
              label: item.$3,
            ),
        ],
      ),
    );
  }

  /// 소셜 탭 아이콘에는 안 읽은 메시지 수를 붙입니다.
  Widget _navIcon(int index, IconData icon, {bool selected = false}) {
    final key = selected ? _navKeys[index].$2 : _navKeys[index].$1;
    return KeyedSubtree(key: key, child: _navIconBody(index, icon));
  }

  Widget _navIconBody(int index, IconData icon) {
    final chat = _chat;
    if (index != 1 || chat == null) return Icon(icon);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Badge(
        isLabelVisible: chat.unreadTotal > 0,
        label: Text(chat.unreadTotal > 99 ? '99+' : '${chat.unreadTotal}'),
        child: Icon(icon),
      ),
    );
  }

  static const _destinations = [
    (Icons.map_outlined, Icons.map, '홈'),
    (Icons.groups_outlined, Icons.groups, '소셜'),
    (Icons.person_outline, Icons.person, '프로필'),
    (Icons.forum_outlined, Icons.forum, '게시판'),
    (Icons.inventory_2_outlined, Icons.inventory_2, '아이템'),
  ];
}

/// 탭 화면이 처음 나타날 때 짧게 흐려졌다가 선명해지며 조금 떠오릅니다.
/// 이전 화면을 겹쳐 두지 않으므로 같은 글자가 두 번 보이는 순간이 없습니다.
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _animation.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 동작 줄이기 설정이면 바로 보여줍니다.
    if (MediaQuery.disableAnimationsOf(context)) _animation.value = 1;
  }

  @override
  void dispose() {
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, .015),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}
