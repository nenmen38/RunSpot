# 데이터베이스 적용 안내

## 현재 상태

- 연결된 프로젝트: `RunSpot` (`rtdlluilhkcdghoakyrp`). 별도 운영 프로젝트 구분은 미확인입니다.
- 원격 적용: 2026-10-21 기준 차단·실제 업적·관리 검토·그룹 러닝까지 마이그레이션 24개와 기존 `run-feedback` 함수 반영 완료.
- 약관 제거는 서버에 수동 반영된 함수·권한과 테이블 제거 상태를 확인한 뒤 누락된 적용 이력만 정리했습니다. 실시간 지도와 기록 저장은 CLI로 적용했습니다.
- 로컬 PostgreSQL 16에서 인증 대역을 사용해 기록 저장·중복 방지·본인 조회 및 기존 보안·지도 권한 테스트 통과.
- 원격 DB에서도 기록 저장·재시도·타인 조회 차단을 트랜잭션 안에서 검증했고, 검증용 기록은 롤백했습니다.
- 실제 Supabase 인증, 저장소, 모바일 로그인 통합 테스트는 별도로 필요합니다.
- 이메일 전환은 로컬 SQL 테스트 10개와 앱 테스트 160개가 통과했습니다. 원격 서버의 실제 계정에서 이메일 확인·가입 완료·비공개 유지·닉네임 등록 필요 상태를 읽기 전용으로 검증했습니다. iPhone 시뮬레이터에서도 전화번호 인증 없이 닉네임 등록 화면이 활성화됨을 확인했으며 닉네임과 공개 설정은 변경하지 않았습니다. 새 확인 메일의 실제 수신과 링크 복귀는 별도 검증이 필요합니다.
- 선택 전화번호 인증 추가 후 앱 테스트 175개와 로컬 SQL 테스트 11개가 통과했습니다. 관련 코드 정적 검사, 원격 본인 조회·실행 권한 검사와 iPhone 시뮬레이터의 수동 인증 완료 표시를 확인했습니다. 실제 문자 발송은 검증하지 않았습니다.

## 파일과 적용 순서

1. `migrations/20260922000100_secure_schema.sql`: 21개 테이블, 회원가입 트리거, 권한 함수, RLS, 최소 권한 부여.
2. `migrations/20260922000200_catalog_seed.sql`: 프리셋 5개, 업적 정의 3개.
3. `migrations/20260922000300_require_phone_verification.sql`: 과거 전화번호 인증 정책. 최신 이메일 전환 마이그레이션이 이를 대체합니다.
4. `migrations/20260922000400_social_access_policy.sql`: 개인 기능 허용, 인증된 사용자 소셜 작성, 양방향 위치 공개 정책.
5. 가입·닉네임·테스트 가입(005~007), 약관 제거(`20261001000100`) 마이그레이션.
6. `migrations/20261006000100_live_runner_map.sql`: 본인 위치 갱신·삭제, 주변 러너 지도 조회 및 비공개 실시간 변경 신호.
7. `migrations/20261008000100_run_history.sql`: 본인 러닝 기록 저장 RPC와 정지·짧은 러닝 허용 제약.
8. `migrations/20261009100450_friend_management.sql`: 친구 목록·정확한 닉네임 검색·서버 상태 전이, 관계 식별자, 비공개 발송 제한 저장소.
9. `migrations/20261009104713_private_run_routes.sql`: 본인 전용 경로 저장·조회, 기록과 경로의 원자적 확정 및 재전송 일치 검사.
10. `migrations/20261009111535_running_conditions.sql`, `20261009191148_environment_shared_budget.sql`: 러닝 환경 조회와 지역 공동 캐시·외부 호출 예산.
11. `migrations/20261011171941_email_social_verification.sql`: 소셜 인증을 이메일로 전환하고 기존 전화번호 인증 RPC를 제거합니다. 기존 닉네임은 보존하며 이메일 미인증 계정의 공개 범위만 비공개로 되돌립니다.
12. `migrations/20261011185117_optional_phone_verification.sql`: 선택 전화번호 인증의 본인 상태 조회. 이메일 기반 소셜 권한을 바꾸거나 인증 상태를 직접 쓰는 기능은 추가하지 않습니다.
13. `migrations/20261013002352_run_feedback_quota.sql`: AI 피드백의 본인 조회, 계정별 72시간·전체 호출 예산과 서버 전용 예약·결과 저장.
14. `migrations/20261013012622_run_temperature_snapshot.sql`: 종료 기온·관측 시각과 본인 저장 RPC. 기존 기록·경로 저장 RPC는 유지하고 과거 기온을 추정해 채우지 않습니다.
15. `migrations/20261019000100_run_rewards.sql`: 러닝 경험치·레벨. 기록 저장과 같은 트랜잭션에서 보상을 한 번만 계산하고 본인 진행도·기록별 보상 조회 RPC를 추가합니다. 기존 기록에는 소급 지급하지 않습니다.
16. `migrations/20261020065459_run_statistics_and_friend_ranking.sql`: 개인 통계·친구 주간 거리 집계 조회와 종료 시각 인덱스. 사용자 배포 승인 후 연결된 RunSpot 서버에 적용했습니다.
17. `migrations/20261020125728_run_location_preferences.sql`: 본인 전용 러닝 자동 위치 공유 설정과 접근 정책. 사용자 배포 승인 후 연결된 RunSpot 서버에 적용했습니다.

18. `migrations/20261026000100_community_board.sql`: 동네·전국 게시판과 러닝 대회 공지. 아직 원격 서버에 적용하지 않았습니다.
19. `migrations/20261027000100_board_engagement.sql`: 게시판 좋아요·댓글·사진 첨부, 글 수정 시 사진 변경과 비공개 `board-images` 저장소 버킷·정책. `20261026085356_app_usability_improvements.sql` 다음에 적용하며 아직 원격 서버에 적용하지 않았습니다.

20. `migrations/20261028000100_account_deletion.sql`: 앱 안 회원 탈퇴(`delete_my_account()`). 본인 인증 계정을 지우면 외래 키 연쇄 삭제로 프로필·기록·게시판 자료가 함께 지워지고 탈퇴 사실만 감사 기록에 남습니다. 게시판 사진 파일은 앱이 먼저 Storage API로 지웁니다.

이전 업적 정의는 데이터 호환을 위해 보존합니다. 현재 앱은 첫 이동 러닝·누적 10회·누적 50km 업적만 표시합니다.
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
- 로그인한 활성 계정은 이메일 미인증 상태에서도 개인 기록을 이용할 수 있습니다. 공개 범위는 비공개로 고정하고 게시물·댓글 작성 및 타인 위치 조회는 차단합니다.
- `auth.users.email` 및 `email_confirmed_at`을 확인하고, `email_change`가 남아 있거나 익명 계정이면 소셜 인증을 인정하지 않습니다. 사용자 메타데이터나 토큰의 과거 이메일로 허용하지 않습니다.
- `my_email_verified()`는 본인의 이메일 인증 상태만 반환합니다. 정지 여부까지 포함하는 실제 데이터 접근은 `is_active()`와 RLS가 검사합니다.
- 인증된 사용자는 위치 공개 범위와 무관하게 `publish_run()`으로 검증된 자기 기록을 게시하고 댓글을 작성할 수 있습니다. 친구 수락은 별도 권한 검사 함수로 처리하며 기록 확정은 후속 서버 기능이 필요합니다.
- 친구 공개는 수락된 관계만 허용하며 양방향 차단 여부를 함께 확인합니다.
- 게시물 공개 범위는 위치 공개 범위와 독립적입니다. 인증된 비공개 사용자도 공개 게시물·댓글을 작성할 수 있습니다. 여기서 공개는 로그인한 사용자에게만 공개한다는 의미입니다.
- `runs`와 구간 기록은 본인 전용입니다. 타인은 위치·실제 시작 시각이 없는 `posts`와 가공된 경로만 읽습니다.
- `save_my_run()`은 현재 로그인한 활성 계정에 개인 측정값만 저장합니다. 이메일 인증은 요구하지 않으며 소유자·검증 상태·코스 ID를 입력으로 받지 않습니다.
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
- 차단·관리·그룹의 새 마이그레이션은 아래 로컬 검증 변경 사항을 원격에 반영해야 사용할 수 있습니다.
- 관리자 역할은 신뢰된 운영 경로로 부여해야 합니다. 새 관리 함수는 현재 역할·다중 인증과 감사 기록을 검사합니다.
- 실제 GPS 위조는 서버 거리 재계산만으로 완전히 방지되지 않습니다. `verified`는 정의한 검증 규칙을 통과했다는 의미입니다.
- 비공개 Storage 버킷 생성과 별도 Storage RLS. 객체 경로 문자열만 저장해도 접근 제어가 생기지는 않습니다.
- Storage 원본 삭제, 탈퇴 시 객체 정리 및 보관 만료 작업. DB 행 삭제가 파일 삭제를 수행하지 않습니다.
- 공개 경로 생성 시 시작·종료 주변 및 사용자가 지정한 보호 구역을 제거하고 위치 유추 위험을 평가합니다.
- 검증된 기록과 별도 참여 동의를 사용하는 공식 경쟁 랭킹은 후속 작업입니다. 현재 친구 주간 랭킹은 기존 프로필 공개 범위를 따르는 저장된 개인 측정 거리 비교입니다.

완료된 개인 측정 경로는 비공개 JSON 좌표로 저장합니다. 기존 객체 경로 참조용 테이블은 유지하며 향후 대용량 파일 저장에 사용할 수 있습니다. 대규모 공간 검색은 전용 스키마의 PostGIS와 공간 인덱스로 확장해야 합니다.
공유 경로는 원본 파일 경로를 노출하지 않고 별도의 가공된 폴리라인만 저장합니다.
서버 비밀 키는 RLS를 우회하므로 모든 서버 API가 호출자와 작업 대상을 검사해야 합니다.

## 테스트

모든 마이그레이션과 SQL 테스트는 `scripts/run_sql_tests.sh`로 순서대로 실행합니다. 격리된 빈 PostgreSQL 16 전용이며 CI(`.github/workflows/ci.yml`)도 같은 스크립트를 씁니다.

```sh
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres scripts/run_sql_tests.sh
```

아래 목록은 초기 기준이며 이후 추가된 마이그레이션·테스트 순서는 스크립트를 따릅니다.

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
  -f supabase/migrations/20261009111535_running_conditions.sql \
  -f supabase/migrations/20261009191148_environment_shared_budget.sql \
  -f supabase/migrations/20261011171941_email_social_verification.sql \
  -f supabase/migrations/20261011185117_optional_phone_verification.sql \
  -f supabase/migrations/20261013002352_run_feedback_quota.sql \
  -f supabase/migrations/20261013012622_run_temperature_snapshot.sql \
  -f supabase/migrations/20261019000100_run_rewards.sql \
  -f supabase/migrations/20261020065459_run_statistics_and_friend_ranking.sql \
  -f supabase/migrations/20261020125728_run_location_preferences.sql \
  -f supabase/tests/test_registration.sql \
  -f supabase/tests/registration.sql \
  -f supabase/tests/security.sql \
  -f supabase/tests/live_runner_map.sql \
  -f supabase/tests/run_history.sql \
  -f supabase/tests/friends.sql \
  -f supabase/tests/run_routes.sql \
  -f supabase/tests/running_conditions.sql \
  -f supabase/tests/environment_shared_budget.sql \
  -f supabase/tests/email_verification.sql \
  -f supabase/tests/optional_phone_verification.sql \
  -f supabase/tests/run_feedback.sql \
  -f supabase/tests/run_temperature.sql \
  -f supabase/tests/run_rewards.sql \
  -f supabase/tests/run_statistics.sql \
  -f supabase/tests/run_location_preferences.sql
```

검증 대상은 회원 프로필 생성, 초기 데이터, 비로그인 접근 차단, 본인·타인 조회 및 수정,
거리 변조, GPS 직접 조회, 관리자 승격 차단, 친구 공유·차단·비공개 전환,
다중 인증, 관리자 역할 회수, 정지 계정 차단, 서비스 역할의 감사 로그 삭제 차단입니다.
미인증 개인 기능 허용, 소셜 작성 차단, 인증된 비공개 작성 허용, 양방향 위치 공개·친구·차단·거리·만료도 검증합니다.

## 친구 관리 API

- `friend_dashboard()`는 현재 활성 계정의 친구·받은 요청·보낸 요청과 소셜 이용 가능 여부를 반환합니다. 상대의 닉네임·사용자 ID·관계 식별자·요청 시각만 반환하며 이메일·전화번호·위치는 포함하지 않습니다.
- `search_friend(requested_nickname)`는 기존 고유 닉네임 인덱스로 정확한 이름 하나만 조회합니다. 본인, 신규 비공개 대상, 미인증·정지·양방향 차단 상대는 제외합니다. 이미 요청한 관계나 친구는 위치 공개 범위와 별개로 확인할 수 있습니다.
- `change_friend(target_id, operation, expected_id)`는 `request`, `accept`, `reject`, `cancel`, `remove`만 허용합니다. 요청과 수락은 양쪽 계정의 활성·가입·이메일 인증·닉네임과 양방향 차단 상태를 검사합니다. 수락·거절은 받은 사람만, 취소는 보낸 사람만, 친구 삭제는 관계의 당사자만 가능합니다.
- 새 요청은 비공개가 아닌 대상에게만 허용하지만 발신자 자신의 위치 공개는 요구하지 않습니다. 비공개 발신자가 요청하면 수신자에게 닉네임이 표시되는 의도적인 공유입니다. 수락·삭제는 프로필 공개 설정이나 위치 공유 상태를 바꾸지 않습니다.
- 기존 친구 테이블에 `relationship_id`를 추가하여 오래된 요청 화면이 재요청을 조작하지 못하게 합니다. 같은 요청의 재전송과 수신자의 중복 수락은 무해하게 처리하지만 상호 요청을 자동 수락하지 않습니다.
- 참여자의 인증 행·계정 제어 행·프로필을 고정된 순서로 잠그고 관계 상태를 검사합니다. 새 요청은 5초 간격·한 시간에 30번·친구와 요청 합계 계정당 500개로 제한하며 취소해도 발송 예산은 복원하지 않습니다.
- 발송 제한 테이블은 비노출 스키마에 두고 RLS 기본 거절과 테이블 권한 회수로 클라이언트 접근을 막습니다. 공개 함수는 호출자 권한으로 비공개 검사 함수에 연결하며 비로그인 실행 권한과 친구 테이블 직접 쓰기 권한은 추가하지 않습니다. 권한 근거: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
- 로컬 PostgreSQL 16에서 `tests/friends.sql`과 기존 가입·지도·보안·기록 테스트가 통과했습니다. 실제 서버에서는 새 함수 실행 권한, 비로그인 및 빈 세션 차단, 직접 쓰기 차단, RLS와 마이그레이션 이력을 확인했습니다. iPhone 시뮬레이터의 실제 로그인 세션으로 미인증 목록 조회와 검색 제한도 확인했습니다. 원격에 가짜 가입 계정이나 친구 요청을 남기지 않았습니다.
- 적용 후 보안 점검에서 새 경고는 없었습니다. 발송 제한 테이블의 정책 없음 안내는 의도적인 기본 거절 구성입니다. 기존 공개 가입 함수 실행 경고와 [유출 비밀번호 보호 미설정](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)은 변경하지 않았습니다. 공개 함수 실행 점검 안내: [비로그인 실행](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [로그인 사용자 실행](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

두 실제 계정에서 이메일 인증·닉네임 등록 후 검색 → 요청 → 상대 수락 → 친구 공개 위치 확인 → 친구 삭제 후 위치 권한 회수를 검증해야 합니다. 소셜의 30초 갱신은 화면이 열린 동안만 수행하며 푸시 알림과 함께 달리기 초대는 포함하지 않습니다.

## 회원가입

가입·닉네임·테스트 가입 마이그레이션(005~007)과 약관 제거 마이그레이션(20261001000100)을 연결된 개발 프로젝트에 적용합니다.
가입 완료에는 별도 약관 동의가 필요하지 않습니다.

### 개발용 테스트 가입

- 디버그 앱은 서버의 `registration_test_mode()`가 허용하면 별도 테스트 가입 기록을 만들 수 있습니다. 이메일 확인 정책은 유지합니다.
- 현재 일반 가입은 약관 없이 완료되므로 테스트 가입은 과거 개발 데이터 검증용으로만 유지합니다.
- 이메일 인증, 닉네임 등록 및 소셜 제한은 생략하지 않습니다.
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
- 이메일 인증을 완료한 뒤 별도 화면에서 닉네임을 등록합니다. 인증 후 등록을 취소해도 개인 기능은 사용할 수 있습니다.
- 닉네임은 한글 완성형·영문·숫자·밑줄 2~30자이며 기존 고유 인덱스로 대소문자 중복을 차단합니다. 공백은 허용하지 않습니다.
- `set_my_nickname`은 현재 사용자만 대상으로 삼으며 가입·이메일 인증을 서버에서 확인합니다. 직접 프로필 닉네임 수정 권한은 제거합니다.
- 최초 닉네임 등록 이후 변경은 서버 시각 기준 30일에 한 번입니다. 동일한 이름 재요청은 변경 시각을 갱신하지 않습니다.
- 이메일 인증과 닉네임 등록을 모두 완료해야 소셜 쓰기와 위치 공유가 가능합니다. 인증된 비공개 사용자의 게시글·댓글 작성은 허용됩니다.
- 006 적용 시 기존 미인증 선점 닉네임은 해제하고 인증된 이름은 유지합니다. 적용 전 대상 데이터를 확인해야 합니다.
- 이메일 전환은 기존 닉네임과 개인 기록을 삭제하지 않으며 전화번호가 없어도 확인된 이메일만으로 소셜 인증을 인정합니다.
- 가입·메일 요청 빈도 제한은 Supabase Auth 설정에서 관리합니다. 이번 변경은 원격 제한 설정을 변경하지 않았습니다. 출시 전 [인증 요청 제한](https://supabase.com/docs/guides/auth/rate-limits)과 CAPTCHA를 점검해야 합니다.
- 약관 제거 마이그레이션은 `registration_terms`, `registration_consents`를 삭제하고 `complete_registration()`을 인자 없이 호출하도록 변경합니다.
- 미완료 계정의 앱 데이터 접근은 DB 정책에서도 제한합니다. 가입 완료 후 이메일 인증에 따른 개인·소셜 권한 구분을 적용합니다.

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

## 이메일 인증 운영

소셜 권한은 확인된 이메일로 검사하며 문자 발송 업체 연결은 필요하지 않습니다. 원격 Email 인증은 활성화, 이메일 자동 확인은 비활성화, Phone 인증은 비활성화 상태입니다.

1. Supabase 인증의 이메일 확인 필수 설정을 유지합니다. 자동 확인 또는 운영 DB의 확인 시각 수동 변경으로 인증을 우회하지 않습니다.
2. Redirect URLs에 `runspot://login-callback`을 등록합니다. 앱은 신규 가입·재전송·이메일 등록 요청 모두 이 주소를 전달합니다.
3. Supabase 기본 메일 발송은 수신자와 발송량이 제한되므로 일반 사용자에게 운영 서비스를 제공하려면 [사용자 지정 SMTP](https://supabase.com/docs/guides/auth/auth-smtp)를 준비합니다. SMTP 비밀은 앱이나 저장소에 넣지 않으며 이메일 전환 자체가 운영 발송 비용을 없애지는 않습니다.
4. 앱은 60초 재전송 대기를 제공하지만 실제 발송 제한은 서버가 강제합니다. 메일 발송 성공만으로 인증 완료로 처리하지 않고 서버 상태를 다시 확인합니다.
5. 이메일 변경 요청·인증 해제 시 프로필을 비공개로 되돌리고 공개 위치를 삭제합니다. 확인 완료 후에도 위치 공유를 자동으로 켜지 않습니다.
6. 실제 기기에서 신규 메일 수신·링크 만료·재전송·앱 복귀와 두 계정의 친구 기능을 검증합니다. CAPTCHA 연동은 이번 범위에 포함하지 않습니다.

일반 이메일 소유 확인은 관리자 다중 인증(`aal2`)과 별개입니다.
신규 소셜 서버 API에서는 서비스 역할로 데이터를 변경하기 전에 JWT 검증과 현재 이메일 확인·계정 상태 검사를 모두 수행해야 합니다. 개인 기록은 이메일 인증과 분리하되 로그인·본인 소유권·활성 계정 검사를 유지합니다.

## 러닝 종료 기온

- `runs.temperature_c`, `temperature_observed_at`은 함께 비우거나 함께 저장합니다. 허용 범위는 -80~60°C, 원래 종료 시각보다 2시간 전부터 15분 후까지의 유한 관측 시각입니다. 현재 업로드 시각을 기준으로 하지 않아 지연된 오프라인 기록도 원래 기온을 유지합니다.
- `save_my_run_with_temperature`은 공개 스키마의 호출자 권한 래퍼와 비공개 스키마의 본인·활성 계정 검사로 분리합니다. 익명 실행과 직접 쓰기는 허용하지 않습니다. 최초 삽입에 기온을 함께 기록하고 중복 재전송 시 값 변경을 거절합니다. 경로 검증이 실패하면 전체 저장을 취소합니다.
- 기존 기온 없는 기록의 재시도는 빈 값으로 유지합니다. 앱이 전달하는 개인 관측 스냅샷이며 공식 검증 데이터·위치 인증·보상 근거로 사용하지 않습니다. 날씨 함수나 외부 API 예산·AI 입력은 변경하지 않았습니다. 갤러리 사진은 서버로 보내지 않습니다.
- PostgreSQL 16에서 SQL 테스트 13개와 별도 20개 동시 연결 저장·10개 변경 재시도 거절 테스트가 통과했습니다. 원격 기존 기록의 기온은 모두 빈 값이며 새 공개 함수의 익명 실행 금지·호출자 권한을 확인했습니다. 새 보안 경고는 추가되지 않았고 기존 공개 권한 함수 경고는 유지됩니다. [기존 함수 경고 안내](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)

```sh
TEMPERATURE_TEST_SOCKET=<격리된_기온_DB_소켓> \
TEMPERATURE_TEST_PSQL=<psql_경로> \
deno test --allow-env=TEMPERATURE_TEST_SOCKET,TEMPERATURE_TEST_PSQL \
  --allow-run=<psql_경로> supabase/tests/temperature_concurrency_test.ts
```

## 러닝 경험치·레벨

- `public.runs` 삽입 트리거가 비공개 `run_rewards`에 기록당 보상을 한 번만 저장합니다. 앱은 경험치를 쓰지 않고 `my_progress()`, `my_run_reward(requested_run_id)`로 본인 값만 조회합니다. 재전송·응답 유실 후 재조회해도 같은 결과를 반환합니다.
- 보상은 `10 + 100m당 1XP`, 기록당 최대 300XP, 종료일(한국 시간) 기준 하루 최대 500XP입니다. 300m 미만, 평균 속도 6.5m/s 초과, 종료 7일 뒤 전송된 기록은 저장하되 0XP와 사유를 남깁니다. 계정별 잠금으로 동시 저장의 한도 계산을 직렬화합니다.
- 레벨 L에서 다음 레벨까지 `100 + 50×(L-1)`XP가 필요하며 최대 Lv.99입니다. 기기 측정값 기반의 참고 보상이며 검증 상태나 랭킹에 반영하지 않습니다. 수치는 초기 제안값이므로 운영 전 서비스 기준과 맞추세요.
- 보상 도입 전 기록과 타인 기록은 모두 `unavailable`로 응답해 존재 여부를 드러내지 않습니다.

## AI 러닝 피드백

- `functions/run-feedback/`는 플랫폼 JWT 검사 후 Auth `getUser()`로 사용자를 확인하고, 현재 활성 계정과 본인 기록을 다시 검사합니다. 새 생성에는 현재 이메일 확인이 필요합니다. 닉네임·전화번호·위치 공개 설정을 바꾸지 않습니다.
- `my_run_feedback(requested_run_id)`는 본인 저장 결과와 서버의 다음 요청 시각을 반환합니다. 생성은 사용자 동의 후 Edge Function에 기록 식별자 하나만 전송합니다. `reserve_run_feedback`, `finish_run_feedback`는 서버 역할만 실행합니다. 공개 RPC는 호출자 권한이며 내부 권한 함수는 비노출 스키마에 있습니다.
- `feedback_requests`는 실제 외부 호출 전 원자적으로 예약합니다. 계정 행 잠금과 전체 예산 행 잠금으로 서로 다른 기록·기기·서버 프로세스의 동시 요청을 직렬화합니다. 요청 시작부터 72시간이며 실패·시간 초과·서버 중단도 환불하지 않습니다. 예약된 요청에는 자동 재전송을 하지 않습니다.
- 전체 서비스는 이동 24시간 100회·이동 30일 1,000회 상한입니다. 관리 예산 설정은 비공개 `feedback_limits`에 있으며 0이면 새 호출을 차단합니다. 증액은 예산 승인 후 서버 관리 작업으로 진행합니다. 계정·기록 삭제 후에도 식별자를 제거한 요청 이력은 전체 호출 예산에 남습니다. 다른 앱이나 관리 스크립트의 같은 키 사용은 이 예산에 포함되지 않습니다.
- 현재 모델은 안정 버전 `gemini-3.5-flash-lite`입니다. 한 요청은 후보 1개·출력 최대 768토큰, 텍스트 지시문과 숫자 요약 합계 4,096바이트 이하입니다. Google 검색·지도·음성·대화 이력·자동 재시도는 사용하지 않습니다. 응답은 최대 32KB, 한국어 피드백 최대 500자로 검증하며 잘리거나 잘못된 출력은 저장하지 않습니다.
- 비교 대상은 현재 러닝 시작 전 30일 안의 최대 5회 기록입니다. 현재 거리·시간·페이스와 이전 합계·평균만 전송하며 이메일·전화번호·닉네임·계정/기록 식별자·날짜·좌표·사용자 입력 문장은 보내지 않습니다. 기기 측정값을 검증된 운동 성과로 단정하거나 의료 진단·경험치 지급에 사용하지 않습니다.
- 서버에 저장된 완료 기록 중 거리 100m·활동 시간 60초 이상만 새 생성 대상입니다. 비교 기록이 없어도 현재 기록이 충분하면 분석할 수 있으며 비교 한계를 명시합니다. 기록 저장 자체는 이 조건과 무관하게 기존대로 유지됩니다.
- 실패 원문·키·개인 기록은 로그와 앱 오류에 노출하지 않습니다. 실패 시 사용량을 모르면 `ai_usage`의 0은 미확인 값이며 무료 호출이라는 의미가 아닙니다. 비용 제한은 사용량 로그가 아니라 환불하지 않는 예약 횟수로 강제합니다.
- `GEMINI_API_KEY`는 Dashboard의 Edge Functions → Secrets에만 등록합니다. 무료 Gemini 요금제의 데이터 개선 사용 여부와 유료 요금제 정책을 확인한 뒤 운영 데이터를 처리합니다. 참고: [키 보안](https://ai.google.dev/gemini-api/docs/api-key), [모델](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite), [요금·데이터 정책](https://ai.google.dev/gemini-api/docs/pricing).

```sh
supabase db push --linked
supabase functions deploy run-feedback --project-ref rtdlluilhkcdghoakyrp --use-api
cd supabase/functions/run-feedback
npx --yes deno@2.5.4 check index.ts
npx --yes deno@2.5.4 test feedback_test.ts
```

`tests/run_feedback.sql`은 격리된 로컬 DB에서만 실행합니다. `tests/feedback_concurrency_test.ts`는 인증 대역이 있는 `/private/tmp/runspot-feedback-db.` 경로의 Unix 소켓·55439 포트만 허용합니다. `FEEDBACK_TEST_SOCKET`, `FEEDBACK_TEST_PSQL`을 설정하고 해당 변수 읽기·psql 실행 권한만 허용해 실행합니다. 실제 Supabase에는 테스트 계정을 생성하지 않습니다.

앱 테스트 187개, SQL 테스트 12개, AI 함수 테스트 7개와 동시 DB 연결 테스트가 통과했습니다. 원격 실행 권한·요청 이력 0건과 iPhone 시뮬레이터의 자료 부족 표시를 확인했습니다. 대상 실계정의 기존 기록이 모두 0m이므로 실제 Gemini 생성과 토큰 사용량·요금 확인은 충분한 실제 러닝 기록 저장 후 검증해야 합니다. 현재 원격에는 가짜 기록이나 피드백을 추가하지 않았습니다. 새 비공개 테이블 2개의 RLS 정책 없음 안내는 직접 접근 거부 설계이며, 공개 권한 함수 관련 경고는 기존 항목 외 추가되지 않았습니다.

## 선택 전화번호 인증

- `my_phone_verification_state()`는 현재 활성 계정의 번호·변경 예정 번호·확인 상태만 반환합니다. 대상 사용자 식별자를 받지 않으며 비로그인 실행 권한은 없습니다. 공개 함수는 호출자 권한으로 비노출 스키마의 내부 함수에 연결합니다.
- 번호가 존재하고 `phone_confirmed_at`이 있으며 `phone_change`가 없고 익명 계정이 아니어야 확인 상태를 인정합니다. 사용자 메타데이터와 과거 토큰은 확인 근거로 사용하지 않습니다.
- 앱은 Supabase Auth의 번호 등록·변경 요청과 `phone_change` 유형의 인증번호 검증을 사용합니다. 발송 성공이나 코드 API 응답만으로 완료를 표시하지 않고 서버 상태를 다시 조회합니다. 프로필 공개·소셜·실시간 위치 권한은 이메일 인증 기준을 유지합니다.
- Phone 제공업체와 문자 발송 업체 연결은 아직 비활성화 상태입니다. 운영에서 실제 문자 인증을 제공하기 전 발송 제한·업체 요금·수신·만료·재전송을 검증해야 합니다.
- 사용자가 명시적으로 지정한 테스트 계정에 한해 관리자 API의 `phone_confirm`으로 수동 확인할 수 있습니다. 관리자 키는 보호된 관리 환경에서만 사용하고 앱·저장소·명령 인자·로그에 넣지 않습니다. 수동 인증은 실제 번호 소유 또는 SMS 수신을 검증한 결과가 아닙니다. 일반 계정 자동 인증이나 고정 OTP 우회는 추가하지 않습니다.

## 기록 저장 보안 점검

- `runs`의 RLS와 본인 조회 정책은 유지하며 일반 사용자의 직접 INSERT·UPDATE 권한은 없습니다. 저장 RPC의 실행 권한은 로그인 사용자에게만 부여합니다.
- 기록 요청은 측정 계정의 로그인 세션에 고정하며 계정이 바뀐 후 이전 요청의 결과를 화면에 반영하지 않습니다.
- 비공개 스키마의 RLS 정책 없음 안내는 일반 사용자의 직접 접근을 거부하는 기존 설계입니다. RPC는 현재 사용자와 활성 계정을 검사합니다.
- Supabase의 [로그인 사용자 실행 가능 권한 함수 안내](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)는 `save_my_run()`에도 표시됩니다. 의도한 API이며 소유자 입력·검증 상태 변경·타인 기록 조회를 허용하지 않습니다.
- 기존 Auth의 [유출 비밀번호 검사 미설정 경고](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)는 이번 기능 범위에서 변경하지 않았습니다.

## 러닝 환경 조회

- `20261009111535_running_conditions.sql`, `20261009191148_environment_shared_budget.sql`과 `functions/running-conditions/`가 필요합니다. 함수의 `verify_jwt`는 켜 두며 플랫폼 검사 후 `getUser()`와 현재 활성 계정 검사를 추가로 수행합니다. 개인 환경 조회에는 이메일 인증을 요구하지 않습니다.
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

## 개인 통계·친구 주간 거리 조회

- `my_run_statistics()`는 활성 계정의 본인 기록 전체에서 주간 거리, 누적 완료 수, 페이스 계산용 누적 거리·활동 시간을 반환합니다. 개인 기록에는 이메일 인증을 요구하지 않습니다. 0 거리·0 활동 시간 기록은 횟수에 포함하고 페이스에서만 제외합니다.
- `friend_weekly_ranking()`은 이메일 인증·닉네임 등록을 완료한 활성 계정에 본인과 공개 가능한 수락 친구의 주간 누적 거리를 반환합니다. 비공개·차단·정지·미인증·미수락·비친구는 제외하며 같은 거리는 `rank()`로 공동 순위를 부여합니다. 기록 없는 친구는 0m입니다.
- 한국 시간 월요일 0시를 기준으로 `ended_at`을 반개구간으로 조회하고 미래 기록을 제외합니다. 서버 세션 시간대와 앱의 기록 목록 페이지 수에 의존하지 않습니다. `runs(user_id, ended_at)` 인덱스를 추가합니다.
- 랭킹은 `rejected` 기록을 제외하고 `pending` 개인 측정값을 포함하는 친구 간 거리 비교입니다. 개인 원본·경로의 본인 전용 정책과 기록 검증 상태는 바꾸지 않습니다. 공개 응답에는 사용자 식별자와 개별 러닝 시각을 넣지 않습니다.
- 공개 함수는 호출자 권한으로 비노출 스키마의 검사·집계 함수에 연결하며 비로그인 실행 권한을 회수합니다. 내부 함수도 로그인·계정 상태를 검사하고 빈 검색 경로를 사용합니다. 기존 함수와 테이블을 삭제하거나 수정하지 않습니다.
- `tests/run_statistics.sql`은 주간 경계·미래 기록·0 거리·0 시간·누적 통계·공동 순위·비공개·차단 양방향·친구 삭제·미인증·정지·비로그인·원본 접근 차단을 검증합니다. 기존 마이그레이션 적용 뒤 새 마이그레이션과 함께 실행합니다.

검증 결과: 격리된 PostgreSQL 16의 SQL 테스트 15개와 앱 테스트 254개가 통과했습니다. 전체 정적 검사에는 기존 `lib/screens/profile_screen.dart` 안내 4건만 남아 있으며 새 코드 관련 항목은 없습니다. 사용자의 명시적 배포 승인 후 2026-10-20 연결된 RunSpot 프로젝트에 적용했습니다. 읽기 전용 트랜잭션으로 실제 기록과 개인 통계의 일치, 랭킹 응답, 비로그인 실행 차단, 타인 원본 기록 차단을 확인했습니다. 배포 후 새 보안 점검 항목은 없으며 검증용 계정·러닝 기록은 추가하지 않았습니다.

## 러닝 시 자동 위치 공유 설정

- `run_location_preferences`는 계정별 `enabled` 설정만 보관합니다. 기존 계정은 행이 없으면 꺼짐으로 해석하며 새 행의 기본값도 꺼짐입니다. 앱은 프로필에서 저장하고 러닝 시작·재개 시 적용합니다.
- 기본 테이블 접근을 회수한 뒤 로그인 계정에 조회·생성·수정만 허용하고, 모든 정책에서 본인 식별자와 활성 계정을 확인합니다. 타인의 설정 조회·수정·생성, 소유권 변경과 클라이언트의 직접 삭제는 차단합니다. 이메일 인증이나 프로필 공개 범위는 변경하지 않습니다.
- `20261020125728_run_location_preferences.sql`은 새 설정 테이블과 본인 전용 정책만 추가합니다. 기존 위치 공유·친구·기록 테이블과 정책은 변경하지 않습니다. 사용자 배포 승인 후 2026-10-20 연결된 RunSpot 프로젝트에 적용했습니다. 기본 미동의 상태·비로그인 조회 차단·본인 저장 권한과 타인 설정 비노출을 확인했으며 새 보안 점검 항목은 없습니다.
- `tests/run_location_preferences.sql`은 기본값, 본인 저장, 계정 분리, 소유권 변경, 비로그인·정지 계정 차단을 검증합니다.

프로필 자동 공유 설정 검증: 앱 테스트 270개·로컬 SQL 테스트 16개·변경 코드 정적 검사를 통과했습니다. 실제 사용자 설정과 위치 공유 동의는 검증 과정에서 켜지 않았습니다.

## 2026-10-21 구현·검증 및 서버 반영

사용자의 명시적 승인 후 기존 21개 다음에 아래 3개를 연결된 RunSpot 프로젝트에 적용했습니다. 미리보기에서 이 3개만 미적용임을 확인했고, 기존 데이터 삭제 없이 적용 이력 24개를 확인했습니다. 관리자 지정은 스키마 마이그레이션과 분리하여 사용자가 지정한 두 계정에만 수행하고 감사 로그를 남겼습니다.

1. `20261021064307_user_block_management.sql`: `my_blocks()`, `change_my_block(target_id, blocked)`. 본인 목록만 조회하며 차단은 친구 변경과 같은 순서로 계정·프로필을 잠급니다. 차단 시 친구·대기 요청을 삭제합니다.
2. `20261021064904_achievements_and_integrity_review.sql`: `my_achievements()`, `review_cases()`, `resolve_review(case_id, decision, note)`. 실제 업적 3개, 기록 변경에 따른 재집계, 평균 속도 6.5m/s 초과 검토, 현재 DB 관리자 역할과 `aal2`, 본인 검토 금지, 사유·감사 이력의 원자적 확정입니다. 반려 보상은 원본 지급 이력을 유지하고 현재 경험치 합산에서 제외하며 이후 지급도 이 잔액을 기준으로 계산합니다.
3. `20261021065535_group_running.sql`: `group_dashboard()`, `group_action(requested_group, operation, target_id, client_id)`. 비공개 그룹·참여자 테이블, 친구 초대·응답·취소·나가기·GPS 준비·10초 뒤 출발 예약·본인 러닝 연결과 저장 후 자동 결과 확정입니다. 타인의 개인 경로는 반환하지 않습니다. 차단 시 공통 활성 그룹을 취소합니다.

그룹 작업은 `create`, `invite`, `accept`, `reject`, `cancel_invite`, `leave`, `cancel`, `ready`, `unready`, `start`, `join_run`입니다. 그룹은 최대 8명, 생성 시간당 5개·초대 시간당 30회이며 대기 30분·진행 24시간으로 제한합니다. 초대 행은 재사용하지 않아 오래된 초대의 수락이 새 초대에 적용되지 않습니다. 최근 20개 그룹만 조회합니다. `join_run`은 공동 출발 전후 제한된 시간 안에 본인의 불변 러닝 식별자를 예약하며 서버 저장 트리거가 같은 계정·식별자와 시작 시각을 확인해 결과를 연결합니다.

관리 승인·반려는 최종 처리이며 동일 결정 재시도만 허용합니다. 승인해도 평균 속도·짧은 거리·동기화 지연·일일 한도에 관한 기존 경험치 제외 기준은 유지합니다. 반려 기록도 개인 기록과 개인 통계에는 남지만 친구 거리 비교·업적·현재 경험치·그룹 결과에서는 제외됩니다. 서버 관리자 계정과 인증 앱의 실제 연동은 별도 기기 검증이 필요합니다. 푸시 알림·소명 요청·계정 정지는 이번 관리 기능에 포함하지 않습니다.

로컬 SQL 검증은 `tests/blocks.sql`, `tests/achievements_and_review.sql`, `tests/group_running.sql`과 기존 회귀 검사로 수행합니다. 새로운 테이블은 비공개 스키마에 두고 RLS를 활성화하며 클라이언트 직접 접근을 거부합니다. 공개 RPC는 보안 호출자 함수이고 내부 권한 상승 함수는 빈 검색 경로·호출자 및 현재 권한 검사를 적용합니다.


서버 반영 검증: 두 지정 계정의 활성 상태와 관리자 역할, 다중 인증 전 관리 조회 차단, 다중 인증 조건을 만족하는 DB 권한 검사에서 관리 목록·업적·차단·그룹 조회, 비로그인·역할 없는 계정·역할 원본 조회 차단을 트랜잭션 안에서 확인하고 검증 작업은 롤백했습니다. 실제 인증 토큰을 위조하거나 인증 앱 등록 상태를 변경하지 않았습니다. 검증용 계정·러닝 기록을 추가하지 않았으며 기존 기록은 17개, 자동 검토 대상은 0개입니다.

두 관리자 계정의 인증 앱 등록은 아직 0건입니다. 각 계정에서 앱의 `관리 → 관리자 다중 인증`으로 인증 앱에 키를 등록하고 실제 6자리 코드를 입력해야 합니다. 실제 인증 앱을 통한 검증은 사용자 작업으로 남아 있습니다.

배포 후 보안 점검에 새 경고 수준 항목은 없습니다. 그룹 비공개 테이블 2개의 [RLS 정책 없음 안내](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)는 클라이언트 직접 접근을 거부하는 설계에 해당하며 RPC의 호출자 검사를 별도로 검증했습니다. 기존 공개 권한 상승 함수와 유출 비밀번호 보호 설정 경고는 이번 배포에서 변경하지 않았습니다.

## 게시판 API

- 게시글과 동네 설정은 비노출 스키마 테이블에 두고 RPC로만 접근합니다. 직접 테이블 권한은 부여하지 않습니다.
- `board_feed(requested_board, requested_topic, before_at, before_id)`는 로그인한 활성 계정에 `local`·`national` 글을 최신순 20개씩, `race` 공지는 한국 날짜 기준 오늘 이후 일정 50개를 날짜순으로 반환합니다. 정지 계정과 양방향 차단 상대의 글은 제외합니다. 응답의 `can_write`·`can_post_race`·`can_moderate`로 화면 버튼을 정합니다.
- 동네 글은 `set_my_board_region()`으로 고른 `시·도 시·군·구`의 주민 글만 보여주며 작성 당시 동네에 고정됩니다. 동네 변경 횟수는 제한하지 않습니다.
- `create_board_post()`는 이메일 인증과 닉네임 등록이 끝난 계정만 사용할 수 있고 대회 공지는 관리자 역할과 다중 인증이 필요합니다. 작성 간격 30초·하루 20개로 제한하며 `client_id`로 재전송 중복을 막습니다.
- `delete_board_post()`는 본인 글 또는 관리자의 삭제만 허용하고 관리자가 타인 글을 지우면 감사 기록을 남깁니다.
- 좋아요(`set_board_like`)·댓글(`board_comments`, `create_board_comment`, `delete_board_comment`)은 목록에서 볼 수 있는 글에만 허용합니다. 동네 글은 같은 동네 주민과 작성자만 반응할 수 있고, 차단 상대의 좋아요·댓글은 개수와 목록에서 제외합니다.
- 댓글은 1~500자, 5초 간격·하루 100개이며 `client_id`로 재전송 중복을 막습니다. 본인 댓글 또는 관리자 삭제만 허용하고 관리자 삭제는 감사 기록을 남깁니다.
- `update_my_board_post()`에 선택 인자 `requested_images`를 더해 글 수정 때 사진도 바꿉니다. null이면 기존 사진을 유지하므로 이전 앱의 수정도 그대로 동작합니다. 수정 충돌 확인(`expected_updated_at`)과 같은 내용 재전송 처리는 기존 규칙을 따릅니다.
- 사진은 글당 4장, 비공개 `board-images` 버킷의 `작성자ID/무작위ID.jpg`(3MB 이하 JPEG)만 허용합니다. 업로드는 이메일 인증 계정의 본인 폴더만, 조회는 본인 사진이나 볼 수 있는 글에 연결된 사진만 가능하며 앱은 1시간짜리 서명 주소로 표시합니다. 앱이 사진을 다시 저장해 촬영 위치 등 메타데이터를 제거합니다.
- 글 삭제나 수정으로 빠진 사진 파일은 작성자 앱이 지웁니다. 관리자 삭제나 앱 종료로 남은 파일을 정리하는 서버 작업은 후속 과제입니다.
- 로컬 PostgreSQL 16에서 `tests/board.sql`, `tests/board_engagement.sql`과 기존 SQL 테스트 전체가 통과했습니다. 로컬에서는 19번 마이그레이션 전에 `tests/local_storage_stub.sql`(Storage 대역)을 실행하고, 모든 마이그레이션 적용 후 두 게시판 테스트를 마지막에 실행합니다.


## 사용성 보완

`app_usability_improvements`는 본인 러닝의 숨김·복원, 인정 완료 횟수, 관리 메뉴 역할 확인, 게시글 수정·신고·처리를 추가합니다. 숨김은 `runs.hidden` 표시만 바꾸며 보상·업적·랭킹·개인 통계의 원본은 보존합니다. 완료 횟수만 거리·시간 양수 및 보류·반려 제외 기준으로 맞춥니다.

관리 메뉴 조회는 본인 역할 존재 여부만 반환합니다. 실제 관리자 조회·처리는 기존 역할·다중 인증 검사를 유지합니다. 신고 자료는 RLS가 적용된 비공개 스키마에 저장하며 일반 사용자의 직접 조회·변경을 차단합니다. 타인 글 수정·본인 글 신고·본인 글 신고 처리·조회할 수 없는 동네 글 신고를 차단하며 동일 글 중복 신고와 일일 20건 초과 접수를 제한합니다. 신고 당시 글을 보존하고 관리자 처리와 감사 이력은 같은 트랜잭션으로 확정합니다.

`tests/app_usability.sql`은 숨김의 보상 불변성·타인 접근 차단·완료 횟수·메뉴와 실제 권한 분리·편집 충돌·신고 중복·처리 감사와 근거 보존을 검증합니다. `rollback/app_usability_improvements.sql`은 새 숨김·신고 자료가 있으면 자동 복구를 중단합니다. 복구해도 이미 편집한 글의 본문은 보존합니다.

`tests/board_moderation_concurrency_test.py <psql 경로> <격리된 로컬 소켓>`은 같은 편집본의 동시 수정 중 한 건만 반영되는지, 동일 글 동시 신고가 한 건으로 접수되는지, 관리자 중복 처리에서 감사 이력이 한 번만 생성되는지 검사합니다. 실제 서버 실행을 막기 위해 `/private/tmp/runspot-splits-db.` 접두사와 55441 포트의 로컬 인증 대역만 허용합니다.
