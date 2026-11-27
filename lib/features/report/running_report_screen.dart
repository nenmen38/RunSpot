import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../shared/formatters/run_format.dart';
import '../../shared/widgets/status_view.dart';
import '../character/runner_character.dart';
import '../run_share/data/run_share_service.dart';
import 'running_report.dart';

/// 월간·연간 러닝 리포트입니다. 카드를 옆으로 넘기며 보고, 마지막 카드를 이미지로 공유합니다.
class RunningReportScreen extends StatefulWidget {
  const RunningReportScreen({
    required this.service,
    this.outfit = CharacterOutfit.none,
    this.shareService,
    this.now,
    super.key,
  });

  final RunningReportService service;
  final CharacterOutfit outfit;
  final RunShareService? shareService;
  final DateTime? now;

  @override
  State<RunningReportScreen> createState() => _RunningReportScreenState();
}

class _RunningReportScreenState extends State<RunningReportScreen> {
  late final DateTime _now = widget.now ?? DateTime.now();
  late ReportPeriod _period;
  late DateTime _starts;
  RunningReport? _report;
  String? _error;
  bool _loading = true;
  bool _sharing = false;
  int _page = 0;
  int _generation = 0;
  final _pages = PageController();
  final _shareCard = GlobalKey();
  final _shareButton = GlobalKey();

  @override
  void initState() {
    super.initState();
    final initial = defaultReport(_now);
    _period = initial.period;
    _starts = initial.starts;
    unawaited(_load());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.service
          .load(_period, _starts)
          .timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() {
        _report = report;
        _page = 0;
      });
      if (_pages.hasClients) _pages.jumpToPage(0);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '리포트를 불러오지 못했어요.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _select(ReportPeriod period) {
    if (period == _period) return;
    _period = period;
    _starts = period == ReportPeriod.year
        ? DateTime(_starts.year)
        : (_starts.year == _now.year
              ? DateTime(_now.year, _now.month)
              : DateTime(_starts.year, 12));
    unawaited(_load());
  }

  /// 이전·다음 달(또는 해)로 옮깁니다. 앞으로는 이번 달(올해)까지만 갑니다.
  void _move(int step) {
    final next = _period == ReportPeriod.year
        ? DateTime(_starts.year + step)
        : DateTime(_starts.year, _starts.month + step);
    if (next.isAfter(_now)) return;
    _starts = next;
    unawaited(_load());
  }

  bool get _canGoForward {
    final next = _period == ReportPeriod.year
        ? DateTime(_starts.year + 1)
        : DateTime(_starts.year, _starts.month + 1);
    return !next.isAfter(_now);
  }

  Future<void> _share() async {
    final boundary =
        _shareCard.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null || !mounted) return;
      final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null
          ? Rect.zero
          : box.localToGlobal(Offset.zero) & box.size;
      await (widget.shareService ?? PlatformRunShareService()).share(
        bytes.buffer.asUint8List(),
        origin,
        isCurrentOwner: () => mounted,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('리포트를 공유하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final cards = report == null || report.isEmpty
        ? const <Widget>[]
        : _cards(report);
    return Scaffold(
      appBar: AppBar(title: const Text('러닝 리포트')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<ReportPeriod>(
                segments: const [
                  ButtonSegment(value: ReportPeriod.month, label: Text('월간')),
                  ButtonSegment(value: ReportPeriod.year, label: Text('연간')),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: _loading
                    ? null
                    : (value) => _select(value.single),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _period == ReportPeriod.year ? '이전 해' : '이전 달',
                  onPressed: _loading ? null : () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  _period == ReportPeriod.year
                      ? '${_starts.year}년'
                      : '${_starts.year}년 ${_starts.month}월',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                IconButton(
                  tooltip: _period == ReportPeriod.year ? '다음 해' : '다음 달',
                  onPressed: _loading || !_canGoForward ? null : () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const StatusView.loading(message: '리포트를 만드는 중이에요')
                  : _error != null
                  ? StatusView.error(message: _error!, onRetry: _load)
                  : report == null || report.isEmpty
                  ? StatusView.empty(
                      icon: Icons.directions_run,
                      message: '이 기간에는 아직 러닝 기록이 없어요.\n한 번 달리면 리포트가 만들어져요!',
                    )
                  : PageView(
                      key: const ValueKey('report-pages'),
                      controller: _pages,
                      onPageChanged: (page) => setState(() => _page = page),
                      children: [
                        for (final card in cards)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: card,
                          ),
                      ],
                    ),
            ),
            if (cards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? const Color(0xFF3182F6)
                              : const Color(0x333182F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(RunningReport report) {
    final km = report.kilometers;
    final diff = (report.distanceMeters - report.previousDistanceMeters) / 1000;
    final marathons = km / 42.195;
    final best = report.bestBucket;
    final hours = report.durationSeconds ~/ 3600;
    final minutes = (report.durationSeconds % 3600) ~/ 60;
    final yearly = report.period == ReportPeriod.year;
    return [
      _ReportCard(
        key: const ValueKey('report-intro'),
        colors: const [Color(0xFF3182F6), Color(0xFF7C5CFF)],
        outfit: widget.outfit,
        cheer: 1,
        eyebrow: yearly ? '연말 결산' : '월간 리포트',
        title: yearly ? '${report.title} 나의 러닝' : '${report.title}의 나의 러닝',
        body: '${yearly ? '한 해' : '한 달'} 동안 달린 이야기를 넘겨 보세요 →',
      ),
      _ReportCard(
        key: const ValueKey('report-distance'),
        colors: const [Color(0xFF0FA57A), Color(0xFF3182F6)],
        outfit: widget.outfit,
        eyebrow: '총 거리',
        big: '${km.toStringAsFixed(1)} km',
        body: [
          if (marathons >= 1)
            '마라톤 풀코스 ${marathons.toStringAsFixed(1)}번 거리예요!'
          else
            '하프 마라톤의 ${(km / 21.0975 * 100).round()}%만큼 달렸어요.',
          if (report.previousDistanceMeters > 0)
            '${report.previousTitle}보다 ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}km',
        ].join('\n'),
      ),
      _ReportCard(
        key: const ValueKey('report-steady'),
        colors: const [Color(0xFFFF8A3D), Color(0xFFF65A8E)],
        outfit: widget.outfit,
        eyebrow: '꾸준함',
        big: '${report.runs}번',
        body:
            '${report.activeDays}일 동안 달렸어요\n모두 ${hours > 0 ? '$hours시간 ' : ''}$minutes분을 달렸어요',
      ),
      _ReportCard(
        key: const ValueKey('report-chart'),
        colors: const [Color(0xFF1E2A5A), Color(0xFF3E4FA8)],
        eyebrow: yearly ? '달마다 달린 거리' : '주마다 달린 거리',
        title: best == null
            ? null
            : '가장 많이 달린 ${yearly ? '달' : '주'}: ${report.bucketLabel(best)}',
        child: _Bars(report: report),
      ),
      _ReportCard(
        key: const ValueKey('report-best'),
        colors: const [Color(0xFF7C5CFF), Color(0xFFB04BD8)],
        outfit: widget.outfit,
        cheer: 0.6,
        eyebrow: '나의 최고 기록',
        title: report.longestMeters == null
            ? null
            : '가장 멀리 ${(report.longestMeters! / 1000).toStringAsFixed(2)}km',
        body: [
          if (report.longestAt case final at?) '${at.month}월 ${at.day}일에 달렸어요',
          if (report.fastestPaceSeconds case final pace?)
            '가장 빠른 페이스 ${formatPaceDuration(Duration(seconds: pace))}/km',
        ].join('\n'),
      ),
      _ReportCard(
        key: const ValueKey('report-style'),
        colors: const [Color(0xFFFFB020), Color(0xFFFF7A1A)],
        outfit: widget.outfit,
        eyebrow: '나의 러닝 스타일',
        title: _timeTitle(report.favoriteTime),
        body: [
          if (report.favoriteWeekday case final day?)
            '${_weekday(day)}에 가장 많이 달렸어요',
          if (report.companions > 0) '친구 ${report.companions}명과 함께 달렸어요',
        ].join('\n'),
      ),
      _ReportCard(
        key: const ValueKey('report-share'),
        colors: const [Color(0xFF3182F6), Color(0xFF1B64DA)],
        eyebrow: '한눈에 보기',
        child: Column(
          children: [
            Expanded(
              // SNS에 올리기 좋은 4:5 비율로 이미지를 만듭니다.
              child: Center(
                // 공유 이미지는 글씨 크기와 관계없이 같은 디자인(320×400)으로 그리고
                // 화면에서는 칸에 맞춰 줄여서 보여 줍니다.
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _shareCard,
                    child: MediaQuery.withNoTextScaling(
                      child: SizedBox(
                        width: 320,
                        height: 400,
                        child: _SummaryCard(
                          report: report,
                          outfit: widget.outfit,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: _shareButton,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B64DA),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(_sharing ? '이미지를 만드는 중…' : '리포트 공유하기'),
            ),
          ],
        ),
      ),
    ];
  }

  static String _weekday(int day) => const [
    '월요일',
    '화요일',
    '수요일',
    '목요일',
    '금요일',
    '토요일',
    '일요일',
  ][(day - 1).clamp(0, 6)];

  static String? _timeTitle(String? time) => switch (time) {
    'morning' => '☀️ 아침형 러너',
    'afternoon' => '🌤️ 한낮의 러너',
    'evening' => '🌇 퇴근길 러너',
    'night' => '🌙 밤하늘 러너',
    _ => null,
  };
}

/// 리포트 카드 한 장입니다. 그라데이션 위에 글과 (있으면) 내 캐릭터를 보여 줍니다.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.colors,
    required this.eyebrow,
    this.title,
    this.big,
    this.body,
    this.outfit,
    this.cheer = 0,
    this.child,
    super.key,
  });

  final List<Color> colors;
  final String eyebrow;
  final String? title;
  final String? big;
  final String? body;
  final CharacterOutfit? outfit;
  final double cheer;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final texts = <Widget>[
              Text(
                eyebrow,
                style: const TextStyle(
                  color: Color(0xD9FFFFFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (title case final title?) ...[
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 26,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              if (big case final big?) ...[
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    big,
                    style: const TextStyle(
                      color: white,
                      fontSize: 54,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              if (body case final body? when body.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ];
            final art =
                child ??
                (outfit == null
                    ? const SizedBox.shrink()
                    : ExcludeSemantics(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: RunnerCharacterPainter(
                            yaw: -0.35,
                            outfit: outfit!,
                            cheer: cheer,
                          ),
                        ),
                      ));
            // 아주 큰 글씨나 좁은 화면에서는 글을 위아래로 넘겨 보고 그림은 고정 높이로 둡니다.
            final roomy =
                MediaQuery.textScalerOf(context).scale(16) <= 24 &&
                constraints.maxHeight >= 420;
            if (!roomy) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...texts,
                    const SizedBox(height: 12),
                    SizedBox(height: 220, child: art),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...texts,
                const SizedBox(height: 12),
                Expanded(child: art),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 달(또는 주차)마다 달린 거리 막대입니다. 가장 많이 달린 칸은 노란색입니다.
class _Bars extends StatelessWidget {
  const _Bars({required this.report});

  final RunningReport report;

  @override
  Widget build(BuildContext context) {
    final values = report.buckets;
    final top = values.fold<int>(1, (a, b) => b > a ? b : a);
    final best = report.bestBucket;
    return Semantics(
      label: [
        for (var i = 0; i < values.length; i++)
          '${report.bucketLabel(i + 1)} ${(values[i] / 1000).toStringAsFixed(1)}km',
      ].join(', '),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: (values[i] / top).clamp(0.02, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: best == i + 1
                                  ? const Color(0xFFFFD43B)
                                  : const Color(0x99FFFFFF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const SizedBox(width: double.infinity),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        report.period == ReportPeriod.year
                            ? '${i + 1}'
                            : '${i + 1}주',
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 공유 이미지로 쓰는 요약 카드입니다.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report, required this.outfit});

  final RunningReport report;
  final CharacterOutfit outfit;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('총 거리', '${report.kilometers.toStringAsFixed(1)}km'),
      ('달린 횟수', '${report.runs}번'),
      ('달린 날', '${report.activeDays}일'),
      if (report.longestMeters case final meters?)
        ('최장 거리', '${(meters / 1000).toStringAsFixed(1)}km'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    report.period == ReportPeriod.year
                        ? '${report.title} 러닝 결산'
                        : '${report.starts.year}년 ${report.title} 러닝',
                    style: const TextStyle(
                      color: Color(0xFF191F28),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final (label, value) in stats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Color(0xFF8B95A1),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Color(0xFF191F28),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    '뜀터',
                    style: TextStyle(
                      color: Color(0xFF3182F6),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: RunnerCharacterPainter(
                    yaw: -0.4,
                    outfit: outfit,
                    cheer: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
