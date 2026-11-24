import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/share_edits.dart';
import '../models/share_layout.dart';
import '../models/share_route.dart';
import '../models/share_sticker_alignment.dart';

typedef EditedShare = ({ShareEdits edits, ShareRoute? route});

class ShareStickerEditor extends StatefulWidget {
  const ShareStickerEditor({
    required this.layout,
    required this.imageHeight,
    required this.isOwner,
    required this.paint,
    required this.loadRoute,
    required this.loadCadence,
    this.title = '직접 수정',
    this.initial,
    this.heartRate,
    this.ownerChanges,
    super.key,
  });

  final ShareLayout layout;
  final double imageHeight;
  final bool Function() isOwner;
  final void Function(Canvas, EditedShare) paint;
  final Future<ShareRoute?> Function(BuildContext) loadRoute;
  final Future<int?> Function(bool Function()) loadCadence;
  final String title;
  final EditedShare? initial;
  final int? heartRate;
  final Stream<Object?>? ownerChanges;

  @override
  State<ShareStickerEditor> createState() => _ShareStickerEditorState();
}

class _ShareStickerEditorState extends State<ShareStickerEditor> {
  late final _visible = <ShareSticker>{
    ...?widget.initial?.edits.visible,
    if (widget.initial == null) ...ShareEdits.templateMetrics,
  };
  late final _placements = <ShareSticker, StickerPlacement>{
    ...?widget.initial?.edits.placements,
  };
  late var _route = widget.initial?.route;
  late var _cadence = widget.initial?.edits.cadence;
  late final _heartRate = widget.initial?.edits.heartRate ?? widget.heartRate;
  ShareSticker? _selected;
  StreamSubscription<Object?>? _ownerSubscription;
  bool _busy = false;
  bool _locked = false;
  Offset _gestureCenter = Offset.zero;
  Offset _gestureStart = Offset.zero;
  double _gestureScale = 1;
  ({double? column, double? row}) _guides = (column: null, row: null);

  bool get _canEdit => mounted && !_locked && widget.isOwner();
  Size get _design => Size(1080, widget.imageHeight);

  EditedShare get _draft => (
    edits: ShareEdits(
      visible: _visible,
      useTemplatePlacement: widget.initial?.edits.useTemplatePlacement ?? false,
      placements: _placements,
      cadence: _cadence,
      heartRate: _heartRate,
    ),
    route: _visible.contains(ShareSticker.route) ? _route : null,
  );

  @override
  void initState() {
    super.initState();
    _ownerSubscription = widget.ownerChanges?.listen((_) {
      if (!mounted || widget.isOwner()) return;
      setState(() {
        _locked = true;
        _route = null;
        _cadence = null;
        _visible.clear();
        _placements.clear();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_ownerSubscription?.cancel());
    super.dispose();
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _setVisible(ShareSticker sticker, bool visible) async {
    if (!_canEdit || _busy) return;
    if (!visible) {
      setState(() {
        _visible.remove(sticker);
        if (_selected == sticker) _selected = null;
      });
      return;
    }
    if (sticker == ShareSticker.heart && _heartRate == null) {
      _message('기록 상세의 심박·칼로리에서 건강 데이터를 연결해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (sticker == ShareSticker.route && _route == null) {
        final route = await widget.loadRoute(context);
        if (!_canEdit || route == null) return;
        if (route.isEmpty) {
          _message('선으로 표시할 이동 경로가 부족합니다.');
          return;
        }
        _route = route;
      }
      if (sticker == ShareSticker.cadence && _cadence == null) {
        final cadence = await widget.loadCadence(() => _canEdit);
        if (!_canEdit) return;
        if (cadence == null) {
          _message('걸음 데이터가 없습니다. 건강 앱 권한과 기기 동기화를 확인해 주세요.');
          return;
        }
        _cadence = cadence;
      }
      setState(() {
        _visible.add(sticker);
        if (sticker == ShareSticker.cadence || sticker == ShareSticker.heart) {
          _placements.putIfAbsent(
            sticker,
            () => (
              center: Offset(.5, sticker == ShareSticker.heart ? .79 : .9),
              scale: 1,
            ),
          );
        }
        _selected = sticker;
      });
    } catch (_) {
      if (_canEdit) {
        _message(
          sticker == ShareSticker.route
              ? '이동 경로를 불러오지 못했습니다.'
              : '걸음 데이터를 불러오지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _place(
    ShareSticker sticker,
    Rect original,
    Offset center,
    double scale, {
    double? snapTolerance,
  }) {
    if (!_canEdit || _busy) return;
    final maxScale = math.min(
      _design.width / original.width,
      _design.height / original.height,
    );
    final boundedScale = scale.clamp(.25, math.min(2.5, maxScale));
    final halfWidth = (original.width * boundedScale / 2).clamp(
      0.0,
      _design.width / 2,
    );
    final halfHeight = (original.height * boundedScale / 2).clamp(
      0.0,
      _design.height / 2,
    );
    final maxX = _design.width - halfWidth;
    final maxY = _design.height - halfHeight;
    double? column;
    double? row;
    if (snapTolerance != null) {
      final edits = _draft.edits;
      final otherCenters = [
        for (final other in _visible)
          if (other != sticker) _stickerBounds(other, edits).center,
      ];
      column = nearestStickerGuide(
        center.dx,
        otherCenters.map((point) => point.dx),
        minCenter: halfWidth,
        maxCenter: maxX,
        tolerance: snapTolerance,
      );
      row = nearestStickerGuide(
        center.dy,
        otherCenters.map((point) => point.dy),
        minCenter: halfHeight,
        maxCenter: maxY,
        tolerance: snapTolerance,
      );
    }
    setState(() {
      _guides = (column: column, row: row);
      _placements[sticker] = (
        center: Offset(
          (column ?? center.dx.clamp(halfWidth, maxX)) / _design.width,
          (row ?? center.dy.clamp(halfHeight, maxY)) / _design.height,
        ),
        scale: boundedScale.toDouble(),
      );
    });
  }

  Rect _stickerBounds(ShareSticker sticker, ShareEdits edits) =>
      edits.boundsFor(
        sticker,
        edits.originalBounds(sticker, widget.layout, _design.height),
        _design.height,
      );

  void _clearGuides() {
    if (_guides.column == null && _guides.row == null) return;
    setState(() => _guides = (column: null, row: null));
  }

  void _resize(double multiplier) {
    final sticker = _selected;
    if (sticker == null) return;
    final edits = _draft.edits;
    final base = edits.originalBounds(sticker, widget.layout, _design.height);
    final current = edits.boundsFor(sticker, base, _design.height);
    _place(
      sticker,
      base,
      current.center,
      current.width / base.width * multiplier,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canEdit) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('로그인 상태를 확인해 주세요.')),
      );
    }
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, draft),
            child: const Text('적용'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _design.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          _canvas(draft, constraints.maxWidth / _design.width),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Expanded(child: Text('켜고 끌 항목을 선택하고, 사진에서 드래그해 옮기세요.')),
                  IconButton(
                    tooltip: '작게',
                    onPressed: _selected == null || _busy
                        ? null
                        : () => _resize(.85),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    tooltip: '크게',
                    onPressed: _selected == null || _busy
                        ? null
                        : () => _resize(1.18),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final sticker in ShareSticker.values)
                    Tooltip(
                      message: sticker == ShareSticker.cadence
                          ? '일시정지를 포함한 기록 구간의 분당 평균 걸음 수'
                          : sticker.label,
                      child: FilterChip(
                        label: Text(sticker.label),
                        selected: _visible.contains(sticker),
                        onSelected: _busy
                            ? null
                            : (visible) => _setVisible(sticker, visible),
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

  Widget _canvas(EditedShare draft, double ratio) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => setState(() => _selected = null),
          child: CustomPaint(
            painter: _StickerPreview(
              (canvas) => widget.paint(canvas, draft),
              ratio,
            ),
          ),
        ),
        for (final sticker in _visible) _hitTarget(sticker, draft.edits, ratio),
        if (_guides.column case final column?)
          Positioned(
            left: column * ratio,
            top: 0,
            bottom: 0,
            child: const IgnorePointer(
              child: ColoredBox(
                color: Color(0xFF3182F6),
                child: SizedBox(width: 1),
              ),
            ),
          ),
        if (_guides.row case final row?)
          Positioned(
            top: row * ratio,
            left: 0,
            right: 0,
            child: const IgnorePointer(
              child: ColoredBox(
                color: Color(0xFF3182F6),
                child: SizedBox(height: 1),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _hitTarget(ShareSticker sticker, ShareEdits edits, double ratio) {
    final original = edits.originalBounds(
      sticker,
      widget.layout,
      _design.height,
    );
    final bounds = edits.boundsFor(sticker, original, _design.height);
    final selected = _selected == sticker;
    return Positioned.fromRect(
      rect: Rect.fromLTRB(
        bounds.left * ratio,
        bounds.top * ratio,
        bounds.right * ratio,
        bounds.bottom * ratio,
      ),
      child: Semantics(
        label: '${sticker.label} 스티커',
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : () => setState(() => _selected = sticker),
          onScaleStart: _busy
              ? null
              : (details) {
                  _gestureStart = details.focalPoint;
                  _gestureCenter = bounds.center;
                  _gestureScale = bounds.width / original.width;
                  setState(() => _selected = sticker);
                },
          onScaleUpdate: _busy
              ? null
              : (details) => _place(
                  sticker,
                  original,
                  _gestureCenter + (details.focalPoint - _gestureStart) / ratio,
                  _gestureScale * details.scale,
                  // 확대율과 관계없이 화면에서 같은 거리 안에 들어오면 맞춥니다.
                  snapTolerance: details.pointerCount == 1 ? 8 / ratio : null,
                ),
          onScaleEnd: (_) => _clearGuides(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(color: const Color(0xFF3182F6), width: 2)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPreview extends CustomPainter {
  const _StickerPreview(this.draw, this.ratio);
  final void Function(Canvas) draw;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(ratio);
    draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StickerPreview oldDelegate) => true;
}
