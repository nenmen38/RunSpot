import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../shared/theme/app_colors.dart';

/// 기본으로 주는 대화방 배경입니다. 밝은 화면과 어두운 화면에서 각각 다른 색을 씁니다.
enum ChatWallpaperPreset {
  sky(
    '하늘',
    [Color(0xFFDCEBFF), Color(0xFFF4F9FF)],
    [Color(0xFF0F1E33), Color(0xFF17283F)],
  ),
  mint(
    '민트',
    [Color(0xFFD8F5E8), Color(0xFFF2FCF7)],
    [Color(0xFF0E2A22), Color(0xFF14342B)],
  ),
  lime(
    '라임',
    [Color(0xFFEAF9C6), Color(0xFFFAFFEC)],
    [Color(0xFF1C280B), Color(0xFF243311)],
  ),
  peach(
    '피치',
    [Color(0xFFFFE2D3), Color(0xFFFFF4EC)],
    [Color(0xFF33201A), Color(0xFF3B2720)],
  ),
  sunset(
    '노을',
    [Color(0xFFFFDCE8), Color(0xFFFFEFD6)],
    [Color(0xFF361A26), Color(0xFF3A2816)],
  ),
  lavender(
    '라벤더',
    [Color(0xFFE8DEFF), Color(0xFFF8F4FF)],
    [Color(0xFF221B36), Color(0xFF2A2240)],
  ),
  stone(
    '차분한 회색',
    [Color(0xFFE6E8EC), Color(0xFFF6F7F9)],
    [Color(0xFF1A1D22), Color(0xFF23272E)],
  );

  const ChatWallpaperPreset(this.label, this.light, this.dark);

  final String label;
  final List<Color> light;
  final List<Color> dark;

  LinearGradient gradient(Brightness brightness) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: brightness == Brightness.dark ? dark : light,
  );
}

/// 대화방 하나에 고른 배경입니다. 기본 배경([preset]) 또는 내 사진([photo]) 중 하나입니다.
@immutable
class ChatWallpaper {
  const ChatWallpaper.preset(ChatWallpaperPreset this.preset) : photo = null;
  const ChatWallpaper.photo(String this.photo) : preset = null;

  final ChatWallpaperPreset? preset;

  /// 기기에 복사해 둔 사진 파일 경로입니다.
  final String? photo;

  String encode() => photo != null ? 'photo:$photo' : 'preset:${preset!.name}';

  static ChatWallpaper? decode(String? value) {
    if (value == null) return null;
    if (value.startsWith('photo:') && value.length > 6) {
      return ChatWallpaper.photo(value.substring(6));
    }
    if (value.startsWith('preset:')) {
      final name = value.substring(7);
      for (final preset in ChatWallpaperPreset.values) {
        if (preset.name == name) return ChatWallpaper.preset(preset);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper && other.preset == preset && other.photo == photo;

  @override
  int get hashCode => Object.hash(preset, photo);
}

/// 배경 설정을 이 기기에만 저장합니다(카카오톡처럼 서버에 올리지 않습니다).
/// 대화방마다 따로 정할 수 있고, '모든 대화방'에 정한 배경은 따로 정하지 않은 방에 쓰입니다.
class ChatWallpaperStore {
  ChatWallpaperStore({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String? value)? write,
    Future<String> Function(Uint8List bytes)? savePhoto,
    Future<void> Function(String photo)? deletePhoto,
  }) : _read = read ?? ((key) => _prefs.getString(key)),
       _write = write ?? _writePrefs,
       _savePhoto = savePhoto ?? _savePhotoFile,
       _deletePhoto = deletePhoto ?? _deletePhotoFile;

  static final instance = ChatWallpaperStore();
  static final _prefs = SharedPreferencesAsync();

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String? value) _write;
  final Future<String> Function(Uint8List bytes) _savePhoto;
  final Future<void> Function(String photo) _deletePhoto;

  static Future<void> _writePrefs(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  static Future<String> _savePhotoFile(Uint8List bytes) async {
    final folder = Directory(
      path.join(
        (await getApplicationSupportDirectory()).path,
        'chat_wallpapers',
      ),
    );
    await folder.create(recursive: true);
    final file = File(path.join(folder.path, '${const Uuid().v4()}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> _deletePhotoFile(String photo) async {
    try {
      await File(photo).delete();
    } catch (_) {
      // 이미 지워졌으면 그대로 둡니다.
    }
  }

  static const allRooms = '*';
  String _key(String owner, String room) => 'chat-wallpaper:$owner:$room';

  /// 이 방에 정한 배경, 없으면 모든 대화방에 정한 배경을 돌려줍니다.
  Future<ChatWallpaper?> load(String owner, String room) async =>
      ChatWallpaper.decode(await _read(_key(owner, room))) ??
      ChatWallpaper.decode(await _read(_key(owner, allRooms)));

  Future<String> keepPhoto(Uint8List bytes) => _savePhoto(bytes);

  /// [wallpaper]가 null이면 기본 배경으로 되돌립니다.
  /// [everywhere]면 모든 대화방에 쓰도록 저장하고 이 방에 따로 정한 배경은 지웁니다.
  Future<void> save(
    String owner,
    String room,
    ChatWallpaper? wallpaper, {
    bool everywhere = false,
  }) async {
    final roomKey = _key(owner, room);
    final allKey = _key(owner, allRooms);
    final before = {
      ChatWallpaper.decode(await _read(roomKey))?.photo,
      if (everywhere) ChatWallpaper.decode(await _read(allKey))?.photo,
    };
    if (everywhere) {
      await _write(allKey, wallpaper?.encode());
      await _write(roomKey, null);
    } else {
      await _write(roomKey, wallpaper?.encode());
    }
    // 더 이상 쓰지 않는 사진 파일은 지웁니다(다른 곳에서 쓰는 사진은 남깁니다).
    final inUse = {
      ChatWallpaper.decode(await _read(roomKey))?.photo,
      ChatWallpaper.decode(await _read(allKey))?.photo,
    };
    for (final photo in before) {
      if (photo != null && !inUse.contains(photo)) await _deletePhoto(photo);
    }
  }
}

/// 대화방 화면에서 배경을 불러오고 바꿉니다.
class ChatWallpaperController extends ValueNotifier<ChatWallpaper?> {
  ChatWallpaperController({
    required String? owner,
    required this.room,
    ChatWallpaperStore? store,
  }) : owner = owner ?? 'guest',
       store = store ?? ChatWallpaperStore.instance,
       super(null) {
    _load();
  }

  final String owner;
  final String room;
  final ChatWallpaperStore store;
  bool _disposed = false;

  Future<void> _load() async {
    try {
      final loaded = await store.load(owner, room);
      if (!_disposed) value = loaded;
    } catch (_) {
      // 불러오지 못하면 기본 배경을 씁니다.
    }
  }

  /// 배경 고르기 창을 띄우고 고른 배경을 저장합니다.
  Future<void> choose(
    BuildContext context, {
    Future<Uint8List?> Function()? pickPhoto,
  }) async {
    final choice = await showModalBottomSheet<_WallpaperChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WallpaperSheet(current: value),
    );
    if (choice == null || _disposed) return;
    var wallpaper = choice.wallpaper;
    if (choice.photo) {
      Uint8List? bytes;
      try {
        bytes = await (pickPhoto ?? _pickPhoto)();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진을 불러올 수 없어요. 사진 접근 권한을 확인해 주세요.')),
          );
        }
        return;
      }
      if (bytes == null || _disposed) return;
      wallpaper = ChatWallpaper.photo(await store.keepPhoto(bytes));
    }
    try {
      await store.save(owner, room, wallpaper, everywhere: choice.everywhere);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('배경을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
      return;
    }
    if (_disposed) return;
    value = wallpaper ?? await store.load(owner, room);
  }

  static Future<Uint8List?> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 2560,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _WallpaperChoice {
  const _WallpaperChoice(this.wallpaper, this.everywhere, {this.photo = false});

  final ChatWallpaper? wallpaper;
  final bool everywhere;
  final bool photo;
}

/// 대화 목록 뒤에 배경을 깔아 줍니다. 사진 위에는 글자가 잘 보이도록 옅은 막을 덮습니다.
class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    required this.wallpaper,
    required this.child,
    super.key,
  });

  final ChatWallpaper? wallpaper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wallpaper = this.wallpaper;
    if (wallpaper == null) return child;
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          key: const ValueKey('chat-wallpaper'),
          child: switch (wallpaper) {
            ChatWallpaper(:final preset?) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: preset.gradient(theme.brightness),
              ),
            ),
            ChatWallpaper(:final photo?) => Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(photo),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: theme.colorScheme.surfaceContainerLow),
                ),
                ColoredBox(
                  color: theme.colorScheme.surfaceContainerLow.withValues(
                    alpha: .35,
                  ),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
        child,
      ],
    );
  }
}

class _WallpaperSheet extends StatefulWidget {
  const _WallpaperSheet({required this.current});

  final ChatWallpaper? current;

  @override
  State<_WallpaperSheet> createState() => _WallpaperSheetState();
}

class _WallpaperSheetState extends State<_WallpaperSheet> {
  bool _everywhere = false;

  void _pick(ChatWallpaper? wallpaper, {bool photo = false}) => Navigator.pop(
    context,
    _WallpaperChoice(wallpaper, _everywhere, photo: photo),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current;
    final tiles = <Widget>[
      _WallpaperTile(
        key: const ValueKey('wallpaper-default'),
        label: '기본',
        selected: current == null,
        onTap: () => _pick(null),
        child: ColoredBox(color: theme.colorScheme.surfaceContainerLow),
      ),
      for (final preset in ChatWallpaperPreset.values)
        _WallpaperTile(
          key: ValueKey('wallpaper-${preset.name}'),
          label: preset.label,
          selected: current?.preset == preset,
          onTap: () => _pick(ChatWallpaper.preset(preset)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: preset.gradient(theme.brightness),
            ),
          ),
        ),
      _WallpaperTile(
        key: const ValueKey('wallpaper-photo'),
        label: current?.photo != null ? '내 사진(바꾸기)' : '내 사진',
        selected: current?.photo != null,
        onTap: () => _pick(null, photo: true),
        child: current?.photo != null
            ? Image.file(
                File(current!.photo!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PhotoIcon(),
              )
            : const _PhotoIcon(),
      ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '대화방 배경',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '배경은 이 기기에서 나에게만 보여요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .72,
              children: tiles,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('wallpaper-everywhere'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _everywhere,
              onChanged: (value) => setState(() => _everywhere = value!),
              title: const Text('모든 대화방에 적용'),
              subtitle: const Text('배경을 따로 정한 다른 방은 그대로예요.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoIcon extends StatelessWidget {
  const _PhotoIcon();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.add_photo_alternate_outlined, size: 28),
  );
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 배경',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.blueDark
                          : theme.colorScheme.outlineVariant,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.expand(child: child),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
