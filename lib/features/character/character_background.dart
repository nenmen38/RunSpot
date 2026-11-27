import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../board/data/board_photo_service.dart';
import '../settings/appearance/app_appearance.dart';
import 'runner_character.dart';

/// 내 러너 캐릭터 뒤에 깔 배경 사진 보관함입니다.
/// 고른 사진은 이 폰에만 저장되고(서버로 올리지 않음) 프로필·꾸미기 창·프로필 카드에 쓰입니다.
/// 친구에게는 보이지 않습니다. 사진은 촬영 위치 등 정보를 지운 JPEG로 다시 저장합니다.
class CharacterBackground extends ChangeNotifier {
  CharacterBackground({
    AppearanceStore? store,
    Future<Directory> Function()? directory,
  }) : _given = store,
       _directory = directory ?? _defaultDirectory;

  static final instance = CharacterBackground();

  /// 보관함에 둘 수 있는 사진 수입니다. 넘으면 가장 오래된 사진부터 지웁니다.
  static const maxPhotos = 12;
  static const _key = 'character.background';

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/character_backgrounds',
  );

  final AppearanceStore? _given;
  final Future<Directory> Function() _directory;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  Directory? _dir;

  /// 보관함의 사진 파일 이름입니다(오래된 것이 앞).
  List<String> names = const [];

  /// 지금 배경으로 쓰는 사진입니다. null이면 기본 운동장 트랙입니다.
  String? selected;

  /// 배경으로 쓸 이미지입니다. 기본 트랙이면 null입니다.
  ImageProvider? get provider => switch ((selected, _dir)) {
    (final name?, final dir?) => FileImage(File('${dir.path}/$name')),
    _ => null,
  };

  /// 보관함 사진 하나의 이미지입니다(작게 줄여 읽음).
  ImageProvider thumbnail(String name, {int width = 240}) {
    final dir = _dir;
    if (dir == null) throw StateError('보관함이 아직 열리지 않았어요.');
    return ResizeImage(FileImage(File('${dir.path}/$name')), width: width);
  }

  Future<void> load() async {
    try {
      final dir = _dir = await _directory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final files = [
        for (final entity in await dir.list().toList())
          if (entity is File && entity.path.endsWith('.jpg')) entity,
      ]..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      names = [for (final file in files) file.uri.pathSegments.last];
      final saved = await _store.read(_key);
      selected = saved != null && names.contains(saved) ? saved : null;
      notifyListeners();
    } catch (_) {
      // 보관함을 못 열어도 기본 트랙으로 보여 줍니다.
    }
  }

  /// 갤러리에서 사진을 골라 보관함에 넣고 바로 배경으로 씁니다. 고르지 않으면 null입니다.
  Future<String?> pickAndAdd() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return add(await file.readAsBytes());
  }

  /// 사진을 JPEG로 다시 저장해 보관함에 넣고 배경으로 씁니다.
  Future<String> add(Uint8List bytes) async {
    final dir = _dir ?? await _directory();
    _dir = dir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final jpeg = await encodeBoardPhoto(bytes);
    final name = 'bg_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File('${dir.path}/$name').writeAsBytes(jpeg, flush: true);
    names = [...names, name];
    // 가득 차면 쓰고 있지 않은 가장 오래된 사진부터 지웁니다.
    while (names.length > maxPhotos) {
      final oldest = names.firstWhere((n) => n != name, orElse: () => name);
      await _delete(oldest);
      names = [
        for (final n in names)
          if (n != oldest) n,
      ];
    }
    await select(name);
    return name;
  }

  /// 배경을 고릅니다. null이면 기본 운동장 트랙으로 돌아갑니다.
  Future<void> select(String? name) async {
    if (name != null && !names.contains(name)) return;
    selected = name;
    notifyListeners();
    try {
      await _store.write(_key, name ?? '');
    } catch (_) {}
  }

  Future<void> remove(String name) async {
    if (!names.contains(name)) return;
    await _delete(name);
    names = [
      for (final n in names)
        if (n != name) n,
    ];
    if (selected == name) {
      selected = null;
      try {
        await _store.write(_key, '');
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _delete(String name) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
      await FileImage(file).evict();
    } catch (_) {}
  }
}

/// 프로필 헤더의 사진 아이콘입니다. 누르면 배경 사진 보관함이 열립니다.
class CharacterBackgroundButton extends StatelessWidget {
  const CharacterBackgroundButton({this.background, super.key});

  final CharacterBackground? background;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    key: const ValueKey('character-background-button'),
    tooltip: '배경 사진',
    visualDensity: VisualDensity.compact,
    onPressed: () => showCharacterBackgroundSheet(
      context,
      background: background ?? CharacterBackground.instance,
    ),
    icon: const Icon(Icons.photo_library_outlined, size: 20),
  );
}

Future<void> showCharacterBackgroundSheet(
  BuildContext context, {
  CharacterBackground? background,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) =>
      _BackgroundSheet(background: background ?? CharacterBackground.instance),
);

class _BackgroundSheet extends StatefulWidget {
  const _BackgroundSheet({required this.background});

  final CharacterBackground background;

  @override
  State<_BackgroundSheet> createState() => _BackgroundSheetState();
}

class _BackgroundSheetState extends State<_BackgroundSheet> {
  bool _busy = false;
  String? _message;

  Future<void> _add() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    String? message;
    try {
      await widget.background.pickAndAdd();
    } on BoardPhotoException catch (error) {
      message = error.message;
    } catch (_) {
      message = '사진을 불러오지 못했어요. 사진 접근 권한을 확인해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.background,
      builder: (context, _) {
        final bg = widget.background;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '배경 사진',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '내 러너 뒤에 깔 사진을 골라요. 이 폰에만 저장되고 친구에게는 보이지 않아요. '
                '보관함에는 ${CharacterBackground.maxPhotos}장까지 담아요.',
                style: text.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 14),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                children: [
                  _Tile(
                    key: const ValueKey('background-default'),
                    selected: bg.selected == null,
                    label: '기본 트랙',
                    onTap: () => bg.select(null),
                    child: const CustomPaint(painter: TrackBackgroundPainter()),
                  ),
                  for (final name in bg.names.reversed)
                    _Tile(
                      key: ValueKey('background-$name'),
                      selected: bg.selected == name,
                      label: bg.selected == name ? '사용 중' : '',
                      onTap: () => bg.select(name),
                      onDelete: () => bg.remove(name),
                      child: Image(
                        image: bg.thumbnail(name),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  _AddTile(
                    key: const ValueKey('background-add'),
                    busy: _busy,
                    onTap: _add,
                  ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _message!,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
    this.onDelete,
    super.key,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label.isEmpty ? '배경 사진' : label,
    child: Stack(
      fit: StackFit.expand,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black12,
                width: selected ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
        if (selected)
          Positioned(
            left: 6,
            top: 6,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
        if (onDelete != null)
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              tooltip: '보관함에서 지우기',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        if (label.isNotEmpty)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap, super.key});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '사진 추가',
    child: InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_photo_alternate_outlined, size: 28),
                    SizedBox(height: 4),
                    Text(
                      '사진 추가',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
