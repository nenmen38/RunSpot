# 뜀터 수익 기능 운영 안내

대회 홍보와 제휴 쿠폰은 서버에 등록된 항목이 활성화되어 있고 노출 기간에 해당할 때 표시됩니다. 하단 상점 탭에서 꾸미기 상품 목록과 상세를 확인합니다. 결제 설정이 없으면 미리보기로 열립니다. 플랫폼별 RevenueCat 공개 SDK 키가 있는 앱에서는 스토어 상품을 구매할 수 있습니다.

## 프로필 꾸미기

1. 앱 스토어와 구글 플레이에 파란 프로필 테두리, 파란 프로필 테마를 각각 일회성 비소모성 상품으로 등록합니다. [결제 모듈 설치 안내](https://www.revenuecat.com/docs/getting-started/installation/flutter)
2. RevenueCat에 각 스토어를 연결하고 `profile_cosmetics` 오퍼링을 만듭니다. 사용자 지정 패키지와 구매 권한 식별자는 각각 `blue_profile_border`, `blue_profile_theme`으로 맞춥니다. 각 패키지에는 해당 플랫폼 상품을 연결하고, 상품은 해당 구매 권한에 연결합니다.
3. 구매 복원 정책을 **Keep with original App User ID**로 설정해 같은 기기의 다른 뜀터 계정으로 구매가 넘어가지 않도록 합니다. 운영·테스트 서버는 별도 RevenueCat 프로젝트를 사용합니다. 뜀터 서버에서 계정별 무작위 구매 식별자를 발급합니다. 계정 삭제 후 기존 구매를 새 계정으로 자동 이전하지 않으므로 계정 복구 문의 절차를 마련합니다.
4. 출시 빌드 설정에 `REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`를 넣습니다. 스토어 연결용 비밀 키는 RevenueCat에서만 관리합니다.
5. 테스트 계정으로 상품 가격 표시, 결제 취소, 구매 후 적용, 동일 계정 구매 복원, 다른 계정에서 권한 분리, 환불 후 재조회가 정상인지 확인합니다. 꾸미기 적용 여부는 기기에 계정별로 보관합니다. 상품 판매를 멈출 때는 오퍼링에서 패키지를 제거하고 기존 구매 권한은 보존합니다.

## 대회 유료 홍보

운영자가 주최자 및 계약·결제를 확인한 뒤 수파베이스 SQL 편집기에서 적용합니다. 기존 대회 식별자를 확인하고 날짜에 한국 시간대(`+09:00`)를 명시합니다. 예시 값은 실제 계약 값으로 교체합니다.

```sql
select id, data->>'name' as event_name, event_date
from runspot_private.marathon_catalog where available order by event_date;

insert into runspot_private.race_promotions (event_id, starts_at, ends_at, enabled)
values ('대회 식별자', '2027-01-01 09:00+09', '2027-01-08 09:00+09', true)
on conflict (event_id) do update set starts_at = excluded.starts_at,
  ends_at = excluded.ends_at, enabled = excluded.enabled;
```

해당 기간에 대회 목록 상단에 ‘광고’로 노출됩니다. 중단하려면 해당 행의 `enabled`를 끕니다. 계약과 홍보비 수납은 별도로 관리합니다.

## 매장 제휴

운영자가 제휴 계약 후 매장·주소·혜택 조건·기간·수수료율을 등록합니다. `commission_bps`의 100은 1%입니다. 계약 조건을 변경할 때는 기존 발급분의 약정이 달라지지 않도록 새 혜택을 등록합니다.

```sql
insert into runspot_private.shop_offers
  (shop_name, shop_address, terms, starts_at, ends_at, commission_bps, enabled)
values ('매장 이름', '매장 주소', '혜택 및 구매 조건',
  '2027-01-01 09:00+09', '2027-02-01 09:00+09', 500, true);
```

사용자는 프로필의 러닝 매장 혜택에서 계정당 혜택별 쿠폰을 한 번 발급받습니다. 매장은 구매 영수증과 쿠폰 번호를 운영자에게 전달합니다. 운영자는 매장·쿠폰 조건·할인 적용 후 실결제 금액을 확인하고 아래 함수를 실행합니다. 사용 처리와 수수료 기록은 한 번에 반영되며, 중복 요청은 거절됩니다. 수수료는 발급 당시 요율을 적용해 원 미만을 버립니다.

```sql
select o.shop_name, o.terms, c.redeemed_at
from runspot_private.shop_coupons c
join runspot_private.shop_offers o on o.id = c.offer_id
where c.code = '실제-쿠폰-번호'::uuid;

select runspot_private.redeem_shop_coupon('실제-쿠폰-번호'::uuid, 19900);

select o.shop_name, c.redeemed_at, c.sale_krw, c.commission_krw
from runspot_private.shop_coupons c
join runspot_private.shop_offers o on o.id = c.offer_id
where c.redeemed_at is not null order by c.redeemed_at;
```

계정을 삭제하면 미사용 쿠폰은 사용할 수 없게 됩니다. 사용한 쿠폰의 판매 금액과 수수료 기록은 계정 연결을 해제한 상태로 정산에 사용합니다. 정산은 기록을 기준으로 운영자가 처리합니다. 운영 시작 전 구매 처리·환불·수수료 정산 기준과 쿠폰 구매 기록의 보관 기간을 확정합니다.
