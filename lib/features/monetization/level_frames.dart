import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_colors.dart';
import '../progress/data/progress_service.dart';

/// 레벨 보상 테두리의 색 구간입니다. 10단위 레벨은 앞 5단위 색에 오라만 더합니다.
enum FrameTier {
  warmup('워밍업', Color(0xFF94A3B8)),
  easy('이지런', Color(0xFF38BDF8)),
  tempo('템포', Color(0xFF22C55E)),
  threshold('역치', Color(0xFFF97316)),
  race('레이스', Color(0xFFEF4444));

  const FrameTier(this.label, this.color);
  final String label;
  final Color color;
}

/// Lv 5부터 5레벨마다 받는 테두리입니다. 러닝 지도에서 내 위치 원에 표시합니다.
class LevelFrame {
  const LevelFrame._(this.level);

  static const all = [
    LevelFrame._(5),
    LevelFrame._(10),
    LevelFrame._(15),
    LevelFrame._(20),
    LevelFrame._(25),
    LevelFrame._(30),
    LevelFrame._(35),
    LevelFrame._(40),
    LevelFrame._(45),
    LevelFrame._(50),
  ];

  static const gold = Color(0xFFFACC15);

  final int level;

  FrameTier get tier => FrameTier.values[(level - 1) ~/ 10];

  /// 테두리는 구간마다 2px에서 4px까지 두꺼워집니다.
  double get borderWidth => 2 + tier.index * .5;
  bool get hasAura => level % 10 == 0;
  bool get pulses => level == 40;
  bool get isMax => level == 50;

  String get name => 'Lv $level ${tier.label} 테두리';
  String get effect => switch (level) {
    10 => '오라 약',
    20 => '오라 중',
    30 => '오라 강',
    40 => '맥동',
    50 => 'MAX · 골드 링',
    _ => '기본 테두리',
  };

  static LevelFrame? of(int? level) =>
      all.where((frame) => frame.level == level).firstOrNull;

  /// [playerLevel]까지 받은 테두리입니다.
  static List<LevelFrame> unlocked(int playerLevel) =>
      all.where((frame) => frame.level <= playerLevel).toList();

  static LevelFrame? next(int playerLevel) =>
      all.where((frame) => frame.level > playerLevel).firstOrNull;
}

/// 개발 실행에서만 쓰는 테두리 시험 레벨입니다. `--dart-define=DEV_LEVEL=50`처럼 줍니다.
/// 출시(릴리스) 빌드에서는 값이 있어도 무시합니다.
int? devLevelOverride() {
  if (!kDebugMode) return null;
  final level = int.tryParse(const String.fromEnvironment('DEV_LEVEL'));
  return level != null && level >= 1 && level <= 99 ? level : null;
}

/// 착용한 테두리를 계정별로 저장합니다.
abstract interface class FrameStorage {
  Future<int?> read();
  Future<void> write(int? level);
}

class PreferencesFrameStorage implements FrameStorage {
  PreferencesFrameStorage(this.key);
  final String key;
  final _prefs = SharedPreferencesAsync();

  @override
  Future<int?> read() => _prefs.getInt(key);

  @override
  Future<void> write(int? level) =>
      level == null ? _prefs.remove(key) : _prefs.setInt(key, level);
}

class MemoryFrameStorage implements FrameStorage {
  int? value;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int? level) async => value = level;
}

/// 서버 레벨로 받은 테두리를 계산하고 착용 상태를 관리합니다.
/// 레벨이 오르면 다시 불러올 때 새 테두리가 보관함에 자동으로 들어옵니다.
class LevelFrameController extends ChangeNotifier {
  LevelFrameController(this.progress, this.storage, {this.levelOverride});

  final ProgressService progress;
  final FrameStorage storage;

  /// 개발 실행에서 테두리를 시험하려고 쓰는 레벨입니다. 서버 경험치는 바꾸지 않습니다.
  final int? levelOverride;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  bool _storageLoaded = false;
  int _generation = 0;
  int? level;
  int? _equipped;
  bool loading = false;
  String? error;

  List<LevelFrame> get unlocked =>
      level == null ? const [] : LevelFrame.unlocked(level!);
  LevelFrame? get next => level == null ? null : LevelFrame.next(level!);

  /// 착용한 테두리입니다. 받지 않은 레벨의 저장값은 무시합니다.
  LevelFrame? get equipped {
    final frame = LevelFrame.of(_equipped);
    return frame != null && level != null && frame.level <= level!
        ? frame
        : null;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!_storageLoaded) {
        _equipped = await storage.read();
        _storageLoaded = true;
      }
      final result = await progress.load().timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (!progress.isCurrentOwner) throw StateError('계정이 변경되었습니다.');
      level = levelOverride ?? result.level;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = '레벨 정보를 불러오지 못했습니다.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 테두리는 하나만 착용합니다. null이면 해제합니다.
  Future<void> wear(LevelFrame? frame) async {
    if (_disposed) return;
    if (frame != null && !unlocked.contains(frame)) return;
    _equipped = frame?.level;
    notifyListeners();
    try {
      await storage.write(frame?.level);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

/// 테두리 미리보기입니다. 지도 위 내 위치 원과 같은 모양으로 그립니다.
class LevelFrameBadge extends StatefulWidget {
  const LevelFrameBadge({required this.frame, this.size = 56, super.key});

  final LevelFrame frame;
  final double size;

  @override
  State<LevelFrameBadge> createState() => _LevelFrameBadgeState();
}

class _LevelFrameBadgeState extends State<LevelFrameBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _motion;

  bool get _animated => widget.frame.pulses || widget.frame.isMax;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 동작 줄이기 설정에서는 움직이지 않는 모양으로 보여줍니다.
    final still = MediaQuery.disableAnimationsOf(context);
    if (_animated && !still) {
      _motion ??= AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.frame.isMax ? 3000 : 1600),
      )..repeat(reverse: widget.frame.pulses);
    } else {
      _motion?.dispose();
      _motion = null;
    }
  }

  @override
  void dispose() {
    _motion?.dispose();
    super.dispose();
  }

  List<BoxShadow> _aura(double t) {
    final frame = widget.frame;
    final color = frame.tier.color;
    return switch (frame.level) {
      10 => [BoxShadow(color: color.withValues(alpha: .6), blurRadius: 6)],
      20 => [
        BoxShadow(
          color: color.withValues(alpha: .65),
          blurRadius: 10,
          spreadRadius: 2,
        ),
      ],
      30 => [
        BoxShadow(
          color: color.withValues(alpha: .75),
          blurRadius: 14,
          spreadRadius: 4,
        ),
      ],
      40 => [
        BoxShadow(
          color: color.withValues(alpha: .6 + .3 * t),
          blurRadius: 8 + 10 * t,
          spreadRadius: 2 + 6 * t,
        ),
      ],
      // MAX의 빛은 바깥 링에 둡니다. 원에 두면 링을 가립니다.
      _ => const [],
    };
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    final size = widget.size;
    Widget paint(double t) {
      final circle = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: frame.tier.color,
            width: frame.borderWidth * size / 34,
          ),
          boxShadow: _aura(t),
        ),
        child: Icon(
          Icons.directions_run,
          size: size * .52,
          color: const Color(0xFF334155),
        ),
      );
      if (!frame.isMax) return circle;
      // MAX는 빨강·골드 링을 한 겹 더 두르고 천천히 돌립니다.
      return Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: t * 2 * math.pi,
            child: Container(
              width: size * 1.3,
              height: size * 1.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: frame.tier.color.withValues(alpha: .7),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ],
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFEF4444),
                    LevelFrame.gold,
                    Color(0xFFEF4444),
                  ],
                ),
              ),
            ),
          ),
          circle,
        ],
      );
    }

    final motion = _motion;
    return Semantics(
      label: '${frame.name} 미리보기',
      child: SizedBox.square(
        dimension: size * 1.4,
        child: Center(
          child: motion == null
              ? paint(frame.pulses ? .5 : 0)
              : AnimatedBuilder(
                  animation: motion,
                  builder: (context, _) => paint(motion.value),
                ),
        ),
      ),
    );
  }
}

/// 보관함 맨 위의 레벨 보상 테두리 목록입니다. 착용은 하나만, 해제는 착용 중일 때만 됩니다.
class LevelFrameSection extends StatelessWidget {
  const LevelFrameSection({required this.controller, super.key});

  final LevelFrameController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final frames = controller.unlocked;
      final next = controller.next;
      final equipped = controller.equipped;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '레벨 보상 테두리',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('착용하면 러닝 지도에서 내 위치 원에 표시돼요.', style: text.bodySmall),
          const SizedBox(height: 10),
          if (controller.loading && controller.level == null)
            const LinearProgressIndicator(),
          if (controller.error case final message?)
            Row(
              children: [
                Expanded(child: Text(message)),
                TextButton(
                  onPressed: controller.refresh,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          for (final frame in frames.reversed)
            _FrameTile(
              frame: frame,
              equipped: equipped == frame,
              onWear: () => controller.wear(frame),
              onRemove: () => controller.wear(null),
            ),
          if (controller.level case final level?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                next == null
                    ? '지금 Lv $level. 모든 레벨 보상을 받았어요.'
                    : frames.isEmpty
                    ? '지금 Lv $level. Lv ${next.level}이 되면 첫 테두리를 받아요.'
                    : '지금 Lv $level. 다음 보상은 Lv ${next.level} ${next.tier.label} 테두리예요.',
                style: text.bodySmall?.copyWith(color: AppColors.gray),
              ),
            ),
          const SizedBox(height: 20),
        ],
      );
    },
  );
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.equipped,
    required this.onWear,
    required this.onRemove,
  });

  final LevelFrame frame;
  final bool equipped;
  final VoidCallback onWear;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('frame-${frame.level}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: equipped ? AppColors.blue : AppColors.line,
          width: equipped ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(child: LevelFrameBadge(frame: frame, size: 40)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      frame.name,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (equipped)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            '착용 중',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(frame.effect, style: text.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: equipped ? null : onWear,
                        child: const Text('착용'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: equipped ? onRemove : null,
                        child: const Text('해제'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
