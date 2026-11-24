import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../auth/data/nickname_service.dart';
import '../friend_controller.dart';
import '../data/block_service.dart';
import '../../../shared/search_history.dart';
import '../../../shared/widgets/recent_searches.dart';
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
                RecentSearches(history: _history, onSearch: _searchAgain),
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
