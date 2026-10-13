import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'share_file_stub.dart' if (dart.library.io) 'share_file_io.dart';

enum RunShareResult { handedOff, cancelled, unknown }

abstract interface class RunShareService {
  Future<RunShareResult> share(
    Uint8List png,
    Rect origin, {
    required bool Function() isCurrentOwner,
  });
}

class PlatformRunShareService implements RunShareService {
  @override
  Future<RunShareResult> share(
    Uint8List png,
    Rect origin, {
    required bool Function() isCurrentOwner,
  }) async {
    if (!isCurrentOwner()) throw StateError('로그인 상태를 확인해 주세요.');
    final file = await prepareShareFile(png);
    try {
      if (!isCurrentOwner()) throw StateError('로그인 상태를 확인해 주세요.');
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: ['runspot.png'],
          title: '러닝 기록 공유',
          sharePositionOrigin: origin,
        ),
      );
      if (result.status == ShareResultStatus.dismissed) {
        await removeUnsharedFile(file);
      }
      return switch (result.status) {
        ShareResultStatus.success => RunShareResult.handedOff,
        ShareResultStatus.dismissed => RunShareResult.cancelled,
        ShareResultStatus.unavailable => RunShareResult.unknown,
      };
    } catch (_) {
      await removeUnsharedFile(file);
      rethrow;
    }
  }
}
