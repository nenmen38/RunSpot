import '../character/character_outfit.dart';
import '../character/runner_character_card.dart';
import '../monetization/coin_frames.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../run_history/models/run_record.dart';
import '../run_history/models/run_route.dart';
import 'data/run_share_service.dart';
import 'data/share_cadence.dart';
import 'data/share_image_renderer.dart';
import 'data/share_photo_service.dart';
import 'data/share_template_store.dart';
import 'models/share_route.dart';
import 'models/share_layout.dart';
import 'models/share_edits.dart';
import 'models/share_highlights.dart';
import 'widgets/share_highlight_picker.dart';
import 'models/share_card_catalog.dart';
import 'widgets/share_sticker_editor.dart';
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
    this.averageHeartRate,
    this.loadCadence,
    this.wallet,
    this.loadHighlights,
    this.templateStore,
    super.key,
  });
  final WalletController? wallet;
  final ShareTemplateStore? templateStore;
  final Future<ShareHighlightChoices> Function()? loadHighlights;
  final RunRecord record;
  final bool Function() isCurrentOwner;
  final Future<RunRoute> Function() loadRoute;
  final RunShareService? shareService;
  final ShareImageRenderer? renderer;
  final Stream<Object?>? ownerChanges;
  final SharePhotoService? photoService;
  final double? averageHeartRate;
  final Future<int?> Function(bool Function())? loadCadence;
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

  /// 내 러너 캐릭터를 카드 오른쪽 아래에 넣을지입니다(지갑이 있으면 기본으로 넣음).
  late bool _withCharacter = widget.wallet != null;
  EditedShare? _customDraft;
  final _templateDrafts = <ShareLayout, EditedShare>{};
  bool _customSelected = false;
  List<SavedShareTemplate> _savedTemplates = [];
  SavedShareTemplate? _selectedTemplate;
  EditedShare? _savedDraft;
  bool _templatesReady = false;
  bool _savingTemplate = false;
  ShareHighlights? _highlights;
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

  bool _canUse(ShareLayout layout) =>
      ShareLayout.freeLayouts.contains(layout) ||
      (widget.wallet?.service.isCurrentOwner == true &&
          shareCardLayouts.entries.any(
            (entry) =>
                entry.value == layout &&
                widget.wallet!.wallet?.cosmetics.contains(entry.key) == true,
          ));

  EditedShare? get _activeDraft => _customSelected
      ? _customDraft
      : _selectedTemplate != null
      ? _savedDraft
      : _templateDrafts[_layout];

  bool get _darkPreview => _photo == null
      ? (_dark || (!_customSelected && _layout == ShareLayout.nightCard))
      : (_textColor ?? Colors.white).computeLuminance() > .179;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplates());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isCurrentOwner()) {
        unawaited(widget.wallet?.refresh());
      }
    });
    _ownerSubscription = widget.ownerChanges?.listen((_) {
      if (!mounted) return;
      setState(() {
        if (!widget.isCurrentOwner()) {
          _png = null;
          _route = null;
          _customDraft = null;
          _templateDrafts.clear();
          _savedTemplates = [];
          _selectedTemplate = null;
          _savedDraft = null;
          _highlights = null;
          _customSelected = false;
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

  Future<void> _render({bool keepPreview = false}) async {
    if (_busy || !widget.isCurrentOwner()) return;
    if (!_customSelected && !_canUse(_layout)) {
      _layout = ShareLayout.centered;
      _selectedTemplate = null;
      _savedDraft = null;
    }
    final height = _imageHeight;
    final draft = _activeDraft;
    setState(() {
      _busy = true;
      _error = null;
      if (!keepPreview) _png = null;
    });
    try {
      final bytes = await _renderer.render(
        widget.record,
        route: draft == null ? (_includeRoute ? _route : null) : draft.route,
        edits: draft?.edits,
        highlights: _highlights,
        character: _withCharacter && widget.wallet != null
            ? characterOutfit(wornCharacterItems(widget.wallet!.wallet).values)
            : null,
        background: _photo,
        dark: _dark,
        height: height,
        textColor: _textColor,
        photoOverlay: _photoOverlay,
        layout: _customSelected ? ShareLayout.centered : _layout,
      );
      if (mounted && widget.isCurrentOwner() && height == _imageHeight) {
        setState(() => _png = bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _png = null;
          _error = '공유 이미지를 만들지 못했습니다.';
        });
      }
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

  Future<bool?> _confirmRoute(BuildContext context) => showDialog<bool>(
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

  Future<void> _selectHighlights() async {
    final load = widget.loadHighlights;
    if (load == null || _busy || !widget.isCurrentOwner()) return;
    final selected = await showDialog<ShareHighlights>(
      context: context,
      builder: (_) => ShareHighlightPicker(
        initial: _highlights,
        load: load,
        isCurrentOwner: widget.isCurrentOwner,
      ),
    );
    if (!mounted || selected == null || !widget.isCurrentOwner()) return;
    setState(() => _highlights = selected);
    _scaffold.currentState?.closeEndDrawer();
    await _render();
  }

  Future<void> _edit({required bool custom}) async {
    final layout = custom ? ShareLayout.centered : _layout;
    if (_busy || !widget.isCurrentOwner() || !_canUse(layout)) return;
    final saved = custom ? null : _selectedTemplate;
    final initial = custom
        ? _customDraft
        : (saved == null ? _templateDrafts[layout] : _savedDraft) ??
              (
                edits: ShareEdits(
                  visible: [
                    ...ShareEdits.templateMetrics,
                    if (_includeRoute && _route != null) ShareSticker.route,
                  ],
                  useTemplatePlacement: true,
                ),
                route: _includeRoute ? _route : null,
              );
    _scaffold.currentState?.closeEndDrawer();
    final height = _imageHeight;
    final photo = _photo?.clone();
    final heart = widget.averageHeartRate;
    final editor = MaterialPageRoute<EditedShare>(
      builder: (_) => ShareStickerEditor(
        layout: layout,
        imageHeight: height,
        isOwner: widget.isCurrentOwner,
        ownerChanges: widget.ownerChanges,
        initial: initial,
        title: custom ? '직접 수정' : '${layout.label} 수정',
        heartRate: heart != null && heart.isFinite && heart > 0
            ? heart.round()
            : null,
        loadRoute: (context) async {
          final consent = await _confirmRoute(context);
          if (!context.mounted || consent != true || !widget.isCurrentOwner()) {
            return null;
          }
          return _route ?? ShareRoute.shape(await widget.loadRoute());
        },
        loadCadence:
            widget.loadCadence ??
            (canRead) => readShareCadence(widget.record, canRead: canRead),
        paint: (canvas, draft) => _renderer.paint(
          canvas,
          widget.record,
          height: height,
          route: draft.route,
          edits: draft.edits,
          highlights: _highlights,
          background: photo,
          dark: _dark,
          textColor: _textColor,
          photoOverlay: _photoOverlay,
          layout: layout,
        ),
      ),
    );
    unawaited(editor.completed.whenComplete(() => photo?.dispose()));
    final result = await Navigator.of(context).push(editor);
    if (!mounted ||
        result == null ||
        !widget.isCurrentOwner() ||
        !_canUse(layout)) {
      return;
    }
    setState(() {
      if (custom) {
        _customDraft = result;
      } else if (saved != null) {
        _savedDraft = result;
      } else {
        _templateDrafts[layout] = result;
      }
      _customSelected = custom;
      if (custom) _selectedTemplate = null;
    });
    await _render();
  }

  Future<void> _loadTemplates() async {
    final store = widget.templateStore;
    if (store == null) return;
    try {
      final templates = await store.load();
      if (!mounted || !widget.isCurrentOwner()) return;
      setState(() {
        _savedTemplates = templates;
        _templatesReady = true;
      });
    } catch (_) {
      if (mounted && widget.isCurrentOwner()) {
        _templateMessage('저장한 템플릿을 불러오지 못했습니다.');
      }
    }
  }

  void _templateMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveTemplate() async {
    final draft = _activeDraft;
    if (draft == null || _savingTemplate || !widget.isCurrentOwner()) return;
    final layout = _customSelected ? ShareLayout.centered : _layout;
    var name = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('내 템플릿으로 저장'),
        content: TextField(
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '템플릿 이름'),
          onChanged: (value) => name = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || !widget.isCurrentOwner()) return;
    if (name.isEmpty || name.length > 24) {
      _templateMessage('템플릿 이름을 1~24자로 입력해 주세요.');
      return;
    }
    final template = SavedShareTemplate(
      id: const Uuid().v4(),
      name: name,
      layout: layout,
      edits: draft.edits,
    );
    if (await _writeTemplates((store) => store.add(template)) && mounted) {
      _templateMessage('내 템플릿에 저장했어요.');
    }
  }

  Future<bool> _writeTemplates(
    Future<List<SavedShareTemplate>> Function(ShareTemplateStore) write,
  ) async {
    final store = widget.templateStore;
    if (store == null ||
        !_templatesReady ||
        _savingTemplate ||
        !widget.isCurrentOwner()) {
      return false;
    }
    setState(() => _savingTemplate = true);
    try {
      final templates = await write(store);
      if (!mounted || !widget.isCurrentOwner()) return false;
      setState(() => _savedTemplates = templates);
      return true;
    } catch (_) {
      if (mounted && widget.isCurrentOwner()) {
        _templateMessage('내 템플릿을 변경하지 못했습니다.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _savingTemplate = false);
    }
  }

  Future<void> _deleteTemplate(SavedShareTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${template.name} 템플릿을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final deleted = await _writeTemplates((store) => store.delete(template.id));
    if (!mounted || !deleted || _selectedTemplate?.id != template.id) return;
    setState(() {
      _selectedTemplate = null;
      _savedDraft = null;
    });
    await _render(keepPreview: true);
  }

  Future<void> _useTemplate(SavedShareTemplate template) async {
    if (_busy || !widget.isCurrentOwner() || !_canUse(template.layout)) return;
    // 새 기록의 경로는 기록마다 사용자가 공유에 동의해야 합니다.
    final edits = template.edits;
    final selectedRoute = _includeRoute ? _route : null;
    final bpm = widget.averageHeartRate;
    int? cadence;
    if (edits.visible.contains(ShareSticker.cadence)) {
      setState(() => _busy = true);
      try {
        cadence =
            await (widget.loadCadence ??
                (canRead) => readShareCadence(widget.record, canRead: canRead))(
              () => mounted && widget.isCurrentOwner(),
            );
      } catch (_) {
        if (mounted && widget.isCurrentOwner()) {
          _templateMessage('이 기록의 케이던스를 불러오지 못했습니다.');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted || !widget.isCurrentOwner()) return;
    setState(() {
      _layout = template.layout;
      _customSelected = false;
      _selectedTemplate = template;
      _savedDraft = (
        edits: ShareEdits(
          visible: [
            for (final sticker in edits.visible)
              if (sticker != ShareSticker.route || selectedRoute != null)
                sticker,
          ],
          placements: edits.placements,
          useTemplatePlacement: edits.useTemplatePlacement,
          heartRate: bpm != null && bpm.isFinite && bpm > 0
              ? bpm.round()
              : null,
          cadence: cadence,
        ),
        route: edits.visible.contains(ShareSticker.route)
            ? selectedRoute
            : null,
      );
    });
    await _render(keepPreview: true);
  }

  Future<void> _selectCharacter(bool selected) async {
    if (_busy || !widget.isCurrentOwner()) return;
    setState(() => _withCharacter = selected);
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
    final consent = await _confirmRoute(context);
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
    if (!_customSelected && !_canUse(_layout)) {
      await _render();
      return;
    }
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
        isCurrentOwner: () =>
            widget.isCurrentOwner() && (_customSelected || _canUse(_layout)),
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
                  SafeArea(
                    top: false,
                    child: Image.memory(
                      _png!,
                      fit: BoxFit.contain,
                      gaplessPlayback: false,
                      semanticLabel: '공유 이미지 미리보기',
                    ),
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
                            '템플릿 수정',
                            Icons.edit_outlined,
                            _busy ? null : () => _edit(custom: _customSelected),
                          ),
                          const SizedBox(width: 8),
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
      if (widget.wallet case final wallet?)
        ListenableBuilder(
          listenable: wallet,
          builder: (_, _) => _templatePicker(),
        )
      else
        _templatePicker(),
      if (widget.loadHighlights != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.military_tech_outlined),
          title: const Text('성과·칭호·업적 넣기'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _selectHighlights,
        ),
      if (widget.wallet != null)
        SwitchListTile(
          key: const ValueKey('share-character'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.emoji_people_outlined),
          title: const Text('내 러너 캐릭터 넣기'),
          value: _withCharacter,
          onChanged: _busy ? null : _selectCharacter,
        ),
      const SizedBox(height: 16),
      if (widget.templateStore != null &&
          (_activeDraft != null || _savedTemplates.isNotEmpty)) ...[
        Text('내 템플릿', style: Theme.of(context).textTheme.titleSmall),
        if (_activeDraft != null)
          TextButton.icon(
            onPressed: _busy || _savingTemplate || !_templatesReady
                ? null
                : _saveTemplate,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('내 템플릿으로 저장'),
          ),
        for (final template in _savedTemplates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            selected: _selectedTemplate?.id == template.id,
            leading: Icon(
              _selectedTemplate?.id == template.id
                  ? Icons.check_circle_outline
                  : Icons.dashboard_outlined,
            ),
            title: Text(template.name),
            subtitle: Text(template.layout.label),
            onTap: _busy || _savingTemplate || !_canUse(template.layout)
                ? null
                : () => _useTemplate(template),
            trailing: IconButton(
              tooltip: '${template.name} 삭제',
              onPressed: _busy || _savingTemplate
                  ? null
                  : () => _deleteTemplate(template),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
      ShareTextColorControl(
        color: _textColor,
        automaticColor: _darkPreview ? Colors.white : const Color(0xFF202428),
        enabled: !_busy,
        onChanged: _selectTextColor,
      ),
      const SizedBox(height: 16),
      if (_activeDraft == null)
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

  Widget _templatePicker() {
    final layouts = [
      ...ShareLayout.freeLayouts,
      ...shareCardLayouts.values.where(_canUse),
    ];
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: layouts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _templateChoice(
              label: '직접 수정',
              description: '표시할 정보와 위치를 직접 선택합니다.',
              preview: const Icon(Icons.dashboard_customize_outlined, size: 36),
              selected: _customSelected,
              onSelected: _busy ? null : (_) => _edit(custom: true),
            );
          }
          final layout = layouts[index - 1];
          return _templateChoice(
            label: layout.label,
            description: layout.description,
            preview: CustomPaint(painter: _TemplatePreview(layout)),
            selected:
                !_customSelected &&
                _selectedTemplate == null &&
                _layout == layout,
            onSelected: _busy
                ? null
                : (selected) async {
                    if (!selected ||
                        !widget.isCurrentOwner() ||
                        !_canUse(layout)) {
                      return;
                    }
                    setState(() {
                      _layout = layout;
                      _customSelected = false;
                      _selectedTemplate = null;
                      _savedDraft = null;
                    });
                    await _render(keepPreview: true);
                  },
          );
        },
      ),
    );
  }

  Widget _templateChoice({
    required String label,
    required String description,
    required Widget preview,
    required bool selected,
    required ValueChanged<bool>? onSelected,
  }) => ChoiceChip(
    label: SizedBox(
      width: 108,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 64, height: 88, child: preview),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    ),
    tooltip: description,
    showCheckmark: false,
    selected: selected,
    onSelected: onSelected,
  );
}

class _TemplatePreview extends CustomPainter {
  const _TemplatePreview(this.layout);
  final ShareLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    final night = layout == ShareLayout.nightCard;
    final minimal = layout == ShareLayout.minimalCard;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()
        ..color = night
            ? const Color(0xFF222A53)
            : minimal
            ? const Color(0xFFF1F4ED)
            : const Color(0xFFF8FAFC),
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
          ..color = night ? const Color(0xFFC1B5FF) : const Color(0xFF16836F)
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
              : night
              ? Colors.white
              : const Color(0xFF202428),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TemplatePreview oldDelegate) =>
      oldDelegate.layout != layout;
}
