# 활동 알림·오류 수집·게시판 사진 정리

## 적용 범위

- 설정 → 알림 설정에서 휴대폰 권한을 요청하고 친구 요청·함께 달리기 초대·댓글/답글의 수신 여부를 계정별로 저장합니다. 앱 시작 시에는 권한창을 띄우지 않습니다.
- 푸시는 잠금 화면에 닉네임·댓글 본문·좌표를 표시하지 않습니다. 전경에서는 확인 버튼이 있는 앱 안내를 표시합니다. 백그라운드·종료 상태에서는 운영체제 알림을 사용하고 누르면 친구 요청·함께 달리기·게시글로 이동합니다. 이동 뒤 실제 접근 권한은 기존 서버 조회에서 검사합니다.
- 기기는 로그인 세션에 연결합니다. 명시적 로그아웃 전에 대기 중 등록을 마치고 서버 연결과 FCM 토큰을 해제합니다. 계정 삭제·서버 세션 삭제에도 연결이 연쇄 삭제됩니다. 권한 거부 후 앱에 복귀하면 서버 연결을 제거합니다. 등록 중 네트워크 오류는 앱이 전경에 있을 때 30초부터 최대 5분 간격으로 재시도합니다.
- 전송 대기는 최대 15분, 기기는 마지막 등록 후 30일, 작업 원본은 하루 보관합니다. 작업당 기기별 최대 5회 재시도하며 한 번에 20건을 가져옵니다. 같은 작업은 임대로 중복 실행을 막고 운영체제의 알림 식별자도 고정합니다. 외부 발송 성공 직후 서버가 끊긴 경우의 재전송까지 정확히 한 번으로 보장할 수는 없습니다.
- 발송 직전 수신 설정·정지·양방향 차단·요청 취소·그룹 만료·댓글 및 글 접근 권한을 확인합니다. 새 기기에는 등록 전 과거 알림을 보내지 않습니다. 좋아요는 기존 앱 내부 알림만 유지합니다.
- 사진은 업로드 후 24시간이 지나고 현재 게시글과 신고 원문 어디에서도 참조하지 않을 때만 격리합니다. 한 번에 최대 100개를 Storage API로 제거합니다. 격리된 파일은 재첨부할 수 없고 삭제 실패 시 다음 작업에서 재시도합니다. 사용자가 글을 쓰다가 오래 머문 경우 만료된 사진을 다시 첨부하라는 안내가 나옵니다.
- 오류 수집은 출시 빌드의 Flutter 오류·처리되지 않은 비동기 오류·러닝 추적·기기 저장·서버 전송 실패를 수집합니다. 다트 예외 본문 대신 고정 분류와 앱 패키지 내부 코드 위치만 보냅니다. 사용자 ID·이메일·토큰·GPS·요청 본문·사용자 로그를 추가하지 않습니다. 동일 위치의 오류는 실행당 한 번, 최대 30종으로 제한합니다. 네이티브 충돌 보고서는 다음 출시 실행 시 전송하며 Firebase가 기본 기기·앱·충돌 정보를 수집합니다. 운영체제 강제 종료·사용자 강제 종료·배터리로 인한 모든 종료가 충돌 보고서로 남는 것은 아닙니다.

## 현재 반영 상태

로컬 코드와 격리 데이터베이스 검증을 완료했습니다. 전체 Flutter 테스트 377개, 서버 함수 테스트 5개, 전체 SQL 테스트와 iOS 개발 빌드(서명 제외)가 통과했습니다. Android 빌드는 이 환경에 Android SDK가 없어 확인하지 못했습니다. 운영 마이그레이션 적용과 `operations-worker` 함수 배포를 완료했습니다. 비밀 없는 외부 요청의 401 거부와 서버 전용 RPC 권한을 확인했습니다. 사용자가 Firebase 서비스 계정·함수 비밀 등록과 데이터베이스의 `operations_worker_config` 연결을 완료했습니다. 한국 시각 2026년 11월 1일 00시 13분 예약 실행에서 상태 200을 확인하여 작업 비밀 인증·Firebase OAuth 인증·발송 대기열 조회·사진 정리 대상 조회가 정상임을 검증했습니다. 확인 당시 등록된 기기는 0대여서 실제 발송·수신 검증은 아직 하지 않았습니다. Apple 개발자 계정이 없어 APNs 등록과 iOS 푸시는 보류하고 Android부터 검증합니다.

## 서버 설치

1. `supabase/migrations/20261031151109_push_delivery_and_photo_cleanup.sql`을 적용합니다. 이전 마이그레이션을 모두 적용한 서버가 필요합니다. 예약 작업은 설정 행이 없으면 아무 외부 요청도 하지 않습니다.
2. Firebase 프로젝트 `capstone-running`에서 FCM HTTP v1 API를 활성화하고 발송 권한이 있는 서비스 계정을 준비합니다. 서비스 계정 JSON은 앱이나 저장소에 넣지 않습니다.
3. 비밀 파일을 저장소 밖에 만들고 Supabase 함수 비밀로 등록합니다. `FIREBASE_SERVICE_ACCOUNT`에는 서비스 계정 JSON 한 줄, `OPERATIONS_WORKER_SECRET`에는 암호학적으로 생성한 32자 이상의 무작위 비밀을 넣습니다. 키 내용은 채팅·터미널 출력·커밋에 남기지 않습니다.

```sh
supabase secrets set --env-file /안전한/경로/operations.env
supabase functions deploy operations-worker --no-verify-jwt
```

함수는 일반 사용자 JWT 대신 `x-worker-secret`을 자체 검증합니다. Supabase가 제공하는 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`도 사용합니다.

4. 데이터베이스 소유자만 접근할 수 있는 SQL 편집기에서 아래 설정을 등록합니다. 비밀은 함수에 등록한 값과 같아야 합니다. 실제 값이 있는 SQL을 파일로 커밋하지 않습니다.

```sql
insert into runspot_private.operations_worker_config(singleton,endpoint,secret)
values(true,'https://프로젝트참조.supabase.co/functions/v1/operations-worker','서버에만 등록할 무작위 비밀')
on conflict(singleton) do update set endpoint=excluded.endpoint,secret=excluded.secret;
```

5. `select runspot_private.run_operations_worker();` 실행 후 `select * from runspot_private.operations_worker_state;`의 최근 상태를 확인합니다. 이후 1분마다 예약 실행합니다. 상태 200은 정상, 503은 푸시 또는 사진 정리에 확인이 필요함, 0은 네트워크·실행 오류입니다. 함수 응답에는 성공 개수와 확인 필요 여부만 있으며 토큰과 파일 경로는 없습니다.

Firebase 설정이 없거나 인증에 실패해도 사진 정리는 독립적으로 수행합니다. 사용자별 테스트 전에 서비스 계정 프로젝트 ID가 앱의 Firebase 프로젝트와 같은지 확인합니다.

## 모바일 설정과 실기기 검증

- Android는 Crashlytics Gradle 플러그인과 알림 권한을 포함합니다. Firebase 콘솔에서 Crashlytics를 활성화합니다.
- iOS는 APNs 인증 키를 Firebase 콘솔에 등록하고 Apple 개발자 계정에서 해당 앱의 푸시 기능이 켜진 프로비저닝 프로파일을 사용합니다. 개발은 `development`, 출시와 프로필 빌드는 `production` 환경으로 설정했습니다.
- iOS Swift Package Manager의 Firebase SDK에서 충돌 심볼 업로드 스크립트를 실행합니다. 출시 빌드에는 dSYM이 필요합니다. 다트 난독화 사용 시 빌드의 심볼 파일도 보존하고 Firebase 안내에 따라 업로드합니다.
- 두 계정과 실기기로 친구 요청·초대·댓글을 만들고 전경/백그라운드/종료 상태의 수신과 이동을 확인합니다. 수신 거부·차단·취소·로그아웃·다른 계정 로그인 뒤에는 이전 계정 내용이 열리지 않는지 확인합니다.
- iOS에서 사용자가 앱을 밀어서 종료한 경우 등 운영체제 정책으로 수신이 제한될 수 있습니다. 이 경우 앱을 다시 열어 확인합니다.
- 출시 빌드의 정제된 오류가 Firebase 콘솔에 보이는지 확인합니다. 좌표·인증 정보·원본 예외 본문이 없는지 확인합니다. 실제 데이터 손실이나 강제 충돌을 일으키는 코드는 앱에 추가하지 않았습니다.

## 검증 명령

```sh
flutter analyze
flutter test
scripts/run_sql_tests.sh
npx deno check supabase/functions/operations-worker/index.ts
npx deno test supabase/functions/operations-worker
```

SQL 테스트는 격리된 PostgreSQL 16에서 실행하며 운영 서버에서는 실행하지 않습니다.

설계 기준: [Firebase 알림 수신](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [Crashlytics 설정](https://firebase.google.com/docs/crashlytics/get-started?platform=flutter), [Storage 객체 삭제](https://supabase.com/docs/guides/storage/management/delete-objects).
