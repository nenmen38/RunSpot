#!/usr/bin/env bash
# 격리된 빈 PostgreSQL 16에 모든 마이그레이션과 SQL 테스트를 순서대로 적용합니다.
# 실제 Supabase 서버에는 절대 실행하지 않습니다. 인증·실시간·저장소 대역을 만들고 DB를 새로 만듭니다.
# 연결 정보는 PGHOST, PGPORT, PGUSER, PGPASSWORD 환경 변수로 지정합니다.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${RUNSPOT_TEST_DB:-runspot_test}"
export PGOPTIONS="${PGOPTIONS:---client-min-messages=warning}"

psql -X -q -v ON_ERROR_STOP=1 -d postgres \
  -c "drop database if exists $DB" \
  -c 'drop role if exists anon' -c 'drop role if exists authenticated' -c 'drop role if exists service_role' \
  -c "create database $DB"

args=(-f supabase/tests/local_auth_stub.sql)
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
for migration in supabase/migrations/*.sql; do
  case "$migration" in
    *20261006000100_*) args+=(-f supabase/tests/local_realtime_stub.sql) ;;
    *20261027000100_*) args+=(-f supabase/tests/local_storage_stub.sql) ;;
    *20261029092427_*)
      # http·pg_cron 확장은 Supabase에만 있으므로 확장 생성 줄을 빼고 대역을 먼저 적용합니다.
      args+=(-f supabase/tests/local_http_cron_stub.sql)
      sed -E '/^create extension if not exists (http|pg_cron)/d' "$migration" > "$work/$(basename "$migration")"
      args+=(-f "$work/$(basename "$migration")")
      continue ;;
  esac
  args+=(-f "$migration")
done
for test in test_registration registration security live_runner_map run_history friends run_routes \
  running_conditions environment_shared_budget email_verification optional_phone_verification run_feedback \
  run_temperature run_rewards run_statistics run_location_preferences blocks achievements_and_review \
  group_running run_splits segment_integrity review_pending_rewards sustained_speed_review app_usability \
  board board_engagement board_notifications board_replies_search board_comment_likes board_news_feed board_safety marathon_catalog account_deletion; do
  args+=(-f "supabase/tests/$test.sql")
done

psql -X -q -v ON_ERROR_STOP=1 -d "$DB" "${args[@]}" >/dev/null
echo "SQL 테스트를 모두 통과했습니다."
