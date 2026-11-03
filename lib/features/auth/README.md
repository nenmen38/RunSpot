# 카카오 로그인과 이메일 인증

카카오 공식 Flutter SDK의 카카오계정 로그인으로 ID 토큰을 발급받고, Supabase의 `signInWithIdToken`으로 로그인합니다. 카카오 고유 ID를 Supabase 인증 서버가 검증하므로 이메일이나 닉네임으로 계정을 임의 연결하지 않습니다.

- 빌드 설정의 `KAKAO_NATIVE_KEY`에 카카오 네이티브 앱 키를 전달합니다. 클라이언트 시크릿은 앱에 포함하지 않습니다.
- 카카오 개발자 콘솔에서 해당 키의 Android 패키지·키 해시와 iOS 번들 ID를 등록하고, 카카오 로그인과 OpenID Connect를 활성화합니다.
- Supabase의 Kakao 제공자 설정은 활성화하고, 화면의 `REST API Key` 필드에는 ID 토큰 발급에 사용하는 **네이티브 앱 키**를 등록합니다. 이 필드는 ID 토큰 발급 대상 검증에 사용됩니다. `Allow users without an email`도 켭니다.
- iOS·Android의 카카오 콜백 스킴은 해당 네이티브 앱 키와 일치해야 합니다.
- 이메일 권한은 카카오에 추가 요청하지 않습니다. 로그인 후 앱의 이메일 인증 화면에서 주소를 직접 입력하고, 서버의 `my_email_verified`가 참일 때만 홈으로 진입합니다.
- 임의 이메일·고정 비밀번호·자체 발급 토큰을 사용하지 않습니다. 서명·발급 대상·nonce 검증은 Supabase 인증 서버가 수행하며 기존 서버의 이메일 인증 제한도 유지합니다.

참고: [카카오 Flutter 설정](https://developers.kakao.com/docs/ko/flutter/getting-started), [Supabase 카카오 ID 토큰 발급 대상](https://github.com/orgs/supabase/discussions/23368).
