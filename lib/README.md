# 앱 코드 구조

- `main.dart`: 앱 초기화 호출과 실행 진입점입니다.
- `app/`: Firebase·Supabase 초기화, 최상위 앱 설정, 화면 크기, 탭 구성을 담당합니다.
- `features/auth/`: 로그인, 가입, 전화번호 인증, 닉네임 등록을 담당합니다. `data/`에는 화면과 분리된 전화번호·닉네임 서비스가 있습니다.
- `features/home/`: 홈 화면을 담당합니다.
- `features/course/`: 코스 화면, 선택 상태·계산을 담당하는 `CourseController`, 코스 모델, 프리셋, 코스 전용 위젯을 포함합니다.
- `features/social/`: 소셜 화면, 랭킹 모델·예시 데이터, 랭킹·공유 위젯을 포함합니다.
- `features/profile/`: 프로필, 공개 범위 설정, 업적 모델·예시 데이터, 개인 통계 위젯을 포함합니다.
- `features/admin/`: 관리 화면, 검토 모델, 관리 전용 위젯을 포함합니다.
- `shared/`: 특정 기능에 의존하지 않는 색상과 공통 위젯입니다.
- `firebase_options.dart`: 기존 Firebase 생성 설정입니다.

기능 전용 위젯은 해당 기능에 두고, 실제로 여러 기능에서 사용하는 범용 위젯만 `shared/`에 둡니다.
`main.dart`를 다른 모듈이나 테스트에서 가져오지 않고 필요한 모듈을 직접 가져옵니다.
서버 정책과 SQL 테스트는 기존 `supabase/` 구조를 유지합니다.

이번 분리는 기존 동작을 보존하는 구조 변경입니다. 코스 점수 계산, 랭킹·업적·통계·관리 예시 데이터가 실제 서버 기능으로 바뀐 것은 아닙니다.
가입·공개 설정 화면에 남아 있는 상태 처리와 데이터 호출은 해당 기능을 확장할 때 같은 방식으로 분리할 수 있습니다.

검증: `flutter analyze`, `flutter test`.
설계 참고: [Flutter 앱 구조 권장 사항](https://docs.flutter.dev/app-architecture/recommendations).
