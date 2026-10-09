# 데이터베이스 적용 안내

## 현재 상태

- 연결된 프로젝트: `RunSpot` (`rtdlluilhkcdghoakyrp`). 별도 운영 프로젝트 구분은 미확인입니다.
- 원격 적용: 2026-10-09 기준 개인 러닝 경로 저장까지 마이그레이션 12개 반영 완료.
- 약관 제거는 서버에 수동 반영된 함수·권한과 테이블 제거 상태를 확인한 뒤 누락된 적용 이력만 정리했습니다. 실시간 지도와 기록 저장은 CLI로 적용했습니다.
- 로컬 PostgreSQL 16에서 인증 대역을 사용해 기록 저장·중복 방지·본인 조회 및 기존 보안·지도 권한 테스트 통과.
- 원격 DB에서도 기록 저장·재시도·타인 조회 차단을 트랜잭션 안에서 검증했고, 검증용 기록은 롤백했습니다.
- 실제 Supabase 인증, 저장소, 모바일 로그인 통합 테스트는 별도로 필요합니다.

## 파일과 적용 순서

1. `migrations/20260922000100_secure_schema.sql`: 21개 테이블, 회원가입 트리거, 권한 함수, RLS, 최소 권한 부여.
2. `migrations/20260922000200_catalog_seed.sql`: 프리셋 5개, 업적 정의 3개.
3. `migrations/20260922000300_require_phone_verification.sql`: 전화번호 인증 필수 정책 및 본인 인증 상태 조회 함수.
4. `migrations/20260922000400_social_access_policy.sql`: 개인 기능 허용, 인증된 사용자 소셜 작성, 양방향 위치 공개 정책.
5. 가입·닉네임·테스트 가입(005~007), 약관 제거(`20261001000100`) 마이그레이션.
6. `migrations/20261006000100_live_runner_map.sql`: 본인 위치 갱신·삭제, 주변 러너 지도 조회 및 비공개 실시간 변경 신호.
7. `migrations/20261008000100_run_history.sql`: 본인 러닝 기록 저장 RPC와 정지·짧은 러닝 허용 제약.
8. `migrations/20261009100450_friend_management.sql`: 친구 목록·정확한 닉네임 검색·서버 상태 전이, 관계 식별자, 비공개 발송 제한 저장소.
9. `migrations/20261009104713_private_run_routes.sql`: 본인 전용 경로 저장·조회, 기록과 경로의 원자적 확정 및 재전송 일치 검사.

업적 목표값 20개 코스, 야간 10회, 누적 상승 750m는 초기 제안값입니다. 운영 반영 전 서비스 기준과 맞추세요.
테스트 사용자, 가짜 러닝 기록, 관리자 계정은 초기 데이터에 포함하지 않습니다.

원격 환경에 기존 테이블이 있으면 먼저 스키마와 마이그레이션 이력을 가져와 충돌을 검토해야 합니다.
약관 제거 등 과거 마이그레이션에는 테이블 제거가 있으므로 적용 전에 현재 스키마와 복구 수단을 확인합니다. 러닝 기록 저장 변경은 기존 기록을 삭제하지 않습니다.
개발과 운영 각각 프로젝트 ID를 확인한 뒤 연결하고, 미리보기에서 예상한 미적용 마이그레이션만 있는지 확인합니다.

```sh
supabase link --project-ref <확인한_개발_프로젝트_ID>
supabase db push --dry-run
supabase db push
```

개발에서 실제 회원가입·접근 정책을 확인한 다음 운영 프로젝트로 명시적으로 다시 연결해 같은 절차를 수행합니다.
운영 스키마 및 복구 수단 확인은 운영 적용 전에 진행합니다. 원격 데이터베이스 초기화 명령은 사용하지 않습니다.
연결 비밀번호는 CLI의 비공개 입력 또는 로컬 비밀 저장소에서 제공하고 파일·채팅·명령 인자에 기록하지 않습니다.
초기 기준 데이터는 마이그레이션에 포함되므로 별도의 시드 재실행이 필요하지 않습니다.

## 접근 계약

- 인증은 Supabase `auth.users`와 `auth.identities`가 관리합니다. 비밀번호나 OAuth 토큰을 앱 테이블에 복제하지 않습니다.
- 일반 사용자는 자기 프로필의 닉네임·표시명·공개 범위만 직접 수정할 수 있습니다.
- 전화번호 인증 전에도 앱 진입, 개인 기록·코스 이용은 허용합니다. 공개 범위는 비공개로 고정하고 게시물·댓글 작성 및 타인 위치 조회는 차단합니다.
- `auth.users.phone` 및 `phone_confirmed_at`을 확인하고, `phone_change`가 남아 있으면 재인증을 요구합니다. 사용자 메타데이터나 토큰의 과거 전화번호로 허용하지 않습니다.
- `my_phone_verified()`는 전화번호 인증 상태만 반환합니다. 정지 여부까지 포함하는 실제 데이터 접근은 `is_active()`와 RLS가 검사합니다.
- 인증된 사용자는 위치 공개 범위와 무관하게 `publish_run()`으로 검증된 자기 기록을 게시하고 댓글을 작성할 수 있습니다. 친구 수락은 별도 권한 검사 함수로 처리하며 기록 확정은 후속 서버 기능이 필요합니다.
- 친구 공개는 수락된 관계만 허용하며 양방향 차단 여부를 함께 확인합니다.
- 게시물 공개 범위는 위치 공개 범위와 독립적입니다. 인증된 비공개 사용자도 공개 게시물·댓글을 작성할 수 있습니다. 여기서 공개는 로그인한 사용자에게만 공개한다는 의미입니다.
- `runs`와 구간 기록은 본인 전용입니다. 타인은 위치·실제 시작 시각이 없는 `posts`와 가공된 경로만 읽습니다.
- `save_my_run()`은 현재 로그인한 활성 계정에 개인 측정값만 저장합니다. 전화번호 인증은 요구하지 않으며 소유자·검증 상태·코스 ID를 입력으로 받지 않습니다.
- 사용자별 `client_run_id`로 중복을 방지하며 같은 식별자의 다른 내용은 거절합니다. 음수·과도한 거리, 비정상 날짜, 경과 시간을 초과한 측정 시간을 거절합니다. 기록은 `pending` 상태로 저장되고 기존 공개·랭킹 권한을 확장하지 않습니다.
- `routes`는 본인 소유이며 다른 사람의 코스를 `runs.route_id`로 참조할 수 없습니다.
- `runspot_private`를 Supabase Data API의 노출 스키마 목록에 추가하지 않습니다.
- `my_staff_role()`은 현재 DB 역할과 `aal2`를 검사합니다. 일반 사용자 또는 다중 인증 미완료 시 NULL을 반환합니다.
- 관리자에게 원본 위치를 일괄 공개하는 정책은 없습니다. 담당 검토 건에 대한 접근이 필요하면 별도 서버 기능으로 제한합니다.
- 역할·계정 상태·감사 기록은 사용자가 직접 수정할 수 없습니다. 역할 부여는 신뢰된 운영 경로에서만 수행합니다.
- 감사 로그는 서비스 역할의 수정·삭제를 막지만 DB 소유자까지 막는 불변 저장소는 아닙니다.

## 서버 기능과 저장소 후속 작업

개인 러닝 기록 저장·목록 조회는 구현되어 있습니다. 아래 후속 기능은 아직 구현되지 않았으므로 앱의 운영 흐름 전체가 완성된 상태는 아닙니다.

- JWT 검증, 현재 계정 상태 및 대상 소유권을 확인하는 서버 API.
- 업로드 크기·형식·소유권 검사, GPS 처리, 거리 계산과 기록 확정 트랜잭션.
- 사용자 차단·차단 해제 API와 관리 화면. 기존 양방향 차단은 친구 검색·요청·수락에도 반영하지만 이번 변경은 차단 작성 권한을 추가하지 않습니다.
- 관리자 권한과 다중 인증 검사, 조치 및 감사 로그의 원자적 기록.
- AI 호출 중복 방지 및 호출 전 예산 예약. `ai_usage`는 사용량 기록이며 한도 강제 기능이 아닙니다.
- 실제 GPS 위조는 서버 거리 재계산만으로 완전히 방지되지 않습니다. `verified`는 정의한 검증 규칙을 통과했다는 의미입니다.
- 비공개 Storage 버킷 생성과 별도 Storage RLS. 객체 경로 문자열만 저장해도 접근 제어가 생기지는 않습니다.
- Storage 원본 삭제, 탈퇴 시 객체 정리 및 보관 만료 작업. DB 행 삭제가 파일 삭제를 수행하지 않습니다.
- 공개 경로 생성 시 시작·종료 주변 및 사용자가 지정한 보호 구역을 제거하고 위치 유추 위험을 평가합니다.
- 랭킹은 검증된 기록·참여 동의·공개 범위·차단을 반영하는 서버 조회로 추가합니다.

완료된 개인 측정 경로는 비공개 JSON 좌표로 저장합니다. 기존 객체 경로 참조용 테이블은 유지하며 향후 대용량 파일 저장에 사용할 수 있습니다. 대규모 공간 검색은 전용 스키마의 PostGIS와 공간 인덱스로 확장해야 합니다.
공유 경로는 원본 파일 경로를 노출하지 않고 별도의 가공된 폴리라인만 저장합니다.
서버 비밀 키는 RLS를 우회하므로 모든 서버 API가 호출자와 작업 대상을 검사해야 합니다.

## 테스트

`tests/local_auth_stub.sql`은 격리된 빈 PostgreSQL 전용입니다. 실제 Supabase에 적용하지 않습니다.
`tests/security.sql`은 테스트 데이터가 롤백되지만 개발 DB 또는 로컬 DB에서만 실행합니다.

```sh
psql <로컬_연결> -v ON_ERROR_STOP=1 \
  -f supabase/tests/local_auth_stub.sql \
  -f supabase/migrations/20260922000100_secure_schema.sql \
  -f supabase/migrations/20260922000200_catalog_seed.sql \
  -f supabase/migrations/20260922000300_require_phone_verification.sql \
  -f supabase/migrations/20260922000400_social_access_policy.sql \
  -f supabase/migrations/20260922000500_registration.sql \
  -f supabase/migrations/20260922000600_verified_nicknames.sql \
  -f supabase/migrations/20260922000700_test_registration.sql \
  -f supabase/migrations/20261001000100_remove_registration_terms.sql \
  -f supabase/tests/local_realtime_stub.sql \
  -f supabase/migrations/20261006000100_live_runner_map.sql \
  -f supabase/migrations/20261008000100_run_history.sql \
  -f supabase/migrations/20261009100450_friend_management.sql \
  -f supabase/migrations/20261009104713_private_run_routes.sql \
  -f supabase/tests/test_registration.sql \
  -f supabase/tests/registration.sql \
  -f supabase/tests/security.sql \
  -f supabase/tests/live_runner_map.sql \
  -f supabase/tests/run_history.sql \
  -f supabase/tests/friends.sql \
  -f supabase/tests/run_routes.sql
```

검증 대상은 회원 프로필 생성, 초기 데이터, 비로그인 접근 차단, 본인·타인 조회 및 수정,
거리 변조, GPS 직접 조회, 관리자 승격 차단, 친구 공유·차단·비공개 전환,
다중 인증, 관리자 역할 회수, 정지 계정 차단, 서비스 역할의 감사 로그 삭제 차단입니다.
미인증 개인 기능 허용, 소셜 작성 차단, 인증된 비공개 작성 허용, 양방향 위치 공개·친구·차단·거리·만료도 검증합니다.

## 친구 관리 API

- `friend_dashboard()`는 현재 활성 계정의 친구·받은 요청·보낸 요청과 소셜 이용 가능 여부를 반환합니다. 상대의 닉네임·사용자 ID·관계 식별자·요청 시각만 반환하며 이메일·전화번호·위치는 포함하지 않습니다.
- `search_friend(requested_nickname)`는 기존 고유 닉네임 인덱스로 정확한 이름 하나만 조회합니다. 본인, 신규 비공개 대상, 미인증·정지·양방향 차단 상대는 제외합니다. 이미 요청한 관계나 친구는 위치 공개 범위와 별개로 확인할 수 있습니다.
- `change_friend(target_id, operation, expected_id)`는 `request`, `accept`, `reject`, `cancel`, `remove`만 허용합니다. 요청과 수락은 양쪽 계정의 활성·가입·전화번호 인증·닉네임과 양방향 차단 상태를 검사합니다. 수락·거절은 받은 사람만, 취소는 보낸 사람만, 친구 삭제는 관계의 당사자만 가능합니다.
- 새 요청은 비공개가 아닌 대상에게만 허용하지만 발신자 자신의 위치 공개는 요구하지 않습니다. 비공개 발신자가 요청하면 수신자에게 닉네임이 표시되는 의도적인 공유입니다. 수락·삭제는 프로필 공개 설정이나 위치 공유 상태를 바꾸지 않습니다.
- 기존 친구 테이블에 `relationship_id`를 추가하여 오래된 요청 화면이 재요청을 조작하지 못하게 합니다. 같은 요청의 재전송과 수신자의 중복 수락은 무해하게 처리하지만 상호 요청을 자동 수락하지 않습니다.
- 참여자의 인증 행·계정 제어 행·프로필을 고정된 순서로 잠그고 관계 상태를 검사합니다. 새 요청은 5초 간격·한 시간에 30번·친구와 요청 합계 계정당 500개로 제한하며 취소해도 발송 예산은 복원하지 않습니다.
- 발송 제한 테이블은 비노출 스키마에 두고 RLS 기본 거절과 테이블 권한 회수로 클라이언트 접근을 막습니다. 공개 함수는 호출자 권한으로 비공개 검사 함수에 연결하며 비로그인 실행 권한과 친구 테이블 직접 쓰기 권한은 추가하지 않습니다. 권한 근거: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
- 로컬 PostgreSQL 16에서 `tests/friends.sql`과 기존 가입·지도·보안·기록 테스트가 통과했습니다. 실제 서버에서는 새 함수 실행 권한, 비로그인 및 빈 세션 차단, 직접 쓰기 차단, RLS와 마이그레이션 이력을 확인했습니다. iPhone 시뮬레이터의 실제 로그인 세션으로 미인증 목록 조회와 검색 제한도 확인했습니다. 원격에 가짜 가입 계정이나 친구 요청을 남기지 않았습니다.
- 적용 후 보안 점검에서 새 경고는 없었습니다. 발송 제한 테이블의 정책 없음 안내는 의도적인 기본 거절 구성입니다. 기존 공개 가입 함수 실행 경고와 [유출 비밀번호 보호 미설정](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)은 변경하지 않았습니다. 공개 함수 실행 점검 안내: [비로그인 실행](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [로그인 사용자 실행](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

두 실제 계정에서 전화번호 인증·닉네임 등록 후 검색 → 요청 → 상대 수락 → 친구 공개 위치 확인 → 친구 삭제 후 위치 권한 회수를 검증해야 합니다. 소셜의 30초 갱신은 화면이 열린 동안만 수행하며 푸시 알림과 함께 달리기 초대는 포함하지 않습니다.

## 회원가입

가입·닉네임·테스트 가입 마이그레이션(005~007)과 약관 제거 마이그레이션(20261001000100)을 연결된 개발 프로젝트에 적용합니다.
가입 완료에는 별도 약관 동의가 필요하지 않습니다.

### 개발용 테스트 가입

- 디버그 앱은 서버의 `registration_test_mode()`가 허용하면 별도 테스트 가입 기록을 만들 수 있습니다. 이메일 확인 정책은 유지합니다.
- 현재 일반 가입은 약관 없이 완료되므로 테스트 가입은 과거 개발 데이터 검증용으로만 유지합니다.
- 전화번호 인증, 닉네임 등록 및 소셜 제한은 생략하지 않습니다.
- 마이그레이션 기본값은 비활성이며 개발 DB에만 7일간 활성화합니다. 실제 만료 시각은 아래 조회로 확인합니다.
- 만료 또는 비활성화 즉시 테스트 접근 권한이 사라집니다. 기존 테스트 사용자는 정식 가입 완료 함수로 전환됩니다.
- 설정은 일반 앱에서 변경할 수 없습니다. 운영자는 개발 DB에서만 다음 SQL로 확인·종료합니다.

```sql
select enabled_until from runspot_private.registration_test_settings;
-- 테스트 종료 시 즉시 비활성화합니다.
update runspot_private.registration_test_settings set enabled_until=null where singleton;
```

### 일반 가입

- 이메일 가입 시 이메일, 비밀번호, 비밀번호 확인만 요구합니다. 비밀번호 확인 값은 서버에 저장하거나 전송하지 않습니다.
- 기본 가입에는 닉네임이 필요하지 않습니다. 미인증 사용자는 개인 기능만 사용하며 프로필에는 '나'로 표시됩니다.
- 전화번호 인증을 완료한 뒤 별도 화면에서 닉네임을 등록합니다. 인증 후 등록을 취소해도 개인 기능은 사용할 수 있습니다.
- 닉네임은 한글 완성형·영문·숫자·밑줄 2~30자이며 기존 고유 인덱스로 대소문자 중복을 차단합니다. 공백은 허용하지 않습니다.
- `set_my_nickname`은 현재 사용자만 대상으로 삼으며 가입·전화번호 인증을 서버에서 확인합니다. 직접 프로필 닉네임 수정 권한은 제거합니다.
- 최초 닉네임 등록 이후 변경은 서버 시각 기준 30일에 한 번입니다. 동일한 이름 재요청은 변경 시각을 갱신하지 않습니다.
- 전화번호 인증과 닉네임 등록을 모두 완료해야 소셜 쓰기와 위치 공유가 가능합니다. 인증된 비공개 사용자의 게시글·댓글 작성은 허용됩니다.
- 006 적용 시 기존 미인증 선점 닉네임은 해제하고 인증된 이름은 유지합니다. 적용 전 대상 데이터를 확인해야 합니다.
- 연결된 Supabase의 `auth.users.phone` 고유 인덱스를 읽기 전용으로 확인했습니다. 실제 문자 인증 및 번호 중복 오류 흐름은 문자 발송 연결 후 검증해야 합니다.
- 가입·문자 요청 빈도 제한은 Supabase Auth 설정에서 관리합니다. 이번 변경은 원격 제한 설정을 변경하지 않았습니다. 출시 전 [인증 요청 제한](https://supabase.com/docs/guides/auth/rate-limits)과 CAPTCHA를 점검해야 합니다. 탈퇴 후 동일 번호의 재가입 유예는 별도 보관 정책 및 서버 구현이 필요합니다.
- 약관 제거 마이그레이션은 `registration_terms`, `registration_consents`를 삭제하고 `complete_registration()`을 인자 없이 호출하도록 변경합니다.
- 미완료 계정의 앱 데이터 접근은 DB 정책에서도 제한합니다. 가입 완료 후 전화번호 인증에 따른 기존 개인·소셜 권한 구분은 유지됩니다.

테스트 모드 종료, 이메일·소셜 신규 가입과 기존 계정 보완 가입의 실기기 검증을 순서대로 진행합니다.

## 위치 및 소셜 API

- `publish_run(target_run, content, audience)`: 현재 사용자 소유의 검증된 러닝만 게시합니다. 거리·시간은 DB에서 복사합니다.
- `comments`: 인증된 사용자만 접근 가능한 게시물에 댓글을 추가·수정합니다. 작성자와 생성 시각은 클라이언트가 지정하지 못합니다.
- `nearby_locations(radius_m)`: 비공개이면 빈 결과, 친구 공개이면 수락된 친구만, 전체 공개이면 범위 안의 공개 대상만 반환합니다.
- 상대방이 비공개이거나 미인증·정지·차단 상태이면 위치를 반환하지 않습니다. 친구 공개 상대는 실제 친구에게만 보입니다.
- 기본 반경 1km, 최대 5km, 위치 유효시간 2분, 최대 결과 200개를 초기 설정으로 사용합니다.
- 좌표는 서버가 `runspot_private.live_locations`에 기록해야 합니다. 임의 중심 좌표를 조회 API에 전달할 수 없습니다.
- `update_my_live_location(latitude,longitude,accuracy_m)`: 인증·닉네임·공개 설정을 검사한 뒤 현재 사용자 위치만 기록합니다. 사용자 ID와 갱신 시각은 서버가 정하며 3초 이내 중복 갱신과 부정확한 좌표를 거릅니다. 기기 GPS 자체의 위조까지 검증하는 API는 아닙니다.
- `stop_live_location()`: 현재 사용자 위치만 삭제합니다. 비공개 전환·닉네임 해제 시에도 원본을 삭제합니다.
- `map_nearby_runners(radius_m)`: 기존 위치 공개 정책을 적용해 닉네임, 거리, 최근 갱신 시각을 함께 반환합니다.
- `runner-map`은 비공개 실시간 채널입니다. 인증된 사용자에게 좌표와 식별자가 없는 변경 신호만 전달하며 앱은 RPC로 현재 접근 권한을 다시 검사합니다. 클라이언트 방송 전송 권한은 추가하지 않습니다.
- 새 마이그레이션은 실제 Supabase의 `realtime.messages`, `realtime.send`, `realtime.topic`이 필요합니다. `tests/local_realtime_stub.sql`은 로컬 테스트에만 사용하며 원격 DB에 적용하지 않습니다.
- 앱은 공유 중 15초마다 갱신하여 만료와 연결 복구를 확인합니다. 백그라운드 공유, 러닝 초대·수락, 오래된 원본의 주기적 삭제 및 게시물·댓글 작성 화면은 별도 작업입니다.
- 코스 생성 화면은 제거했지만 기존 러닝 기록의 참조를 보존하기 위해 과거 코스 DB 테이블과 기존 마이그레이션은 삭제하지 않습니다.
- 공유된 과거 경로도 본인 또는 위치 조회 자격을 충족한 사용자만 볼 수 있습니다. 실시간 반경 검색은 `nearby_locations`에 적용합니다.

## 문자 발송 연결

현재 문자 발송 업체 계정이 없으며 원격 Phone 인증은 비활성화 상태입니다.
실제 인증 문자 발송 및 수신 검증은 미완료입니다. 이 상태에서도 개인 기능은 사용할 수 있으나 소셜 상호작용은 제한됩니다.

1. 지원되는 문자 발송 업체 계정을 준비하고 한국 휴대폰 발송 가능 여부와 발신자 요건을 확인합니다.
2. Supabase 인증 설정의 Phone 제공업체에 발송 자격 증명을 등록합니다. 비밀 키는 앱이나 저장소에 넣지 않습니다.
3. Phone 인증을 활성화하고 문자 확인을 필수로 설정합니다. 자동 확인 및 테스트 OTP 우회 설정을 운영에 사용하지 않습니다.
4. 서버의 발송 빈도·인증 시도 제한과 업체의 발송 예산을 설정합니다. 현재 앱의 60초 대기시간은 화면 편의 기능이며 서버 제한을 대체하지 않습니다.
5. CAPTCHA를 활성화하려면 앱에 해당 챌린지와 토큰 전달을 함께 연동해야 합니다. 이 변경에는 CAPTCHA 연동이 포함되지 않습니다.
6. 실제 기기에서 신규 소셜 계정, 기존 인증 계정, 잘못된 코드, 만료, 재전송, 번호 중복, 번호 변경을 검증합니다.

일반 문자 소유 확인은 관리자 다중 인증(`aal2`)과 별개입니다.
신규 소셜 서버 API를 만들 때에는 서비스 역할로 데이터를 변경하기 전에 JWT 검증과 현재 전화번호 확인·계정 상태 검사를 모두 수행해야 합니다. 개인 기록은 전화번호 인증과 분리하되 로그인·본인 소유권·활성 계정 검사를 유지합니다.

## 기록 저장 보안 점검

- `runs`의 RLS와 본인 조회 정책은 유지하며 일반 사용자의 직접 INSERT·UPDATE 권한은 없습니다. 저장 RPC의 실행 권한은 로그인 사용자에게만 부여합니다.
- 기록 요청은 측정 계정의 로그인 세션에 고정하며 계정이 바뀐 후 이전 요청의 결과를 화면에 반영하지 않습니다.
- 비공개 스키마의 RLS 정책 없음 안내는 일반 사용자의 직접 접근을 거부하는 기존 설계입니다. RPC는 현재 사용자와 활성 계정을 검사합니다.
- Supabase의 [로그인 사용자 실행 가능 권한 함수 안내](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)는 `save_my_run()`에도 표시됩니다. 의도한 API이며 소유자 입력·검증 상태 변경·타인 기록 조회를 허용하지 않습니다.
- 기존 Auth의 [유출 비밀번호 검사 미설정 경고](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)는 이번 기능 범위에서 변경하지 않았습니다.

## 러닝 환경 조회

- `20261009111535_running_conditions.sql`, `20261009191148_environment_shared_budget.sql`과 `functions/running-conditions/`가 필요합니다. 함수의 `verify_jwt`는 켜 두며 플랫폼 검사 후 `getUser()`와 현재 활성 계정 검사를 추가로 수행합니다. 개인 환경 조회에는 전화번호 인증을 요구하지 않습니다.
- 공공데이터포털에서 [기상청 단기예보](https://www.data.go.kr/data/15084084/openapi.do), [에어코리아 대기오염정보](https://www.data.go.kr/data/15073861/openapi.do), [에어코리아 측정소정보](https://www.data.go.kr/data/15073877/openapi.do)를 승인받습니다. 키는 서버 비밀 설정 `KMA_SERVICE_KEY`, `AIRKOREA_SERVICE_KEY`에 등록하며 클라이언트 빌드 설정·저장소·로그에는 추가하지 않습니다.
- `supabase secrets set --project-ref <프로젝트 식별자> --env-file <보호된 서버 비밀 파일>`로 등록합니다. 파일은 두 변수만 포함하고 본인만 읽을 수 있게 보호하며 Git에 넣지 않습니다. 같은 공공데이터 키도 각 API의 활용 승인이 필요합니다. 실제 운영 계정 승인과 일일 호출량은 공공데이터포털에서 관리합니다.
- `running-conditions`는 로그인 세션으로 `latitude`, `longitude`만 받습니다. 좌표는 약 1km 정밀도로 반올림하고 기상청 5km 격자와 가까운 미세먼지 측정소를 선택합니다. 사용자 좌표는 저장하지 않습니다. 외부 기관에는 격자·시도명만 보내고 기관 오류 원문이나 인증키를 포함한 URL은 앱에 반환하지 않습니다.
- 공개 관측 캐시는 비공개 스키마의 RLS 기본 거절 테이블에 저장합니다. 공동 캐시·갱신 권한·호출 예산 RPC는 `service_role`만 실행 가능하며 공개 연결 함수는 호출자 권한으로 실행합니다. 앱은 원본 캐시·예산 테이블에 접근할 수 없습니다. 기존 캐시 RPC는 이전 배포 호환을 위해 유지하지만 새 함수는 공동 캐시만 사용합니다.
- 날씨는 격자별 마지막 정상 자료를 보관하며 `base_date:base_time`이 같은 발표 자료를 반복 조회하지 않습니다. 다음 발표 시각부터 요청이 있는 격자만 갱신합니다. 미세먼지는 `getCtprvnRltmMesureDnsty`의 시도별 최신 측정소 목록을 3600초간 공유하며 측정소 목록은 86400초간 공유합니다. 전남·광주는 공식 문서의 `전남광주` 조회로 통합합니다. 페이지 누락 없이 전체 목록을 받은 뒤 저장하며 매 페이지 예산을 예약합니다. 가장 가까운 30km 이내 측정소만 선택하고 코드가 있으면 동일 코드로 연결합니다.
- 지역별 DB 행을 잠가 180초 갱신 권한을 부여하고, 갱신 권한 토큰으로 호출 예약·저장을 검증합니다. 프로세스 장애 후 권한이 만료되면 새 요청이 담당하며 이전 작업자는 결과를 덮어쓸 수 없습니다. 실패 후 5분 동안 반복 조회를 막습니다. 갱신할 때 일주일 이상 갱신되지 않은 다른 지역의 캐시를 정리하며 현재 요청 지역의 마지막 정상 자료는 보존합니다. 만료 자료 반환에는 오류·원래 관측 시각·마지막 서버 갱신 시각을 포함합니다. 최신 자료의 수신 시각이 관측 시각을 대체하지 않습니다.
- `environment_budgets`의 `kma`, `air`, `stations`는 각각 최근 24시간 450회 상한입니다. 기관 초기화 시각을 추측하지 않고 이동 24시간 창으로 보수적으로 집계합니다. 기관별 예산 행을 잠근 트랜잭션에서 호출 전 예약하고 실패·시간 초과도 환불하지 않습니다. 예산 RPC 장애 시 외부 요청을 진행하지 않습니다. 운영 승인 후 증액하려면 승인 범위에 맞게 상한 검증과 설정을 마이그레이션으로 변경해야 합니다. 다른 서버·스크립트에서 같은 키를 사용하는 호출은 이 DB 예산에 포함되지 않습니다.
- 계정당 최소 10초 간격·시간당 120회 제한은 유지합니다. 기관별 상한에 도달하면 외부 요청을 중단하고 마지막 정상 자료와 `quota_exhausted`를 반환합니다. 마지막 자료가 없으면 해당 기관 자료는 `null`입니다. 앱은 공동 갱신 실패 또는 관측 2시간 경과 시 양호 판단을 중단하며 이미 확인된 주의 조건은 자료 부족 안내와 함께 유지합니다.

```sh
cd supabase/functions/running-conditions
npx --yes deno@2.5.4 check index.ts
npx --yes deno@2.5.4 test providers_test.ts shared_cache_test.ts
```

SQL 권한·호출 제한 테스트는 `tests/running_conditions.sql`, `tests/environment_shared_budget.sql`을 격리된 로컬 DB에서 실행합니다. 새 테스트는 갱신 권한·예산 접근 차단·발표 경계·한도·실패 자료 보관·24시간 경과·이전 작업자 덮어쓰기 차단도 확인합니다. 의존성은 고정 버전과 `deno.lock`으로 관리합니다.

`tests/environment_concurrency_test.ts`는 인증 대역을 가진 임시 로컬 DB에서 20개 연결의 갱신 권한과 449회 사용 후 동시 요청이 정확히 한 회만 허용되는지 검증합니다. 소켓은 `/private/tmp/runspot-environment-db.`로 시작하는 격리 경로, 포트는 55439를 사용합니다. 실제 Supabase에 실행하지 않습니다.

```sh
ENVIRONMENT_TEST_SOCKET=<격리된_임시_DB_소켓> ENVIRONMENT_TEST_PSQL=<psql_실행파일> \
  npx --yes deno@2.5.4 test --allow-env=ENVIRONMENT_TEST_SOCKET,ENVIRONMENT_TEST_PSQL \
  --allow-run=<psql_실행파일> supabase/tests/environment_concurrency_test.ts
```

관리자의 SQL 조회로 외부 호출 예약량을 확인합니다. 사용자별 앱 조회 횟수가 아니라 기관별 실제 외부 요청 예산입니다.

```sql
select b.provider,b.max_requests,count(a.id) as reserved_last_24h
from runspot_private.environment_budgets b
left join runspot_private.environment_attempts a
  on a.provider=b.provider and a.reserved_at>clock_timestamp()-interval '24 hours'
group by b.provider,b.max_requests;
```

## 개인 경로 저장 API

- `save_my_run_with_route()`는 기존 개인 기록 검사를 재사용하고 구간별 `[[위도,경도],…]` 배열을 기록과 같은 트랜잭션에서 저장합니다. 동일한 기록 식별자의 다른 경로는 거절하며 서버 응답이 끊겨도 같은 내용으로 재전송할 수 있습니다. 기존 `save_my_run()`은 이전 앱과의 호환을 위해 유지합니다.
- `my_run_route(requested_run_id)`는 현재 활성 계정이 소유한 기록만 조회합니다. 친구 여부·위치 공개 설정과 관계없이 타인 경로와 미존재 기록은 같은 접근 거절 응답을 반환합니다. 경로 없는 이전 기록은 빈 배열을 반환합니다.
- 경로는 `runspot_private.measured_run_routes`에 저장합니다. RLS 기본 거절과 직접 테이블 권한 회수를 함께 적용하며, 공개 함수는 호출자 권한으로 비공개 검사 함수에 연결합니다. Data API의 노출 스키마에 `runspot_private`를 추가하지 않습니다.
- 좌표는 유한한 숫자와 지리 범위를 검사합니다. 구간 5만 개·좌표 50만 개·직렬화된 데이터 32MiB까지 허용하며 잘라서 저장하지 않습니다. 상한 초과 요청은 거절하고 앱의 기기 원본은 유지합니다. 좌표별 시각·정확도·인증 토큰은 저장하지 않습니다.
- 기록 삭제 시 경로도 함께 삭제됩니다. 별도 경로 공개·거리 검증·전체 기록 오프라인 캐시는 포함하지 않습니다. 지도 배경은 기존 타일 제공자를 사용합니다.
- 로컬 SQL 테스트에서 정밀도·구간 단절·형식·범위·크기 제한·중복·다른 경로 거절·비로그인·타인·친구·정지 계정 및 직접 접근 차단을 검증했습니다. 원격 서버에서는 실제 활성 계정의 저장·재전송·본인 조회·접근 거절을 트랜잭션 안에서 확인하고 롤백하여 기존 기록 2개를 보존했습니다.
- 보안 점검에 새 경고는 없습니다. 새 비공개 테이블의 [정책 없음 안내](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)는 직접 접근을 허용하지 않는 의도된 구성입니다. 기존 공개 함수 실행 및 유출 비밀번호 검사 경고는 변경하지 않았습니다.

참고: [마이그레이션](https://supabase.com/docs/guides/deployment/database-migrations),
[행 수준 보안](https://supabase.com/docs/guides/database/postgres/row-level-security),
[저장소 접근 제어](https://supabase.com/docs/guides/storage/security/access-control).
