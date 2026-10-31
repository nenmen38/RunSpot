# 출시 체크리스트

코드로 처리한 항목과, 계정·법적 판단이 필요해 직접 해야 하는 항목을 나눴습니다.

## 앱에 반영된 항목

- 앱 안에서 회원 탈퇴: 설정 → 회원 탈퇴. 서버 `delete_my_account()`가 계정과 연결 자료를 지우고, 앱이 게시판 사진과 기기에 보관한 전송 대기 기록·진행 중 기록을 지웁니다.
- 정책 문서 링크: `config/*.json`의 `PRIVACY_POLICY_URL`, `TERMS_URL`, `LOCATION_TERMS_URL`, `SUPPORT_EMAIL`을 채우면 설정 화면에 표시됩니다. 비어 있으면 숨깁니다.
- 오픈소스 라이선스 화면: 설정 → 오픈소스 라이선스.
- 출시 서명: `android/key.properties`가 있으면 출시 키로 서명하고, 없으면 개발용 디버그 서명을 사용합니다.
- iOS 사진 권한 안내 문구를 게시판 사진 업로드에 맞게 수정했습니다.
- CI: `.github/workflows/ci.yml`이 푸시·PR마다 `flutter analyze`, `flutter test`, SQL 테스트(`scripts/run_sql_tests.sh`)를 실행합니다.

## 직접 해야 하는 항목

### 1. 서버 적용
- `supabase db push --dry-run`으로 `20261028000100_account_deletion.sql`, `20261028000200_board_notifications.sql`, `20261029000100_board_replies_search.sql`, `20261029000200_board_comment_likes.sql`, `20261029120000_board_news_feed.sql`만 남았는지 확인한 뒤 `supabase db push`.

### 2. 출시 키 만들기 (Android, 한 번만)
```powershell
keytool -genkey -v -keystore C:\keys\runspot-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
`android/key.properties` (저장소에 올리지 않습니다):
```
storePassword=입력한_비밀번호
keyPassword=입력한_비밀번호
keyAlias=upload
storeFile=C:\\keys\\runspot-upload.jks
```
키 파일과 비밀번호를 잃어버리면 앱을 업데이트할 수 없으므로 안전한 곳에 따로 보관합니다. Google Play 앱 서명을 사용하면 이 키는 업로드 키로 쓰입니다.

출시 빌드:
```powershell
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

### 3. 정책 문서
- `docs/privacy-policy-draft.md`는 코드 기준으로 작성한 **초안**입니다. 운영자 정보·보관 기간을 채우고 법률 검토를 받은 뒤 웹에 게시하고 주소를 `PRIVACY_POLICY_URL`에 넣습니다.
- 위치 정보를 다루므로 위치정보법상 **위치기반서비스사업 신고** 대상인지, 위치정보 이용약관·동의가 필요한지 확인합니다.
- 서비스 이용약관(게시판 운영 정책, 신고 처리, 이용 제한 포함)을 준비합니다.

### 4. 스토어 등록 정보
- 앱 이름을 하나로 정합니다. 현재 Android 표시 이름은 `runquest`, iOS는 `Runquest`, 문서는 `런퀘스트`, 저장소는 `RunSpot`으로 서로 다릅니다.
- 앱 아이콘이 Flutter 기본 아이콘인지 확인하고 교체합니다.
- Google Play **데이터 보안** 양식과 App Store **개인정보 라벨**을 초안의 수집 항목과 같게 작성합니다.
- 백그라운드 위치(러닝 측정 중)와 건강 데이터(심박수·칼로리) 사용 목적을 심사 양식에 적습니다. Google Play는 백그라운드 위치 사용 영상을 요구할 수 있습니다.
- 심사용 테스트 계정(이메일 인증·닉네임 완료)을 준비합니다.

### 5. 운영 준비 (권장)
- 오류 수집: Crashlytics 연결 구현 완료. Firebase 콘솔 활성화·출시 실기기 보고 확인이 필요합니다.
- 푸시 알림: 세션별 기기 등록·수신 설정·서버 대기열·화면 이동 구현 완료. FCM 서비스 계정·APNs 설정과 서버 활성화 절차는 `docs/OPERATIONS.md`를 따릅니다.
- 게시판 사진 정리: 24시간이 지난 미사용 사진을 격리 후 제거하는 서버 작업 구현 완료. 작업 비밀 등록과 예약 실행 확인이 필요합니다.
