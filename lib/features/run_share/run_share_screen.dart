import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../run_history/models/run_record.dart';
import '../run_history/models/run_route.dart';
import 'data/run_share_service.dart';
import 'data/share_image_renderer.dart';
import 'data/share_photo_service.dart';
import 'models/share_route.dart';
import 'models/share_layout.dart';
import 'widgets/share_text_color_control.dart';

class RunShareScreen extends StatefulWidget {
  const RunShareScreen({
    required this.record,
    required this.isCurrentOwner,
    required this.loadRoute,
    this.shareService,
    this.renderer,
    this.ownerChanges,
    this.photoService,
    super.key,
  });
  final RunRecord record;
  final bool Function() isCurrentOwner;
  final Future<RunRoute> Function() loadRoute;
  final RunShareService? shareService;
  final ShareImageRenderer? renderer;
  final Stream<Object?>? ownerChanges;
  final SharePhotoService? photoService;
  @override
  State<RunShareScreen> createState() => _RunShareScreenState();
}

class _RunShareScreenState extends State<RunShareScreen> {
  Uint8List? _png;
  ShareRoute? _route;
  ui.Image? _photo;
  bool _dark = false;
  bool _photoOverlay = false;
  Color? _textColor;
  ShareLayout _layout = ShareLayout.centered;
  bool _includeRoute = false;
  bool _busy = false;
  bool _confirming = false;
  StreamSubscription<Object?>? _ownerSubscription;
  String? _error;
  final _shareButton = GlobalKey();
  final _scaffold = GlobalKey<ScaffoldState>();
  double _imageHeight = 1920;
  late final _renderer = widget.renderer ?? ShareImageRenderer();
  late final _service = widget.shareService ?? PlatformRunShareService();
  late final _photos = widget.photoService ?? GallerySharePhotoService();

  bool get _darkPreview => _photo == null
      ? _dark
      : (_textColor ?? Colors.white).computeLuminance() > .179;

  @override
  void initState() {
    super.initState();
    _ownerSubscription = widget.ownerChanges?.listen((_) {
      if (!mounted) return;
      setState(() {
        if (!widget.isCurrentOwner()) {
          _png = null;
          _route = null;
          _photo?.dispose();
          _photo = null;
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screen = MediaQuery.sizeOf(context);
    final height = (1080 * screen.longestSide / screen.shortestSide)
        .clamp(1512.0, 3240.0)
        .roundToDouble();
    if (_png == null || height != _imageHeight) {
      _imageHeight = height;
      unawaited(_render());
    }
  }

  @override
  void dispose() {
    unawaited(_ownerSubscription?.cancel());
    _photo?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    if (_busy || !widget.isCurrentOwner()) return;
    final height = _imageHeight;
    setState(() {
      _busy = true;
      _error = null;
      _png = null;
    });
    try {
      final bytes = await _renderer.render(
        widget.record,
        route: _includeRoute ? _route : null,
        background: _photo,
        dark: _dark,
        height: height,
        textColor: _textColor,
        photoOverlay: _photoOverlay,
        layout: _layout,
      );
      if (mounted && widget.isCurrentOwner() && height == _imageHeight) {
        setState(() => _png = bytes);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '공유 이미지를 만들지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && height != _imageHeight) unawaited(_render());
  }

  Future<void> _selectPhoto() async {
    if (_busy || !widget.isCurrentOwner()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var changed = false;
    try {
      final photo = await _photos.pick();
      if (!mounted || !widget.isCurrentOwner()) {
        photo?.dispose();
        return;
      }
      if (photo == null) return;
      _photo?.dispose();
      setState(() => _photo = photo);
      changed = true;
    } catch (error) {
      if (mounted && widget.isCurrentOwner()) {
        setState(
          () => _error = error is SharePhotoException
              ? error.message
              : '사진을 불러오지 못했습니다. 다른 사진을 선택해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (changed) await _render();
  }

  Future<void> _selectDefault(bool dark) async {
    if (_busy || !widget.isCurrentOwner()) return;
    _photo?.dispose();
    setState(() {
      _photo = null;
      _dark = dark;
    });
    await _render();
  }

  Future<void> _selectTextColor(Color? color) async {
    if (_busy || !widget.isCurrentOwner()) return;
    setState(() => _textColor = color);
    await _render();
  }

  Future<void> _selectPhotoOverlay(bool enabled) async {
    if (_busy || _photo == null || !widget.isCurrentOwner()) return;
    setState(() => _photoOverlay = enabled);
    await _render();
  }

  Future<void> _selectRoute(bool selected) async {
    if (_busy || !widget.isCurrentOwner()) return;
    if (!selected) {
      setState(() => _includeRoute = false);
      await _render();
      return;
    }
    setState(() {
      _busy = true;
      _confirming = true;
    });
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('경로 포함'),
        content: const Text(
          '지도·주소 없이 달린 경로의 선 모양만 표시합니다. 경로 모양에서도 위치를 유추할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('포함'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirming = false;
    });
    if (consent != true || !mounted || !widget.isCurrentOwner()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _route ??= ShareRoute.shape(await widget.loadRoute());
      if (!mounted || !widget.isCurrentOwner()) return;
      if (_route!.isEmpty) {
        setState(() => _error = '선으로 표시할 이동 경로가 부족합니다.');
        return;
      }
      setState(() => _includeRoute = true);
    } catch (_) {
      if (mounted) setState(() => _error = '경로를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_includeRoute) await _render();
  }

  Future<void> _share() async {
    if (_busy || _png == null || !widget.isCurrentOwner()) return;
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.share(
        _png!,
        origin,
        isCurrentOwner: widget.isCurrentOwner,
      );
      if (mounted && widget.isCurrentOwner()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (result) {
              RunShareResult.handedOff => '공유 앱으로 전달했습니다.',
              RunShareResult.cancelled => '공유를 취소했습니다.',
              RunShareResult.unknown => '공유 결과는 선택한 앱에서 확인해 주세요.',
            }),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '공유창을 열지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _darkPreview
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: Scaffold(
      key: _scaffold,
      backgroundColor: _darkPreview
          ? const Color(0xFF22282C)
          : const Color(0xFFF8FAFC),
      endDrawer: Drawer(
        child: SafeArea(
          child: !widget.isCurrentOwner()
              ? const Center(child: Text('로그인 상태를 확인해 주세요.'))
              : _options(context),
        ),
      ),
      body: !widget.isCurrentOwner()
          ? const Center(child: Text('로그인 상태를 확인해 주세요.'))
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_png != null)
                  Image.memory(
                    _png!,
                    fit: BoxFit.contain,
                    gaplessPlayback: false,
                    semanticLabel: '공유 이미지 미리보기',
                  ),
                if (_busy && !_confirming)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          _tool(
                            '뒤로',
                            Icons.arrow_back,
                            () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          _tool(
                            '공유 설정',
                            Icons.tune,
                            () => _scaffold.currentState?.openEndDrawer(),
                          ),
                          const SizedBox(width: 8),
                          _tool(
                            '공유',
                            Icons.ios_share,
                            _busy || _png == null ? null : _share,
                            key: _shareButton,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null && !_busy)
                  Positioned(
                    bottom: 0,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      top: false,
                      child: Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!),
                              if (_png == null)
                                TextButton.icon(
                                  onPressed: _render,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('이미지 다시 만들기'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );

  Widget _tool(
    String tooltip,
    IconData icon,
    VoidCallback? action, {
    Key? key,
  }) {
    final onDark = _darkPreview;
    return IconButton.filledTonal(
      key: key,
      tooltip: tooltip,
      onPressed: action,
      style: IconButton.styleFrom(
        backgroundColor: onDark
            ? const Color(0xB3000000)
            : const Color(0xEFFFFFFF),
        foregroundColor: onDark ? Colors.white : const Color(0xFF202428),
      ),
      icon: Icon(icon),
    );
  }

  Widget _options(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '공유 설정',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: '설정 닫기',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      if (_busy && !_confirming)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('배경'),
            IconButton(
              tooltip: '밝은 기본 배경',
              isSelected: _photo == null && !_dark,
              onPressed: _busy ? null : () => _selectDefault(false),
              icon: const Icon(Icons.light_mode_outlined),
              selectedIcon: const Icon(Icons.light_mode),
            ),
            IconButton(
              tooltip: '어두운 기본 배경',
              isSelected: _photo == null && _dark,
              onPressed: _busy ? null : () => _selectDefault(true),
              icon: const Icon(Icons.dark_mode_outlined),
              selectedIcon: const Icon(Icons.dark_mode),
            ),
            IconButton(
              tooltip: '갤러리 사진 선택',
              isSelected: _photo != null,
              onPressed: _busy ? null : _selectPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library),
            ),
          ],
        ),
      ),
      if (_photo != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('사진 배경 덮개'),
          value: _photoOverlay,
          onChanged: _busy ? null : _selectPhotoOverlay,
        ),
      const SizedBox(height: 16),
      const Text('공유 템플릿'),
      const SizedBox(height: 8),
      SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ShareLayout.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final layout = ShareLayout.values[index];
            return ChoiceChip(
              label: SizedBox(
                width: 108,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 88,
                      child: CustomPaint(painter: _TemplatePreview(layout)),
                    ),
                    const SizedBox(height: 8),
                    Text(layout.label),
                  ],
                ),
              ),
              tooltip: layout.description,
              showCheckmark: false,
              selected: _layout == layout,
              onSelected: _busy
                  ? null
                  : (selected) async {
                      if (!selected || !widget.isCurrentOwner()) return;
                      setState(() => _layout = layout);
                      await _render();
                    },
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      ShareTextColorControl(
        color: _textColor,
        automaticColor: _dark || _photo != null
            ? Colors.white
            : const Color(0xFF202428),
        enabled: !_busy,
        onChanged: _selectTextColor,
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('경로 포함'),
        value: _includeRoute,
        onChanged: _busy ? null : _selectRoute,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_png == null && !_busy)
        TextButton.icon(
          onPressed: _render,
          icon: const Icon(Icons.refresh),
          label: const Text('이미지 다시 만들기'),
        ),
    ],
  );
}

class _TemplatePreview extends CustomPainter {
  const _TemplatePreview(this.layout);
  final ShareLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = const Color(0xFFF8FAFC),
    );
    canvas.save();
    canvas.scale(size.width / 1080, size.height / 1920);
    final composition = layout.compose(1920, hasRoute: true);
    if (composition.panel case final panel?) {
      canvas.drawRect(panel, Paint()..color = const Color(0xFFE1E6EA));
    }
    if (composition.route case final bounds?) {
      final side = bounds.shortestSide;
      final center = bounds.center;
      final path = Path()
        ..moveTo(center.dx - side * .35, center.dy + side * .3)
        ..lineTo(center.dx - side * .2, center.dy - side * .3)
        ..lineTo(center.dx + side * .35, center.dy - side * .1)
        ..lineTo(center.dx + side * .15, center.dy + side * .3);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF16836F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22,
      );
    }
    for (final slot in composition.texts) {
      final width = slot.rect.width * (slot.bold ? .78 : .45);
      final x =
          slot.rect.left + (slot.centered ? (slot.rect.width - width) / 2 : 0);
      canvas.drawRect(
        Rect.fromLTWH(x, slot.rect.top, width, slot.size * .8),
        Paint()
          ..color = slot.isLabel
              ? const Color(0xFF929CA3)
              : const Color(0xFF202428),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TemplatePreview oldDelegate) =>
      oldDelegate.layout != layout;
}
