import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

Future<XFile> prepareShareFile(Uint8List bytes) async {
  final root = await getTemporaryDirectory();
  final directory = await Directory(path.join(root.path, 'runspot-shares'))
      .create(recursive: true);
  final expiry = DateTime.now().subtract(const Duration(hours: 24));
  // 다른 캐시나 원본 기록은 건드리지 않고 오래된 공유 PNG만 정리합니다.
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is File &&
        RegExp(r'^runspot-[a-f0-9-]+\.png$')
            .hasMatch(path.basename(entry.path))) {
      if ((await entry.stat()).modified.isBefore(expiry)) await entry.delete();
    }
  }
  final file = File(
    path.join(directory.path, 'runspot-${const Uuid().v4()}.png'),
  );
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: 'image/png');
}

Future<void> removeUnsharedFile(XFile file) async {
  final local = File(file.path);
  if (await local.exists()) await local.delete();
}
