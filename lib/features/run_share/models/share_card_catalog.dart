import '../../monetization/cosmetics.dart';
import 'share_layout.dart';

/// 보유 상품과 공유 화면에서 쓰는 배치를 연결합니다.
const shareCardLayouts = {
  CosmeticItem.shareMinimal: ShareLayout.minimalCard,
  CosmeticItem.shareNight: ShareLayout.nightCard,
};
