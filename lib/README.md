# 앱 코드 구조

- `main.dart`: 앱 초기화 호출과 실행 진입점입니다.
- `app/`: Firebase·Supabase 초기화, 최상위 앱 설정, 화면 크기, 탭 구성을 담당합니다.
- `features/auth/`: 로그인, 가입, 이메일 인증, 선택 전화번호 인증, 닉네임 등록을 담당합니다. `data/`에는 화면과 분리된 이메일·전화번호·닉네임 서비스가 있습니다.
- `features/home/`: 실제 지도 홈 화면과 `LiveMapController`를 담당합니다. `data/`는 기기 위치 및 서버 공유를, `models/`는 위치와 주변 러너 데이터를 담당합니다.
- `features/home/data/location_settings.dart`는 플랫폼별 지도·러닝 GPS 설정을, `location_tracker.dart`는 구독 교체와 시작 준비 확인을 담당합니다. 러닝 GPS는 백그라운드에서 유지하지만 서버 위치 공유는 별도로 중단합니다.
- `features/home/models/run_pace.dart`는 최근 GPS 이동 구간의 현재 페이스를 계산합니다. `run_session.dart`는 평균 페이스와 구간별 경로를 담당합니다. 종료 시 변경 불가능한 경로 스냅샷을 완료 기록에 포함합니다. 측정 중 지도 선은 공통 카카오 지도 모듈에 구간별 좌표를 전달합니다.
- `features/run_conditions/`: 서버 관측 자료 호출, 날씨·미세먼지 모델과 참고 조건 판단, 홈 활성 상태의 갱신 제어, 요약·상세 표시를 분리합니다. 위치 공개 설정이나 러닝 GPS 측정과 독립적으로 동작합니다.
- `features/run_history/`: 개인 러닝 기록 저장·목록 조회·새로고침·페이지 조회를 담당합니다. `data/run_outbox.dart`는 완료 기록을 서버·계정별 SQLite 저장소에 보관합니다. 컨트롤러는 기기 보관과 서버 전송을 분리하고 앱 시작·복귀 및 지연 재시도로 미전송 원본을 복구합니다. 서버 서비스, 기록 모델, 목록과 상세 위젯을 분리합니다.
- `features/run_feedback/`: 계정에 고정된 피드백 조회·생성 서비스와 기록 상세 패널입니다. 전송 동의 후에만 생성하며 이미 저장된 결과, 서버의 72시간 제한·오류·한도 상태를 표시합니다. 진행 중 결과 확인은 읽기 요청만 사용합니다.
- `features/run_share/`: 전체 화면 PNG 미리보기와 설정 패널, 보호 경로 정규화, 이미지 렌더링, 운영체제 공유 서비스 및 임시 파일 처리를 분리합니다. 이미지는 휴대폰 비율에 맞춰 거리·시간·평균 페이스·기온과 선택한 경로 선만 표시하며 브랜드·AI 피드백은 포함하지 않습니다. 원본 화면 캡처를 사용하지 않아 편집 버튼·계정 정보·지도·날짜가 섞이지 않습니다.
- `run_history/models/run_temperature.dart`: 종료 시점에 고정된 관측 기온·관측 시각입니다. `ConditionsController`는 위치 구역과 자료 신선도를 확인하고 추가 API 호출 없이 스냅샷을 만듭니다. 저장소 3버전은 기존 전송 대기 기록과 경로를 보존하면서 기온을 함께 저장합니다.
- `run_share/data/share_photo_service.dart`: 갤러리 한 장 선택과 크기 제한·축소 디코딩을 담당합니다. 사진은 공유 화면 안에서만 보유하고 계정 전환·화면 종료 때 해제하며 서버 전송·영구 저장하지 않습니다. 공유 렌더러가 사진 픽셀과 기온을 합성하고 원본 메타데이터는 복사하지 않습니다.
- `run_share/widgets/share_text_color_control.dart`: 자동·색상 견본과 직접 색상 코드 입력·색상 채널 슬라이더를 담당합니다. 공유 화면의 선택 색을 PNG 렌더러에 전달하고 대비가 낮으면 윤곽선과 사진 명암으로 보완합니다. 브랜드와 AI 피드백은 계속 제외합니다.
- `features/run_history/models/run_route.dart`는 구간별 좌표의 읽기 전용 모델과 형식 검사를 담당합니다. 저장소 2판은 경로를 함께 보관하고 이전 전송 대기 기록을 빈 경로로 유지합니다. `run_record_detail_screen.dart`는 상세 경로 조회·오류 재시도를, `widgets/saved_run_map.dart`는 지도·출발·도착·전체 경로 보기를 담당합니다. 기록 목록은 좌표를 조회하지 않습니다.
- `features/social/`: 친구 관리와 실제 주간 거리 랭킹 화면을 포함합니다. `data/ranking_service.dart`는 계정 고정 집계 조회를, `models/weekly_ranking.dart`는 서버 순위 응답 해석을 담당합니다. `data/friend_service.dart`는 계정 고정 서버 호출을, `friend_controller.dart`는 목록·검색·변경 상태와 화면 활성 중 갱신을 담당합니다. `models/friend_entry.dart`와 친구 목록·검색·랭킹 위젯을 분리합니다.
- `features/profile/`: 프로필, 공개 범위 설정, 실제 업적 조회·달성일 모델, 개인 통계 위젯을 포함합니다. `data/statistics_service.dart`와 `models/run_statistics.dart`는 계정 고정 통계 조회와 거리 가중 평균 페이스를 담당합니다. `data/run_sharing_preference_service.dart`는 본인 전용 자동 위치 공유 설정 저장·조회를, `widgets/run_sharing_control.dart`는 프로필의 설정·저장 상태·재시도를 담당합니다. 홈 컨트롤러가 설정과 실제 러닝·GPS 상태를 함께 확인하며 홈에는 공유 스위치를 두지 않습니다.
- `features/progress/`: 서버가 계산한 경험치·레벨 조회 서비스와 모델, 프로필 레벨 카드, 러닝 종료 보상(확인 중·실패 재시도·레벨 업) 위젯입니다. 보상은 서버 저장 시 확정되므로 앱은 조회만 재시도합니다. 서버 저장 대기 기록은 전송 후 지급된다고 안내합니다.
- `features/admin/`: 실제 이상 기록 조회·승인·반려 서비스, 처리 사유 입력과 관리자 다중 인증 위젯을 포함합니다. 서버 역할과 다중 인증을 매번 확인합니다.
- `shared/`: 특정 기능에 의존하지 않는 색상과 공통 위젯입니다. `widgets/account_query_panel.dart`는 개인 통계·랭킹의 로딩·재시도·계정 변경 응답 폐기·복귀 및 30초 갱신을 담당합니다.
- `shared/maps/`: 홈·기록 상세가 함께 사용하는 카카오 지도 설정, 웹뷰 브리지, 카메라 컨트롤러와 지도 위젯입니다. `assets/maps/kakao_map.html`은 공식 SDK를 로드하여 마커·단절 경로·영역 맞춤을 처리합니다. 좌표 이벤트 형식을 검사하고 지도 갱신을 직렬화하며 변경 없는 상태는 다시 전달하지 않습니다. 지도 실패와 GPS 측정 실패는 분리합니다.
- `firebase_options.dart`: 기존 Firebase 생성 설정입니다.

기능 전용 위젯은 해당 기능에 두고, 실제로 여러 기능에서 사용하는 범용 위젯만 `shared/`에 둡니다.
`main.dart`를 다른 모듈이나 테스트에서 가져오지 않고 필요한 모듈을 직접 가져옵니다.
서버 정책과 SQL 테스트는 기존 `supabase/` 구조를 유지합니다.

코스 생성 기능은 제거했습니다. 홈 위치는 기기 GPS와 Supabase 조회로 연결합니다. 개인 통계·친구 주간 랭킹은 서버 집계를 사용하며 업적·관리 화면도 서버 조회를 사용합니다.
가입·공개 설정 화면에 남아 있는 상태 처리와 데이터 호출은 해당 기능을 확장할 때 같은 방식으로 분리할 수 있습니다.

검증: `flutter analyze`, `flutter test`.
설계 참고: [Flutter 앱 구조 권장 사항](https://docs.flutter.dev/app-architecture/recommendations).

- `features/home/data/run_checkpoint_store.dart`: 계정·서버별 진행 중 러닝 SQLite 보관·재개방과 종료 원본 정리를 담당합니다. `RunSession.restore`는 시간·거리를 더하지 않고 일시 정지 상태와 새 경로 구간을 사용합니다.
- `features/group_running/`: 그룹 모델·계정 고정 RPC 서비스·서버 시각 카운트다운·앱 수명 주기·GPS 준비 및 그룹 화면을 분리합니다. 개인 기록·경로 측정은 기존 홈 컨트롤러를 사용합니다.
- `features/social/data/block_service.dart`, `blocked_users_screen.dart`, `widgets/block_button.dart`: 본인 차단 조회·변경, 동의 확인과 서버 갱신을 담당합니다.
- `features/profile/data/achievement_service.dart`: 서버가 확정한 실제 업적 진행률과 달성일을 조회합니다. 공통 계정 조회 패널로 재조회와 계정 변경 응답 폐기를 처리합니다.
- `features/board/`: 동네·전국 게시판과 러닝 대회 공지입니다. `data/board_service.dart`는 계정 고정 RPC 호출을, `board_controller.dart`는 게시판·말머리 선택과 이전 응답 폐기·더 보기·작성·삭제 후 재조회를 담당합니다. `data/korean_regions.dart`는 동네 선택용 시·도·시·군·구 목록이며 동네는 사용자가 직접 고릅니다. 대회 공지 등록 버튼은 서버가 알려준 관리자 권한일 때만 표시합니다.
