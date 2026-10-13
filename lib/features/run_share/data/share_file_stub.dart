import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<XFile> prepareShareFile(Uint8List bytes) async =>
    XFile.fromData(bytes, mimeType: 'image/png');
Future<void> removeUnsharedFile(XFile file) async {}
