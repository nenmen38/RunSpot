# 앱 코드 구조

- `main.dart`: 앱 초기화 호출과 실행 진입점입니다.
- `app/`: Firebase·Supabase 초기화, 최상위 앱 설정, 화면 크기, 탭 구성을 담당합니다.
- `features/auth/`: 로그인, 가입, 이메일 인증, 선택 전화번호 인증, 닉네임 등록을 담당합니다. `data/`에는 화면과 분리된 이메일·전화번호·닉네임 서비스가 있습니다.
- `features/home/`: 실제 지도 홈 화면과 `LiveMapController`를 담당합니다. `data/`는 기기 위치 및 서버 공유를, `models/`는 위치와 주변 러너 데이터를 담당합니다.
- `features/home/data/location_settings.dart`는 플랫폼별 지도·러닝 GPS 설정을, `location_tracker.dart`는 구독 교체와 시작 준비 확인을 담당합니다. 러닝 GPS는 백그라운드에서 유지하지만 서버 위치 공유는 별도로 중단합니다.
- `features/home/models/run_pace.dart`는 최근 GPS 이동 구간의 현재 페이스를 계산합니다. `run_session.dart`는 평균 페이스와 구간별 경로를, `widgets/run_route_layer.dart`는 측정 중 지도 선 표시를 담당합니다. 종료 시 변경 불가능한 경로 스냅샷을 완료 기록에 포함합니다.
- `features/run_conditions/`: 서버 관측 자료 호출, 날씨·미세먼지 모델과 참고 조건 판단, 홈 활성 상태의 갱신 제어, 요약·상세 표시를 분리합니다. 위치 공개 설정이나 러닝 GPS 측정과 독립적으로 동작합니다.
- `features/run_history/`: 개인 러닝 기록 저장·목록 조회·새로고침·페이지 조회를 담당합니다. `data/run_outbox.dart`는 완료 기록을 서버·계정별 SQLite 저장소에 보관합니다. 컨트롤러는 기기 보관과 서버 전송을 분리하고 앱 시작·복귀 및 지연 재시도로 미전송 원본을 복구합니다. 서버 서비스, 기록 모델, 목록과 상세 위젯을 분리합니다.
- `features/run_history/models/run_route.dart`는 구간별 좌표의 읽기 전용 모델과 형식 검사를 담당합니다. 저장소 2판은 경로를 함께 보관하고 이전 전송 대기 기록을 빈 경로로 유지합니다. `run_record_detail_screen.dart`는 상세 경로 조회·오류 재시도를, `widgets/saved_run_map.dart`는 지도·출발·도착·전체 경로 보기를 담당합니다. 기록 목록은 좌표를 조회하지 않습니다.
- `features/social/`: 친구 관리와 기존 예시 랭킹 화면을 포함합니다. `data/friend_service.dart`는 계정 고정 서버 호출을, `friend_controller.dart`는 목록·검색·변경 상태와 화면 활성 중 갱신을 담당합니다. `models/friend_entry.dart`와 친구 목록·검색·랭킹 위젯을 분리합니다.
- `features/profile/`: 프로필, 공개 범위 설정, 업적 모델·예시 데이터, 개인 통계 위젯을 포함합니다.
- `features/admin/`: 관리 화면, 검토 모델, 관리 전용 위젯을 포함합니다.
- `shared/`: 특정 기능에 의존하지 않는 색상과 공통 위젯입니다.
- `firebase_options.dart`: 기존 Firebase 생성 설정입니다.

기능 전용 위젯은 해당 기능에 두고, 실제로 여러 기능에서 사용하는 범용 위젯만 `shared/`에 둡니다.
`main.dart`를 다른 모듈이나 테스트에서 가져오지 않고 필요한 모듈을 직접 가져옵니다.
서버 정책과 SQL 테스트는 기존 `supabase/` 구조를 유지합니다.

코스 생성 기능은 제거했습니다. 홈 위치는 기기 GPS와 Supabase 조회로 연결하며 랭킹·업적·통계·관리 데이터는 기존 예시 데이터입니다.
가입·공개 설정 화면에 남아 있는 상태 처리와 데이터 호출은 해당 기능을 확장할 때 같은 방식으로 분리할 수 있습니다.

검증: `flutter analyze`, `flutter test`.
설계 참고: [Flutter 앱 구조 권장 사항](https://docs.flutter.dev/app-architecture/recommendations).
