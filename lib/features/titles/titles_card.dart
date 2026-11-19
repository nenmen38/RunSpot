import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/panel.dart';
import '../../shared/widgets/status_view.dart';
import '../monetization/cosmetics.dart';
import 'badge_directory.dart';
import 'title_service.dart';

/// 프로필의 칭호 카드입니다. 달려서 얻은 칭호 중 하나를 닉네임 옆에 달 수 있습니다.
class TitlesCard extends StatefulWidget {
  const TitlesCard({required this.service, this.titleStyle, super.key});

  final TitleService service;

  /// 착용한 칭호 모양입니다. 미리보기에 씁니다.
  final CosmeticItem? titleStyle;

  @override
  State<TitlesCard> createState() => _TitlesCardState();
}

class _TitlesCardState extends State<TitlesCard> {
  TitlesState? _state;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _run(Future<TitlesState> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await action().timeout(const Duration(seconds: 15));
      if (!mounted || !widget.service.isCurrentOwner) return;
      setState(() => _state = state);
    } catch (_) {
      if (mounted) setState(() => _error = '칭호를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(widget.service.load);

  Future<void> _select(RunnerTitle? title) async {
    await _run(() => widget.service.select(title));
    // 다른 화면의 내 칭호도 새로 불러오게 합니다.
    BadgeDirectory.instance.refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = _state;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech_outlined, color: AppColors.purple),
              const SizedBox(width: 8),
              Expanded(child: Text('칭호', style: text.titleMedium)),
              if (state?.selected case final title?)
                TitleBadge(title: title, style: widget.titleStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '달려서 얻은 칭호 하나를 닉네임 옆에 달 수 있어요. 칭호는 코인으로 살 수 없어요.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),
          if (_busy && state == null) const LinearProgressIndicator(),
          if (_error case final message? when state == null)
            InlineError(message: message),
          if (state != null)
            for (final item in state.titles)
              Padding(
                key: ValueKey('title-${item.title.code}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      item.title.icon,
                      color: item.earned ? AppColors.purple : AppColors.gray,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: item.earned ? null : AppColors.gray,
                            ),
                          ),
                          Text(item.title.condition, style: text.bodySmall),
                          if (!item.earned) ...[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: item.ratio,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            const SizedBox(height: 2),
                            Text(item.label, style: text.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (item.earned)
                      state.selected == item.title
                          ? OutlinedButton(
                              onPressed: _busy ? null : () => _select(null),
                              child: const Text('떼기'),
                            )
                          : FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _select(item.title),
                              child: const Text('달기'),
                            ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
