class KakaoMapConfig {
  const KakaoMapConfig({required this.javaScriptKey, required this.origin});
  const KakaoMapConfig.fromEnvironment()
    : javaScriptKey = const String.fromEnvironment('KAKAO_JAVASCRIPT_KEY'),
      origin = const String.fromEnvironment(
        'KAKAO_MAP_ORIGIN',
        defaultValue: 'https://localhost',
      );
  final String javaScriptKey;
  final String origin;

  String? validate({required bool release}) {
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(javaScriptKey)) {
      return '카카오 지도 JavaScript 키 설정을 확인해 주세요.';
    }
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (release && (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      return '카카오 지도에 등록한 HTTPS 서비스 도메인을 확인해 주세요.';
    }
    return null;
  }
}
