import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../chat/friend_chat.dart';
import '../crew/crew_controller.dart';
import '../crew/widgets/crew_widgets.dart';
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
    this.crewController,
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

  /// 있으면 친구 옆에 크루 탭을 두고, 크루장에게 크루원 초대 버튼을 보여줍니다.
  final CrewController? crewController;
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
  bool _showChat = false;
  FriendChatService? _chat;

  Future<void> _invite(String userId) async {
    final message = await widget.groupController?.inviteAndStart(userId);
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
    if (_friends.service case final SupabaseFriendService service) {
      _chat = FriendChatService(service.client);
    }
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
  Widget build(BuildContext context) {
    final chat = _chat;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SegmentedButton<bool>(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.blueSoft
                      : theme.colorScheme.surfaceContainerLow,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.blueDark
                      : theme.colorScheme.onSurfaceVariant,
                ),
                textStyle: WidgetStateProperty.resolveWith(
                  (states) => theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 18),
                ),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('소셜')),
                ButtonSegment(value: true, label: Text('대화')),
              ],
              selected: {_showChat},
              onSelectionChanged: (values) =>
                  setState(() => _showChat = values.single),
              showSelectedIcon: false,
            ),
            const Spacer(),
            if (!_showChat)
              ListenableBuilder(
                listenable: _friends,
                builder: (context, _) => IconButton(
                  tooltip: '친구 목록 새로고침',
                  onPressed: _friends.loading || _friends.busyUserId != null
                      ? null
                      : _friends.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _showChat
              ? chat != null
                    ? FriendChatView(service: chat)
                    : const Center(child: Text('대화를 사용할 수 없습니다.'))
              : _social(),
        ),
      ],
    );
  }

  Widget _social() => DefaultTabController(
    length: widget.crewController == null ? 4 : 5,
    // initialTab은 크루 탭이 없을 때의 번호입니다. 크루 탭이 친구 다음에 끼므로 뒤 탭은 한 칸 밀립니다.
    initialIndex: widget.crewController != null && widget.initialTab >= 1
        ? widget.initialTab + 1
        : widget.initialTab,
    child: AnimatedBuilder(
      animation: Listenable.merge([_friends, ?widget.crewController]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              const Tab(text: '친구'),
              if (widget.crewController != null)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('크루'),
                      if (widget.crewController!.invites.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Badge(
                          label: Text(
                            '${widget.crewController!.invites.length}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
                  crew: widget.crewController,
                  onRunInvite: widget.groupController == null
                      ? null
                      : (entry) => _invite(entry.userId),
                ),
                if (widget.crewController case final crew?)
                  CrewTab(controller: crew),
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
