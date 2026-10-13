import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ShareTextColorControl extends StatelessWidget {
  const ShareTextColorControl({
    required this.color,
    required this.automaticColor,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final Color? color;
  final Color automaticColor;
  final ValueChanged<Color?> onChanged;
  final bool enabled;

  static const swatches = [
    ('흰색', Color(0xFFFFFFFF)),
    ('검정', Color(0xFF171A1D)),
    ('라임', Color(0xFFCAFF70)),
    ('하늘', Color(0xFF9FE7FF)),
    ('노랑', Color(0xFFFFDB7B)),
    ('분홍', Color(0xFFFFA8C7)),
  ];

  Future<void> _custom(BuildContext context) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorDialog(initial: color ?? automaticColor),
    );
    if (context.mounted && selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('글자 색', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 4,
        runSpacing: 8,
        children: [
          IconButton(
            tooltip: '자동 글자 색',
            isSelected: color == null,
            onPressed: enabled ? () => onChanged(null) : null,
            icon: const Icon(Icons.auto_fix_high_outlined),
            selectedIcon: const Icon(Icons.auto_fix_high),
          ),
          for (final swatch in swatches)
            Tooltip(
              message: '글자 색 ${swatch.$1}',
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                selected: color == swatch.$2,
                enabled: enabled,
                label: '글자 색 ${swatch.$1}',
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: InkResponse(
                    onTap: enabled ? () => onChanged(swatch.$2) : null,
                    radius: 24,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: swatch.$2,
                          border: Border.all(
                            color: color == swatch.$2
                                ? Theme.of(context).colorScheme.primary
                                : const Color(0xFF8A9297),
                            width: color == swatch.$2 ? 3 : 1,
                          ),
                        ),
                        child: color == swatch.$2
                            ? Icon(
                                Icons.check,
                                size: 17,
                                color: swatch.$2.computeLuminance() > .4
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: '사용자 지정 글자 색',
            isSelected:
                color != null && !swatches.any((swatch) => swatch.$2 == color),
            onPressed: enabled ? () => _custom(context) : null,
            icon: const Icon(Icons.color_lens_outlined),
            selectedIcon: const Icon(Icons.color_lens),
          ),
        ],
      ),
    ],
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});
  final Color initial;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late Color _color = widget.initial;
  late final _code = TextEditingController(text: _hex(_color));
  String? _error;

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _changeCode(String value) {
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized);
    setState(() {
      _error = valid ? null : '여섯 자리 색상 코드를 입력해 주세요.';
      if (valid) _color = Color(0xFF000000 | int.parse(normalized, radix: 16));
    });
  }

  Widget _channel(String name, int shift, Color track) {
    final value = (_color.toARGB32() >> shift) & 255;
    return Row(
      children: [
        SizedBox(width: 40, child: Text(name)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: track,
            label: '$value',
            onChanged: (next) => setState(() {
              final rgb = _color.toARGB32();
              _color = Color((rgb & ~(255 << shift)) | (next.round() << shift));
              _code.text = _hex(_color);
              _error = null;
            }),
          ),
        ),
        SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('글자 색'),
    content: SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 40, width: double.infinity, color: _color),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            maxLength: 7,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
            ],
            decoration: InputDecoration(
              labelText: '색상 코드',
              hintText: '#FFFFFF',
              errorText: _error,
              errorMaxLines: 3,
              counterText: '',
            ),
            onChanged: _changeCode,
          ),
          const SizedBox(height: 12),
          _channel('빨강', 16, Colors.red),
          _channel('초록', 8, Colors.green),
          _channel('파랑', 0, Colors.blue),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _error == null
            ? () => Navigator.of(context).pop(_color)
            : null,
        child: const Text('적용'),
      ),
    ],
  );
}
