import 'package:flutter/material.dart';

import 'appearance/app_appearance.dart';

/// 칼로리 계산에 쓰는 체중(kg)입니다. 이 폰에만 저장하고 서버로 보내지 않습니다.
class BodyWeight extends ChangeNotifier {
  BodyWeight({AppearanceStore? store}) : _given = store;

  static final instance = BodyWeight();
  static const _key = 'body.weight_kg';
  static const minKg = 30.0;
  static const maxKg = 200.0;

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  /// 사용자가 정한 체중입니다. 정하지 않았으면 null입니다.
  double? kg;

  static bool valid(double value) =>
      value.isFinite && value >= minKg && value <= maxKg;

  Future<void> load() async {
    try {
      final value = double.tryParse(await _store.read(_key) ?? '');
      kg = value != null && valid(value) ? value : null;
      notifyListeners();
    } catch (_) {}
  }

  /// [value]가 null이면 체중 설정을 지웁니다.
  Future<void> set(double? value) async {
    if (value != null && !valid(value)) return;
    if (kg == value) return;
    kg = value;
    notifyListeners();
    try {
      await _store.write(_key, value?.toString() ?? '');
    } catch (_) {}
  }
}

/// 체중을 입력받는 창입니다. 저장하면 true를 돌려줍니다.
Future<bool> showBodyWeightDialog(
  BuildContext context,
  BodyWeight weight,
) async {
  final result = await showDialog<({double? kilograms})>(
    context: context,
    builder: (_) => _BodyWeightDialog(kilograms: weight.kg),
  );
  if (result == null) return false;
  await weight.set(result.kilograms);
  return true;
}

class _BodyWeightDialog extends StatefulWidget {
  const _BodyWeightDialog({required this.kilograms});

  final double? kilograms;

  @override
  State<_BodyWeightDialog> createState() => _BodyWeightDialogState();
}

class _BodyWeightDialogState extends State<_BodyWeightDialog> {
  late final TextEditingController _input;
  String? _error;

  @override
  void initState() {
    super.initState();
    final kilograms = widget.kilograms;
    _input = TextEditingController(
      text: kilograms?.toStringAsFixed(kilograms % 1 == 0 ? 0 : 1) ?? '',
    );
  }

  @override
  void dispose() {
    // 입력창이 닫히는 전환이 끝나고 제거될 때 컨트롤러를 해제합니다.
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_input.text.trim());
    if (value == null || !BodyWeight.valid(value)) {
      setState(() => _error = '30~200kg 사이로 입력해 주세요.');
      return;
    }
    Navigator.pop(context, (kilograms: value));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('체중'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('러닝 칼로리를 계산할 때만 쓰고, 이 폰에만 저장해요.'),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: 'kg', errorText: _error),
        ),
      ],
    ),
    actions: [
      if (widget.kilograms != null)
        TextButton(
          onPressed: () => Navigator.pop(context, (kilograms: null)),
          child: const Text('설정 지우기'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(onPressed: _save, child: const Text('저장')),
    ],
  );
}
