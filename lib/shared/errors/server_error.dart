import 'package:supabase_flutter/supabase_flutter.dart';

/// 예상하지 못한 서버 오류를 사람이 구분할 수 있는 문구로 바꿉니다.
/// 서버 함수가 아직 배포되지 않았으면 업데이트가 필요하다고 알리고,
/// 그 밖의 오류는 문의할 때 원인을 찾을 수 있도록 오류 코드를 덧붙입니다.
String unexpectedServerError(Object exception, String fallback) {
  if (exception is PostgrestException) {
    if (exception.code == 'PGRST202' || exception.code == '42883') {
      return '서버 업데이트가 필요한 기능입니다. 잠시 후 다시 시도해 주세요.';
    }
    final code = exception.code;
    if (code != null && code.isNotEmpty) return '$fallback (오류 코드 $code)';
  }
  if (exception is StorageException && exception.statusCode != null) {
    return '$fallback (오류 코드 ${exception.statusCode})';
  }
  return fallback;
}
