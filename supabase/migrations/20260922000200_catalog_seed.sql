-- 개발과 운영에서 동일하게 사용하는 기준 데이터만 등록합니다.
insert into public.route_presets(code,name,distance_m,slope,flow,environment,safety) values
('night','야간 안전런',5000,'flat','relaxed','mixed','night'),
('pace','페이스런',5000,'flat','few_signals','urban','optimal'),
('uphill','업힐런',7000,'uphill','relaxed','urban','avoid_alleys'),
('healing','힐링런',5000,'gentle','relaxed','nature','optimal'),
('10k','10킬로미터 기록 도전',10000,'flat','few_signals','urban','optimal');

insert into public.achievement_definitions(code,title,metric,target) values
('explorer','코스 탐색가','distinct_routes',20),
('night_runner','야간 안전러','night_runs',10),
('uphill_runner','업힐 사냥꾼','elevation_m',750);
