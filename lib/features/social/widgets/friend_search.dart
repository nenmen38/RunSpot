import 'package:flutter/material.dart';

import '../friend_controller.dart';
import 'friend_list.dart';

class FriendSearch extends StatefulWidget {
  const FriendSearch({required this.controller, super.key});
  final FriendController controller;
  @override
  State<FriendSearch> createState() => _FriendSearchState();
}

class _FriendSearchState extends State<FriendSearch> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          enabled: controller.canInteract,
          maxLength: 30,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onChanged: controller.queryChanged,
          onSubmitted: controller.search,
          decoration: InputDecoration(
            labelText: '닉네임',
            counterText: '',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_input.text.isNotEmpty)
                  IconButton(
                    tooltip: '검색어 지우기',
                    onPressed: () {
                      _input.clear();
                      controller.queryChanged('');
                    },
                    icon: const Icon(Icons.close),
                  ),
                IconButton(
                  tooltip: '친구 검색',
                  onPressed:
                      controller.canInteract &&
                          !controller.searching &&
                          controller.busyUserId == null
                      ? () => controller.search(_input.text)
                      : null,
                  icon: const Icon(Icons.search),
                ),
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
        Expanded(
          child: ListView(
            children: [
              if (controller.searched && controller.results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('검색 결과가 없습니다.', textAlign: TextAlign.center),
                ),
              for (final entry in controller.results)
                FriendRow(entry: entry, controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}
