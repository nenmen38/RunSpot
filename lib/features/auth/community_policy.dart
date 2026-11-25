import 'package:flutter/material.dart';

/// 서버에 기록하는 버전과 화면에 표시하는 본문은 함께 갱신합니다.
abstract final class CommunityPolicy {
  static const version = 1;
  static const title = '뜀터 커뮤니티 운영정책';
  static const text = '''
이 운영정책은 뜀터의 게시글, 댓글, 프로필, 사진 및 메시지에 적용됩니다.

성적 착취와 아동 성착취물, 음란물, 폭력·위협, 혐오, 괴롭힘, 사기, 광고성 도배, 불법 거래, 타인의 개인정보 무단 공개, 저작권 침해를 금지합니다. 게시하거나 전송할 권리가 있는 자료만 공유해 주세요.

게시글·댓글·프로필·메시지의 신고 메뉴로 위반을 신고할 수 있습니다. 이용자를 차단하면 해당 이용자와의 상호작용이 제한됩니다.

운영자는 신고 내용을 검토하고 게시물 숨김·삭제, 이용 제한 또는 계정 정지 조치를 할 수 있습니다. 조치에 관한 문의는 앱 설정의 문의 경로를 이용해 주세요.
''';
}

class CommunityPolicyAgreement extends StatelessWidget {
  const CommunityPolicyAgreement({
    required this.accepted,
    required this.onChanged,
    super.key,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(CommunityPolicy.text),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('커뮤니티 운영정책에 동의합니다 (필수)'),
        value: accepted,
        onChanged: (value) => onChanged(value == true),
      ),
    ],
  );
}
