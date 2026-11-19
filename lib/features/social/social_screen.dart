import '../crew/models/crew.dart';
import '../chat/new_chat_screen.dart';
import '../chat/chat_rooms.dart';
import 'friend_invite_screen.dart';
import '../../shared/data/account_rpc.dart';
import '../meetups/meetup_screen.dart';

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
import '../chat/chat_sync.dart';
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
    this.showChatOnStart = false,
    this.chatSync,
    super.key,
  });

  /// 메시지 알림으로 들어오면 처음부터 대화 목록을 보여줍니다.
  final bool showChatOnStart;

  /// 안 읽은 메시지 수와 실시간 신호입니다.
  final ChatSync? chatSync;

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
  late bool _showChat = widget.showChatOnStart;
  FriendChatService? _chat;
  ChatRoomService? _rooms;

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
      _rooms = SupabaseChatRoomService(service.client);
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

  int _chatListRevision = 0;

  /// 친구·크루원 중에서 골라 대화를 시작합니다. 친구 한 명이면 1:1 대화, 여러 명이면 단톡입니다.
  Future<void> _newChat() async {
    final rooms = _rooms, chat = _chat;
    if (rooms == null || chat == null) return;
    await _friends.refresh();
    await widget.crewController?.refresh();
    if (!mounted) return;
    final selection = await Navigator.of(context).push<NewChatSelection>(
      MaterialPageRoute(
        builder: (_) => NewChatScreen(
          friends: [
            for (final friend in _friends.friends)
              (id: friend.userId, nickname: friend.nickname),
          ],
          crews: widget.crewController?.crews ?? const [],
          ownerId: rooms.ownerId,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    final friendIds = {for (final friend in _friends.friends) friend.userId};
    if (selection.members.length == 1 &&
        friendIds.contains(selection.members.keys.single)) {
      final entry = selection.members.entries.single;
      await openFriendChat(
        context,
        chat.client,
        entry.key,
        entry.value,
        sync: widget.chatSync,
      );
    } else {
      try {
        final room = await rooms.create(
          selection.members.keys.toList(),
          name: selection.name,
        );
        if (!mounted) return;
        await openChatRoom(context, rooms, room, sync: widget.chatSync);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PostgrestException
                  ? error.message
                  : '대화방을 만들지 못했습니다. 다시 시도해 주세요.',
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _chatListRevision++);
  }

  /// 크루 단체 대화방으로 바로 들어갑니다.
  Future<void> _openCrewChat(Crew crew) async {
    final rooms = _rooms;
    if (rooms == null) return;
    try {
      final room = await rooms.crewRoom(crew.id);
      if (!mounted) return;
      await openChatRoom(context, rooms, room, sync: widget.chatSync);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('크루 대화방에 들어가지 못했습니다.')));
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
                      ? AppColors.blueText
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
              segments: [
                const ButtonSegment(value: false, label: Text('소셜')),
                ButtonSegment(value: true, label: _chatLabel()),
              ],
              selected: {_showChat},
              onSelectionChanged: (values) =>
                  setState(() => _showChat = values.single),
              showSelectedIcon: false,
            ),
            const Spacer(),
            // 대화 화면에서는 오른쪽 위에서 새 대화(1:1·단톡)를 시작합니다.
            if (_showChat && _rooms != null)
              IconButton(
                tooltip: '새 대화',
                onPressed: _newChat,
                icon: const Icon(Icons.add_comment_outlined),
              ),
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
        if (!_showChat && chat != null)
          TextButton.icon(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => FriendInviteScreen(client: chat.client),
              ),
            ),
            icon: const Icon(Icons.qr_code),
            label: const Text('친구 초대'),
          ),
        if (!_showChat && chat != null && widget.groupController != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.event_available),
              label: const Text('동네 러닝 모임'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => MeetupScreen(
                    service: AccountRpc(chat.client),
                    onGroup: () async {
                      await widget.groupController!.refresh();
                      if (!context.mounted) return;
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupRunningScreen(
                            controller: widget.groupController!,
                            friends: _friends,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _showChat
              ? chat != null
                    ? FriendChatView(
                        key: ValueKey(_chatListRevision),
                        service: chat,
                        sync: widget.chatSync,
                        rooms: _rooms,
                      )
                    : const Center(child: Text('대화를 사용할 수 없습니다.'))
              : _social(),
        ),
      ],
    );
  }

  /// '대화' 버튼 옆에 안 읽은 메시지 수를 보여줍니다.
  Widget _chatLabel() {
    final sync = widget.chatSync;
    if (sync == null) return const Text('대화');
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => Badge(
        isLabelVisible: sync.unreadTotal > 0,
        offset: const Offset(14, -6),
        label: Text(sync.unreadTotal > 99 ? '99+' : '${sync.unreadTotal}'),
        child: const Text('대화'),
      ),
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
                  CrewTab(
                    controller: crew,
                    onOpenChat: _rooms == null ? null : _openCrewChat,
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
