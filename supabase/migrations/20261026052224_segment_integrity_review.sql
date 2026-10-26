-- 전체 평균에 가려진 고속 이동도 기존 관리자 검토 흐름으로 보냅니다.
create function runspot_private.has_suspicious_splits(data jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select exists(select 1 from jsonb_array_elements(coalesce(data,'[]'::jsonb)) s
    where (s->>'distance_m')::numeric >= 300
      and ((s->>'duration_us')::numeric <= 0
        or (s->>'distance_m')::numeric * 1000000 > (s->>'duration_us')::numeric * 6.5));
$$;
revoke all on function runspot_private.has_suspicious_splits(jsonb) from public,anon,authenticated;

create or replace function runspot_private.open_integrity_case()
returns trigger language plpgsql security definer set search_path = '' as $$
declare rule text;
begin
  if runspot_private.has_suspicious_splits(new.split_data) then
    rule := 'split_speed_over_6_5';
  elsif (new.distance_m > 0 and new.duration_sec = 0)
    or (new.duration_sec > 0 and new.distance_m::numeric/new.duration_sec > 6.5) then
    rule := 'average_speed_over_6_5';
  end if;
  if rule is not null then
    insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
      values(new.id,rule,90) on conflict(run_id) do nothing;
  end if;
  return null;
end;
$$;

create or replace function runspot_private.review_cases()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if runspot_private.staff_role() is null then
    raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(entry order by created_at,id),'[]'::jsonb) from (
    select c.id,c.created_at,jsonb_build_object('id',c.id,'nickname',coalesce(p.nickname,'닉네임 없음'),
      'rule',c.rule_code,'risk',c.risk_score,'status',c.status,'distance_m',r.distance_m,
      'duration_sec',r.duration_sec,'splits',r.split_data) entry
    from runspot_private.integrity_cases c join public.runs r on r.id=c.run_id
    join public.profiles p on p.id=r.user_id where c.status in ('open','evidence_requested')
    order by c.created_at,c.id limit 100
  ) cases);
end;
$$;

-- 이미 확정된 관리자 결정을 덮어쓰지 않고 검토 대기 기록만 보완합니다.
insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
  select id,'split_speed_over_6_5',90 from public.runs
  where integrity_status='pending' and runspot_private.has_suspicious_splits(split_data)
  on conflict(run_id) do nothing;
notify pgrst,'reload schema';
