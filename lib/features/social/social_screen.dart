import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/friend_service.dart';
import 'data/block_service.dart';
import 'data/ranking_service.dart';
import 'friend_controller.dart';
import 'widgets/friend_list.dart';
import 'widgets/friend_ranking.dart';
import 'widgets/friend_search.dart';
import '../group_running/group_controller.dart';
import '../group_running/group_running_screen.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({
    this.rankingService,
    this.friendService,
    this.blockService,
    this.groupController,
    this.onProfileTap,
    this.initialTab = 0,
    this.openGroupOnStart = false,
    this.onInitialGroupOpened,
    super.key,
  });

  final RankingService? rankingService;
  final FriendService? friendService;
  final BlockService? blockService;
  final GroupController? groupController;
  final VoidCallback? onProfileTap;
  final int initialTab;
  final bool openGroupOnStart;
  final VoidCallback? onInitialGroupOpened;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with WidgetsBindingObserver {
  late final FriendController _friends;
  late final RankingService _ranking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ranking =
        widget.rankingService ??
        SupabaseRankingService(Supabase.instance.client);
    _friends = FriendController(
      widget.friendService ?? SupabaseFriendService(Supabase.instance.client),
    );
    _friends.setActive(true);
    if (widget.openGroupOnStart && widget.groupController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onInitialGroupOpened?.call();
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => GroupRunningScreen(
              controller: widget.groupController!,
              friends: _friends,
            ),
          ),
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _friends.setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _friends.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: widget.initialTab,
    child: AnimatedBuilder(
      animation: _friends,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '소셜',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '친구 목록 새로고침',
                onPressed: _friends.loading || _friends.busyUserId != null
                    ? null
                    : _friends.refresh,
                icon: const Icon(Icons.refresh),
              ),
              if (widget.groupController case final controller?)
                FilledButton.icon(
                  label: const Text('함께 달리기'),
                  icon: const Icon(Icons.directions_run),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => GroupRunningScreen(
                        controller: controller,
                        friends: _friends,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          TabBar(
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              const Tab(text: '친구'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('요청'),
                    if (_friends.received.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Badge(label: Text('${_friends.received.length}')),
                    ],
                  ],
                ),
              ),
              const Tab(text: '검색'),
              const Tab(text: '랭킹'),
            ],
          ),
          if (_friends.loading) const LinearProgressIndicator(),
          if (_friends.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _friends.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_friends.loaded && !_friends.canInteract)
            Row(
              children: [
                const Expanded(child: Text('이메일 인증과 닉네임 등록이 필요합니다.')),
                TextButton(
                  onPressed: widget.onProfileTap,
                  child: const Text('프로필'),
                ),
              ],
            ),
          Expanded(
            child: TabBarView(
              children: [
                FriendList(
                  controller: _friends,
                  requests: false,
                  blockService: widget.blockService,
                ),
                FriendList(
                  controller: _friends,
                  requests: true,
                  blockService: widget.blockService,
                ),
                FriendSearch(
                  controller: _friends,
                  blockService: widget.blockService,
                ),
                FriendRanking(service: _ranking, revision: _friends.revision),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
