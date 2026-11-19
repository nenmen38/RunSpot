-- 단톡·크루 대화방에서도 사진을 보낼 수 있게 합니다. 1:1 대화와 같은 방식(1MB 이하 JPEG, 서버 보관)입니다.
alter table runspot_private.chat_room_messages
  add column kind text not null default 'text' check (kind in ('text','photo')),
  add column photo bytea check (octet_length(photo) between 4 and 1048576),
  add constraint chat_room_messages_photo_kind check ((kind='photo') = (photo is not null));

-- 메시지에 종류(kind)를 함께 돌려줍니다. 사진은 목록에서 '사진'으로 보이고, 실제 사진은 따로 받습니다.
create or replace function runspot_private.chat_room_read(target uuid,before_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target);
begin
  return jsonb_build_object(
    'room',(select jsonb_build_object('room_id',r.id,'kind',r.kind,'crew_id',r.crew_id,
        'title',runspot_private.chat_room_title(r.id,viewer)) from runspot_private.chat_rooms r where r.id=target),
    'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',member.uid,'nickname',coalesce(p.nickname,'알 수 없음'))
        order by p.nickname),'[]'::jsonb)
      from runspot_private.chat_room_member_ids(target) as member(uid) left join public.profiles p on p.id=member.uid),
    'messages',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'sender_id',m.sender_id,
        'nickname',coalesce(p.nickname,'알 수 없음'),'body',m.body,'kind',m.kind,'sent_at',m.sent_at,
        'unread',(select count(*) from runspot_private.chat_room_member_ids(target) as member(uid)
          where member.uid<>m.sender_id and runspot_private.chat_room_last_read(target,member.uid)<m.id))
        order by m.id desc),'[]'::jsonb)
      from (select * from runspot_private.chat_room_messages
        where room_id=target and (before_id is null or id<before_id)
          -- 차단한 사람의 메시지는 보이지 않게 합니다.
          and not exists(select 1 from runspot_private.blocks b
            where (b.blocker_id=viewer and b.blocked_id=sender_id) or (b.blocker_id=sender_id and b.blocked_id=viewer))
        order by id desc limit 50) m
      left join public.profiles p on p.id=m.sender_id));
end;
$$;


create function runspot_private.chat_room_send_photo(target uuid,jpeg text,request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target); image_bytes bytea;
begin
  if request_id is null or jpeg is null then raise exception '사진을 다시 보내 주세요.' using errcode='22023'; end if;
  if octet_length(jpeg)>1398104 then raise exception '사진은 1MB 이하로 보내 주세요.' using errcode='22023'; end if;
  begin
    image_bytes := decode(jpeg,'base64');
  exception when others then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end;
  -- JPEG 파일의 시작(FF D8)과 끝(FF D9)을 확인합니다.
  if octet_length(image_bytes) not between 4 and 1048576
     or substring(image_bytes from 1 for 2)<>'\xffd8'::bytea
     or substring(image_bytes from octet_length(image_bytes)-1 for 2)<>'\xffd9'::bytea then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end if;
  if exists(select 1 from runspot_private.chat_room_messages m
      where m.sender_id=viewer and m.request_id=chat_room_send_photo.request_id) then
    return;
  end if;
  if (select count(*) from runspot_private.chat_room_messages
      where sender_id=viewer and kind='photo' and sent_at>clock_timestamp()-interval '1 minute') >= 5 then
    raise exception '사진은 1분에 5장까지 보낼 수 있어요.' using errcode='P0001';
  end if;
  insert into runspot_private.chat_room_messages(room_id,sender_id,body,request_id,kind,photo)
  values(target,viewer,'사진',request_id,'photo',image_bytes);
end;
$$;

create function runspot_private.chat_room_photo(target uuid,message_id bigint)
returns text language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target);
begin
  return (select encode(m.photo,'base64') from runspot_private.chat_room_messages m
    where m.id=message_id and m.room_id=target and m.kind='photo'
      and not exists(select 1 from runspot_private.blocks b
        where (b.blocker_id=viewer and b.blocked_id=m.sender_id) or (b.blocker_id=m.sender_id and b.blocked_id=viewer)));
end;
$$;

create function public.chat_room_send_photo(target uuid,jpeg text,request_id uuid) returns void language sql
security invoker set search_path='' as $$ select runspot_private.chat_room_send_photo(target,jpeg,request_id); $$;
create function public.chat_room_photo(target uuid,message_id bigint) returns text language sql stable
security invoker set search_path='' as $$ select runspot_private.chat_room_photo(target,message_id); $$;
revoke all on function runspot_private.chat_room_send_photo(uuid,text,uuid),runspot_private.chat_room_photo(uuid,bigint),
  public.chat_room_send_photo(uuid,text,uuid),public.chat_room_photo(uuid,bigint) from public,anon,authenticated;
grant execute on function runspot_private.chat_room_send_photo(uuid,text,uuid),runspot_private.chat_room_photo(uuid,bigint),
  public.chat_room_send_photo(uuid,text,uuid),public.chat_room_photo(uuid,bigint) to authenticated;
notify pgrst,'reload schema';
