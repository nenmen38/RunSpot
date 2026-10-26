import 'package:flutter/material.dart';

import 'data/korean_regions.dart';

/// 시·도와 시·군·구를 차례로 골라 `시·도 시·군·구` 문자열을 반환합니다.
class RegionPickerScreen extends StatefulWidget {
  const RegionPickerScreen({this.current, super.key});

  final String? current;

  @override
  State<RegionPickerScreen> createState() => _RegionPickerScreenState();
}

class _RegionPickerScreenState extends State<RegionPickerScreen> {
  String? _province;

  void _pickProvince(String province) => setState(() => _province = province);

  @override
  Widget build(BuildContext context) {
    final province = _province;
    final items = province == null
        ? koreanRegions.keys.toList()
        : koreanRegions[province]!;
    return PopScope(
      canPop: province == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _province = null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(province ?? '동네 선택')),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Text(
                province == null
                    ? '시·도를 선택해 주세요.'
                    : '시·군·구를 선택해 주세요. 동네 게시판에는 같은 동네 주민의 글만 보여요.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            for (final item in items)
              Builder(
                builder: (context) {
                  // 하위 목록이 있는 시·도는 아직 동네가 아니므로 null입니다.
                  final label = province != null
                      ? regionLabel(province, item)
                      : koreanRegions[item]!.isEmpty
                      ? item
                      : null;
                  return ListTile(
                    title: Text(item),
                    trailing: label == null
                        ? const Icon(Icons.chevron_right)
                        : label == widget.current
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => label == null
                        ? _pickProvince(item)
                        : Navigator.of(context).pop(label),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
