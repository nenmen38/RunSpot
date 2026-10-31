#!/usr/bin/env bash
# 공개 모바일 설정만 사용하여 팀원에게 전달할 Android 검증 APK를 만듭니다.
set -euo pipefail
cd "$(dirname "$0")/.."
source_config="${1:-config/dev.json}"
artifact_dir="${2:-build/qa/android}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/runspot-android-qa.XXXXXX")"
cleanup() {
  python3 - "$work_dir" <<'CLEANUP'
import sys
from pathlib import Path
root = Path(sys.argv[1])
(root / 'client.json').unlink(missing_ok=True)
root.rmdir()
CLEANUP
}
trap cleanup EXIT

python3 - "$source_config" "$work_dir/client.json" <<'PY'
import json
import os
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
allowed = (
    'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY',
    'KAKAO_JAVASCRIPT_KEY', 'KAKAO_MAP_ORIGIN',
    'PRIVACY_POLICY_URL', 'TERMS_URL', 'LOCATION_TERMS_URL', 'SUPPORT_EMAIL',
)
for key in ('SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'KAKAO_JAVASCRIPT_KEY'):
    if not isinstance(source.get(key), str) or not source[key].strip():
        raise SystemExit(f'모바일 설정이 필요합니다: {key}')
target = Path(sys.argv[2])
target.write_text(json.dumps({key: source[key] for key in allowed if key in source}), encoding='utf-8')
os.chmod(target, 0o600)
PY

mkdir -p "$artifact_dir"
flutter build apk --debug --dart-define-from-file="$work_dir/client.json"
cp build/app/outputs/flutter-apk/app-debug.apk "$artifact_dir/runspot-android-qa.apk"
flutter build apk --release --dart-define-from-file="$work_dir/client.json"
cp build/app/outputs/flutter-apk/app-release.apk "$artifact_dir/runspot-android-release-qa.apk"
flutter build apk --release --target=tool/crashlytics_probe.dart --dart-define-from-file="$work_dir/client.json"
cp build/app/outputs/flutter-apk/app-release.apk "$artifact_dir/runspot-crashlytics-probe.apk"
(
  cd "$artifact_dir"
  shasum -a 256 runspot-android-qa.apk runspot-android-release-qa.apk runspot-crashlytics-probe.apk > SHA256SUMS
)
printf '검증 APK와 파일 확인값을 준비했습니다: %s\n' "$artifact_dir"
