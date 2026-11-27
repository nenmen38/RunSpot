import 'dart:typed_data';

/// 다른 화면(예: 프로필 카드 공유)에서 게시판 글쓰기에 사진을 붙여 열어 달라고 부탁하는 쪽지입니다.
/// 게시판 화면이 열릴 때 한 번 꺼내 가며, 꺼낸 뒤에는 비워집니다.
class BoardShareIntent {
  BoardShareIntent._();
  static final instance = BoardShareIntent._();

  Uint8List? photo;

  Uint8List? take() {
    final value = photo;
    photo = null;
    return value;
  }
}
