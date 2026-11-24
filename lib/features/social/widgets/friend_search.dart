import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../auth/data/nickname_service.dart';
import '../friend_controller.dart';
import '../data/block_service.dart';
import '../search_history.dart';
import 'friend_list.dart';

class FriendSearch extends StatefulWidget {
  const FriendSearch({
    required this.controller,
    this.blockService,
    this.history,
    super.key,
  });
  final FriendController controller;
  final BlockService? blockService;

  /// 최근 검색어입니다. 없으면 이 기기에 계정별로 저장합니다.
  final SearchHistory? history;
  @override
  State<FriendSearch> createState() => _FriendSearchState();
}

class _FriendSearchState extends State<FriendSearch> {
  final _input = TextEditingController();
  late final SearchHistory _history =
      widget.history ?? SearchHistory(scope: 'friend');

  @override
  void initState() {
    super.initState();
    if (widget.history == null || !_history.loaded) _history.load();
  }

  @override
  void dispose() {
    if (widget.history == null) _history.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _canSearch {
    final controller = widget.controller;
    return controller.canInteract &&
        !controller.searching &&
        controller.busyUserId == null;
  }

  /// 검색하고, 올바른 닉네임이면 최근 검색어에 남깁니다.
  void _submit(String value) {
    if (!_canSearch) return;
    final query = value.trim();
    if (validateNickname(query) == null) _history.add(query);
    widget.controller.search(query);
  }

  /// 최근 검색어를 누르면 입력칸에 넣고 바로 검색합니다.
  void _searchAgain(String query) {
    _input.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    FocusScope.of(context).unfocus();
    _submit(query);
  }

  void _clearInput() {
    _input.clear();
    widget.controller.queryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // 검색어를 지웠거나 아직 검색하지 않았으면 결과 대신 최근 검색어를 보여줍니다.
    final showHistory =
        _input.text.trim().isEmpty &&
        !controller.searched &&
        !controller.searching;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: AppColors.blue, width: 2),
    );
    return ListView(
      children: [
        const SizedBox(height: 12),
        // 네이버 검색창처럼 굵은 테두리의 둥근 검색창입니다.
        TextField(
          controller: _input,
          enabled: controller.canInteract,
          maxLength: 30,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            controller.queryChanged(value);
            setState(() {});
          },
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: '닉네임으로 친구 찾기',
            counterText: '',
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 4, 14),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: AppColors.blue, width: 2.4),
            ),
            disabledBorder: border.copyWith(
              borderSide: BorderSide(color: AppColors.line, width: 2),
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_input.text.isNotEmpty)
                  IconButton(
                    tooltip: '검색어 지우기',
                    onPressed: () => setState(_clearInput),
                    icon: Icon(Icons.cancel, size: 20, color: AppColors.gray),
                  ),
                IconButton(
                  tooltip: '친구 검색',
                  onPressed: _canSearch ? () => _submit(_input.text) : null,
                  icon: const Icon(Icons.search, color: AppColors.blue),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        if (controller.searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              controller.searchError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (controller.searching) const LinearProgressIndicator(),
        if (showHistory)
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) =>
                _RecentSearches(history: _history, onSearch: _searchAgain),
          ),
        if (controller.searched && controller.results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('검색 결과가 없습니다.', textAlign: TextAlign.center),
          ),
        for (final entry in controller.results)
          FriendRow(
            entry: entry,
            controller: controller,
            blockService: widget.blockService,
          ),
      ],
    );
  }
}

/// 네이버 검색창의 최근 검색어 목록과 같은 모양입니다.
/// 제목·전체 삭제 / 시계 아이콘·검색어·날짜·지우기 / 맨 아래 자동저장 끄기·켜기.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.history, required this.onSearch});

  final SearchHistory history;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    if (!history.loaded) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final gray = TextStyle(color: AppColors.gray, fontSize: 13);
    final items = history.enabled ? history.items : const <SearchHistoryItem>[];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '최근 검색어',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gray,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('전체 삭제'),
                ),
            ],
          ),
          if (!history.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '검색어 저장 기능이 꺼져 있습니다.',
                textAlign: TextAlign.center,
                style: gray,
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '최근 검색어 내역이 없습니다.',
                textAlign: TextAlign.center,
                style: gray,
              ),
            )
          else
            for (final item in items)
              InkWell(
                key: ValueKey('recent-${item.query}'),
                onTap: () => onSearch(item.query),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 18, color: AppColors.gray),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                      Text(
                        '${item.at.month.toString().padLeft(2, '0')}.'
                        '${item.at.day.toString().padLeft(2, '0')}.',
                        style: gray.copyWith(fontSize: 12),
                      ),
                      IconButton(
                        tooltip: '${item.query} 검색어 삭제',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => history.remove(item.query),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          Divider(height: 20, color: AppColors.line),
          // 맨 아래 줄: 왼쪽 자동저장 끄기/켜기.
          Row(
            children: [
              TextButton(
                key: const ValueKey('recent-toggle'),
                onPressed: () => history.setEnabled(!history.enabled),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gray,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(history.enabled ? '자동저장 끄기' : '자동저장 켜기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최근 검색어 전체 삭제'),
        content: const Text('최근 검색어를 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) await history.clear();
  }
}
