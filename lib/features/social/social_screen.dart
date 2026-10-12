import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/friend_service.dart';
import 'friend_controller.dart';
import 'widgets/friend_list.dart';
import 'widgets/friend_ranking.dart';
import 'widgets/friend_search.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({
    required this.rankingMode,
    required this.onModeChanged,
    this.friendService,
    this.onProfileTap,
    super.key,
  });

  final int rankingMode;
  final ValueChanged<int> onModeChanged;
  final FriendService? friendService;
  final VoidCallback? onProfileTap;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with WidgetsBindingObserver {
  late final FriendController _friends;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _friends = FriendController(
      widget.friendService ?? SupabaseFriendService(Supabase.instance.client),
    );
    _friends.setActive(true);
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
                FriendList(controller: _friends, requests: false),
                FriendList(controller: _friends, requests: true),
                FriendSearch(controller: _friends),
                FriendRanking(
                  mode: widget.rankingMode,
                  onModeChanged: widget.onModeChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
