import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../models/board_post.dart';
import '../widgets/board_post_tile.dart';
import 'marathon_detail_screen.dart';
import 'marathon_event.dart';
import 'marathon_style.dart';
import 'marathon_service.dart';
import 'marathon_status_badge.dart';
import 'marathon_status_filter.dart';

class MarathonBoard extends StatefulWidget {
  const MarathonBoard({
    required this.service,
    required this.notices,
    required this.onOpenNotice,
    required this.refreshNotices,
    this.query,
    this.onSearch,
    this.searching = false,
    super.key,
  });
  final MarathonService service;
  final List<BoardPost> notices;
  final ValueChanged<BoardPost> onOpenNotice;
  final Future<void> Function() refreshNotices;
  final String? query;
  final VoidCallback? onSearch;
  final bool searching;

  @override
  State<MarathonBoard> createState() => _MarathonBoardState();
}

class _MarathonBoardState extends State<MarathonBoard> {
  MarathonFeed? _feed;
  MarathonStatus? _status;
  bool _loading = true;
  String? _error;
  int _revision = 0;
  Timer? _promotionExpiry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _promotionExpiry?.cancel();
    super.dispose();
  }

  void _schedulePromotionExpiry() {
    _promotionExpiry?.cancel();
    final now = DateTime.now();
    final expiries = _feed?.events
        .map((event) => event.promotedUntil)
        .whereType<DateTime>()
        .where((expiry) => expiry.isAfter(now))
        .toList();
    if (expiries == null || expiries.isEmpty) return;
    expiries.sort();
    _promotionExpiry = Timer(expiries.first.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedulePromotionExpiry();
    });
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feed = await widget.service.load().timeout(
        const Duration(seconds: 15),
      );
      if (mounted && revision == _revision) {
        setState(() => _feed = feed);
        _schedulePromotionExpiry();
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '대회 정보를 불러오지 못했어요.');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query?.trim() ?? '';
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final matching =
        _feed?.events
            .where(
              (event) =>
                  (_status == null || event.status == _status) &&
                  (query.isEmpty || event.matches(query)),
            )
            .toList() ??
        [];
    final now = DateTime.now();
    final promoted = matching
        .where((event) => event.isPromotedAt(now))
        .toList();
    final events = matching.where((event) => !event.isPromotedAt(now)).toList();
    final notices = _status == null || _status == MarathonStatus.unknown
        ? widget.notices
        : const <BoardPost>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            MarathonStatusFilter(
              selected: _status,
              onChanged: (status) => setState(() => _status = status),
            ),
            if (largeText) const Spacer(),
            if (!largeText) const SizedBox(width: 12),
            if (!largeText)
              Expanded(
                child: Text(
                  '${matching.length}개 대회',
                  style: const TextStyle(
                    color: MarathonStyle.secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            if (widget.onSearch != null)
              IconButton(
                tooltip: widget.searching ? '검색 닫기' : '검색',
                onPressed: widget.onSearch,
                icon: Icon(
                  widget.searching ? Icons.search_off : Icons.search,
                  size: 22,
                ),
                color: MarathonStyle.secondary,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
          ],
        ),
        if (largeText)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${matching.length}개 대회',
              style: const TextStyle(
                color: MarathonStyle.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading && _feed == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) => RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait([_load(), widget.refreshNotices()]);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_error != null) _message(_error!, retry: true),
                        if (_feed?.syncedAt == null && _error == null)
                          _message('대회 정보를 준비하고 있어요.', retry: true)
                        else if (_feed?.syncedAt != null &&
                            DateTime.now()
                                    .toUtc()
                                    .difference(_feed!.syncedAt!)
                                    .inHours >=
                                48)
                          _message('정보 갱신이 지연되고 있어요.'),
                        if (!_loading &&
                            _feed?.syncedAt != null &&
                            _error == null &&
                            matching.isEmpty &&
                            notices.isEmpty)
                          SizedBox(
                            height: constraints.maxHeight * .65,
                            child: Center(
                              child: Text(
                                query.isEmpty ? '해당하는 대회가 없어요.' : '검색 결과가 없어요.',
                              ),
                            ),
                          ),
                        for (final event in promoted)
                          _eventTile(event, promoted: true),
                        for (var index = 0; index < events.length; index++) ...[
                          if (index == 0 ||
                              events[index].date.year !=
                                  events[index - 1].date.year ||
                              events[index].date.month !=
                                  events[index - 1].date.month)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 24,
                                bottom: 8,
                                left: 4,
                              ),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  '${events[index].date.year}년 ${events[index].date.month}월',
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          _eventTile(events[index]),
                          if (index + 1 < events.length &&
                              events[index].date.month ==
                                  events[index + 1].date.month &&
                              events[index].date.year ==
                                  events[index + 1].date.year)
                            const Divider(
                              height: 1,
                              color: AppColors.line,
                              thickness: .5,
                            ),
                        ],
                        if (notices.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: 20, bottom: 8),
                            child: Text(
                              '운영 공지',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          for (final post in notices)
                            BoardPostTile(
                              post: post,
                              onTap: () => widget.onOpenNotice(post),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _eventTile(MarathonEvent event, {bool promoted = false}) => _EventTile(
    event: event,
    promoted: promoted,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MarathonDetailScreen(event: event),
      ),
    ),
  );

  Widget _message(String text, {bool retry = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Text(text),
        if (retry)
          TextButton(
            onPressed: _loading ? null : _load,
            child: const Text('다시 시도'),
          ),
      ],
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.onTap,
    required this.promoted,
  });
  final bool promoted;
  final MarathonEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(14) > 20 ? 82 : 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MediaQuery.textScalerOf(context).scale(14) > 20
                        ? '${event.date.month}월\n${event.date.day}일'
                        : '${event.date.month}.${event.date.day}',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    raceCountdown(event.date),
                    style: const TextStyle(
                      color: MarathonStyle.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (promoted)
                    const Text(
                      '광고',
                      style: TextStyle(
                        color: AppColors.blueDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    event.name,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MarathonStyle.secondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  MarathonStatusBadge(status: event.status),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
