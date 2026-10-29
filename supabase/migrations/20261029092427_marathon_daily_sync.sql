-- 하루 한 번 서버에서만 외부 API를 읽습니다. 사용자 요청은 저장된 자료만 조회합니다.
create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create function runspot_private.refresh_marathons()
returns boolean language plpgsql set search_path='' as $$
declare response extensions.http_response; imported integer;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('marathon_daily_sync',0)) then return false; end if;
 update runspot_private.marathon_sync_state set attempted_at=clock_timestamp() where singleton;
 begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','20000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  select * into response from extensions.http_get('https://www.apizoa.com/api/v1/marathons');
  if response.status<>200 or octet_length(response.content)>3000000 then
   raise exception '마라톤 API 응답을 확인하지 못했습니다.'; end if;
  imported:=runspot_private.import_marathons(response.content::jsonb);
 exception when others then
  -- 수집 실패 시 이전 정상 목록을 유지하고 운영자가 확인할 수 있는 상태만 남깁니다.
  update runspot_private.marathon_sync_state set last_error='동기화 실패: '||sqlstate where singleton;
  return false;
 end;
 return imported>0;
end;
$$;
revoke all on function runspot_private.refresh_marathons() from public,anon,authenticated,service_role;
-- 외부 요청 함수는 비노출 스키마에 두며 앱에서 호출하는 공개 RPC는 조회 전용입니다.
-- 한국 시각 매일 오전 3시입니다. 같은 이름으로 재실행해도 작업을 중복 생성하지 않습니다.
select cron.schedule('runspot-marathons-daily','0 18 * * *','select runspot_private.refresh_marathons();');
