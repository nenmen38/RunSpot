-- 로컬·CI PostgreSQL에는 Supabase의 http·pg_cron 확장이 없어 마라톤 동기화 마이그레이션이 쓰는 이름만 대신 만듭니다.
-- 외부 요청은 보내지 않고 실패 응답만 돌려주며, 예약 작업도 등록하지 않습니다. 실제 서버에서는 절대 실행하지 않습니다.
create schema if not exists extensions;
create type extensions.http_response as (status integer,content_type varchar,headers jsonb,content varchar);
create function extensions.http_set_curlopt(curlopt varchar,value varchar) returns boolean
language sql as $$ select true $$;
create function extensions.http_get(uri varchar) returns extensions.http_response
language sql as $$ select row(503,null,null,null)::extensions.http_response $$;
create schema if not exists cron;
create function cron.schedule(job_name text,schedule text,command text) returns bigint
language sql as $$ select 1::bigint $$;
