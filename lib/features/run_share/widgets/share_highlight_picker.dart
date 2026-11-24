import 'package:flutter/material.dart';

import '../models/share_highlights.dart';

class ShareHighlightPicker extends StatefulWidget {
  const ShareHighlightPicker({
    required this.initial,
    required this.load,
    required this.isCurrentOwner,
    super.key,
  });

  final ShareHighlights? initial;
  final Future<ShareHighlightChoices> Function() load;
  final bool Function() isCurrentOwner;

  @override
  State<ShareHighlightPicker> createState() => _ShareHighlightPickerState();
}

class _ShareHighlightPickerState extends State<ShareHighlightPicker> {
  late final _choices = widget.load();
  late String? _title = widget.initial?.title;
  late String? _achievement = widget.initial?.achievement;
  late String? _milestone = widget.initial?.milestone;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _choices,
    builder: (context, snapshot) {
      final choices = widget.isCurrentOwner() ? snapshot.data : null;
      return AlertDialog(
        title: const Text('성과·칭호·업적 넣기'),
        scrollable: true,
        content: choices == null
            ? Text(
                !widget.isCurrentOwner()
                    ? '로그인 상태를 확인해 주세요.'
                    : snapshot.hasError
                    ? '칭호와 업적을 불러오지 못했습니다.'
                    : '칭호와 업적을 불러오는 중이에요.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choices.milestones case final milestones?)
                    _select('러닝 성과', milestones, _milestone, (value) {
                      setState(() => _milestone = value);
                    })
                  else
                    const Text('러닝 성과는 현재 이 서버에서 사용할 수 없습니다.'),
                  _select('칭호', choices.titles, _title, (value) {
                    setState(() => _title = value);
                  }),
                  _select('업적', choices.achievements, _achievement, (value) {
                    setState(() => _achievement = value);
                  }),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (choices != null)
            FilledButton(
              onPressed: () => Navigator.pop<ShareHighlights>(context, (
                milestone: choices.milestones?.contains(_milestone) == true
                    ? _milestone
                    : null,
                title: choices.titles.contains(_title) ? _title : null,
                achievement: choices.achievements.contains(_achievement)
                    ? _achievement
                    : null,
              )),
              child: const Text('적용'),
            ),
        ],
      );
    },
  );

  Widget _select(
    String label,
    List<String> list,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => DropdownButton<String>(
    isExpanded: true,
    value: list.contains(selected) ? selected : '',
    items: [
      DropdownMenuItem(value: '', child: Text('$label 표시 안 함')),
      for (final value in list.toSet())
        DropdownMenuItem(value: value, child: Text(value)),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
  );
}
