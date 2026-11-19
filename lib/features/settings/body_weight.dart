import 'package:flutter/material.dart';

import '../run_history/models/run_calories.dart';
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

  /// 계산에 쓰는 체중입니다. 정하지 않았으면 기본 65kg입니다.
  double get effectiveKg => kg ?? defaultBodyWeightKg;

  static bool valid(double value) =>
      value.isFinite && value >= minKg && value <= maxKg;

  Future<void> load() async {
    try {
      final value = double.tryParse(await _store.read(_key) ?? '');
      kg = value != null && valid(value) ? value : null;
      notifyListeners();
    } catch (_) {}
  }

  /// [value]가 null이면 기본값으로 되돌립니다.
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
  final input = TextEditingController(
    text: weight.kg == null
        ? ''
        : weight.kg!.toStringAsFixed(weight.kg! % 1 == 0 ? 0 : 1),
  );
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('체중'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('러닝 칼로리를 계산할 때만 쓰고, 이 폰에만 저장해요.'),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                suffixText: 'kg',
                hintText: '${defaultBodyWeightKg.round()}',
                errorText: error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (weight.kg != null)
            TextButton(
              onPressed: () async {
                await weight.set(null);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('기본값으로'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(input.text.trim());
              if (value == null || !BodyWeight.valid(value)) {
                setState(() => error = '30~200kg 사이로 입력해 주세요.');
                return;
              }
              await weight.set(value);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    ),
  );
  input.dispose();
  return saved == true;
}
