begin;
create function pg_temp.check_commerce(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000881','shop-one@example.com',now()),
 ('00000000-0000-0000-0000-000000000882','shop-two@example.com',now());
insert into runspot_private.marathon_catalog(id,event_date,data)
 values('sponsored-race',current_date+15,'{"name":"테스트 대회"}');
insert into runspot_private.race_promotions(event_id,starts_at,ends_at)
 values('sponsored-race',now()-interval '1 hour',now()+interval '1 hour');
insert into runspot_private.shop_offers(id,shop_name,shop_address,terms,starts_at,ends_at,commission_bps)
 values('00000000-0000-0000-0000-000000000883','매장','주소','할인 조건',
 now()-interval '1 hour',now()+interval '1 hour',725);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000881',true);
select pg_temp.check_commerce(public.marathon_events()#>>'{events,0,promoted_until}' is null,'비활성 광고 숨김');
select pg_temp.check_commerce(public.active_shop_offers()='[]'::jsonb,'비활성 혜택 숨김');
select set_config('test.first_customer',public.cosmetic_customer()::text,true);
select pg_temp.check_commerce(public.cosmetic_customer()::text=current_setting('test.first_customer')
 and not has_table_privilege('runspot_private.cosmetic_customers','select'),'결제 식별자 재사용 및 직접 조회 차단');
select pg_temp.check_commerce(not has_table_privilege('runspot_private.shop_coupons','select')
 and not has_function_privilege('runspot_private.redeem_shop_coupon(uuid,integer)','execute'),'사용자 직접 조회·사용 처리 차단');
reset role;
update runspot_private.race_promotions set enabled=true;
update runspot_private.shop_offers set enabled=true;
set local role authenticated;
select pg_temp.check_commerce(public.marathon_events()#>>'{events,0,promoted_until}' is not null,'활성 광고 표시');
select public.claim_shop_coupon('00000000-0000-0000-0000-000000000883');
select public.claim_shop_coupon('00000000-0000-0000-0000-000000000883');
select pg_temp.check_commerce(public.active_shop_offers()#>>'{0,code}' is not null,'본인 쿠폰 조회');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000882',true);
select pg_temp.check_commerce(public.active_shop_offers()#>>'{0,code}' is null,'타인 쿠폰 숨김');
select pg_temp.check_commerce(public.cosmetic_customer()::text<>current_setting('test.first_customer'),'계정별 결제 식별자 분리');
reset role;
select pg_temp.check_commerce((select count(*)=1 from runspot_private.shop_coupons),'중복 발급 방지');
select pg_temp.check_commerce((select runspot_private.redeem_shop_coupon(code,19900)=1442 from runspot_private.shop_coupons),'원 단위 수수료 계산');
do $$
begin
  begin
    perform runspot_private.redeem_shop_coupon(code,19900) from runspot_private.shop_coupons;
  exception when raise_exception then
    if sqlerrm = '사용할 수 없는 쿠폰입니다.' then return; end if;
    raise;
  end;
  raise exception '중복 사용을 허용했습니다.';
end $$;
update runspot_private.race_promotions set starts_at=now()-interval '2 hours',ends_at=now();
update runspot_private.shop_offers set starts_at=now()-interval '2 hours',ends_at=now();
set local role authenticated;
select pg_temp.check_commerce(public.active_shop_offers()='[]'::jsonb,'만료 혜택 숨김');
select pg_temp.check_commerce(public.marathon_events()#>>'{events,0,promoted_until}' is null,'만료 광고 숨김');
rollback;
