import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_share/models/share_sticker_alignment.dart';

void main() {
  test('허용 거리 안에서 캔버스에 들어가는 가장 가까운 정렬선을 선택합니다', () {
    expect(
      nearestStickerGuide(
        105,
        [102, 110, 106, 112],
        minCenter: 100,
        maxCenter: 900,
        tolerance: 8,
      ),
      106,
    );
    expect(
      nearestStickerGuide(
        101,
        [99, 109, 110],
        minCenter: 100,
        maxCenter: 900,
        tolerance: 8,
      ),
      109,
    );
  });

  test('정렬선에서 멀어지거나 정렬할 스티커가 없으면 원래 위치를 사용합니다', () {
    for (final guides in [
      <double>[],
      [109.01, 92.99],
      [99.0],
    ]) {
      expect(
        nearestStickerGuide(
          101,
          guides,
          minCenter: 100,
          maxCenter: 900,
          tolerance: 8,
        ),
        isNull,
      );
    }
  });
}
