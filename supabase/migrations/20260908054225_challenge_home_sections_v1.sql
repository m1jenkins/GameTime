-- A short-lived, actor-bound ordering snapshot is the cursor. It stores IDs,
-- never cached social/Health content. Each page reauthorizes and projects current
-- permitted details, so a block/revocation cannot resurrect old visibility.
create table app.challenge_pages_v1 (
 id uuid primary key,actor_id uuid not null references public.profiles(id),section text not null check(section in ('action','active','upcoming','history')),
 ids uuid[] not null,created_at timestamptz not null,expires_at timestamptz not null
);
create index challenge_pages_actor_v1 on app.challenge_pages_v1(actor_id,created_at);
alter table app.challenge_pages_v1 enable row level security;
revoke all on app.challenge_pages_v1 from public,anon,authenticated,service_role;
create function app.challenge_pages_guard_v1() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid)) or coalesce(current_setting('app.challenge_write_v1',true),'')<>'on'
 or tg_op not in ('INSERT','DELETE') then raise exception 'challenge_rpc_required' using errcode='42501';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger challenge_pages_guard before insert or update or delete on app.challenge_pages_v1 for each row execute function app.challenge_pages_guard_v1();
create function public.challenge_section_v1(p_section text,p_cursor jsonb default null,p_limit integer default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;page app.challenge_pages_v1;skip integer:=0;ids uuid[];rows jsonb:='[]';cid uuid;item jsonb;next_cursor jsonb;begin
 a:=app.challenge_session_v1();
 if p_section is null or p_section not in ('action','active','upcoming','history') or p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_page' using errcode='22023';end if;
 if p_cursor is null or p_cursor='null'::jsonb then
  perform set_config('app.challenge_write_v1','on',true);
  delete from app.challenge_pages_v1 where actor_id=a and (expires_at<=clock_timestamp() or id in(select id from app.challenge_pages_v1 where actor_id=a order by created_at desc offset 19));
  select coalesce(array_agg(c.id order by
   case when p_section='action' and c.status='review' then 0 else 1 end,
   case when p_section='history' then coalesce(f.recorded_at,c.ends_at) end desc,
   case when p_section='action' and c.status='review' then notice.review_by when p_section='active' then c.ends_at else c.starts_at end,
   c.id),'{}') into ids
  from app.challenge_lobbies_v1 c join app.challenge_members_v1 me on me.challenge_id=c.id and me.actor_id=a
  left join app.challenge_finals_v1 f on f.challenge_id=c.id
  left join lateral(select review_by from app.challenge_notices_v1 where challenge_id=c.id order by revision desc limit 1) notice on true
  where case p_section when 'action' then me.exited_at is null and c.status in ('review','consent_pending') when 'active' then me.exited_at is null and c.status in ('active','syncing') when 'upcoming' then me.exited_at is null and c.status in ('lobby_open','published_open','scheduled') else (me.exited_at is not null or c.status in ('final','void','cancelled')) end;
  insert into app.challenge_pages_v1 values(extensions.gen_random_uuid(),a,p_section,ids,clock_timestamp(),clock_timestamp()+interval '2 minutes') returning * into page;
 else
  if jsonb_typeof(p_cursor) is distinct from 'object' or p_cursor-array['snapshot_id','offset']<>'{}' or not(p_cursor ?& array['snapshot_id','offset'])
   or p_cursor->>'offset' !~ '^[0-9]+$' then raise exception 'challenge_invalid_page' using errcode='22023';end if;
  select * into page from app.challenge_pages_v1 where id=(p_cursor->>'snapshot_id')::uuid and actor_id=a and section=p_section and expires_at>clock_timestamp();
  if page.id is null then raise exception 'challenge_page_expired' using errcode='55000';end if;
  skip:=(p_cursor->>'offset')::integer;
  if skip>cardinality(page.ids) then raise exception 'challenge_invalid_page' using errcode='22023';end if;
 end if;
 foreach cid in array page.ids[skip+1:skip+p_limit] loop
  item:=public.challenge_detail_v1(cid);rows:=rows||jsonb_build_array(item);
 end loop;
 if skip+p_limit<cardinality(page.ids) then next_cursor:=jsonb_build_object('snapshot_id',page.id,'offset',skip+p_limit);end if;
 return jsonb_build_object('section',p_section,'projection_revision',page.id,'server_time',app.challenge_now_v1(),'expires_at',page.expires_at,'rows',rows,'next_cursor',next_cursor);
end $$;
revoke all on function app.challenge_pages_guard_v1(),public.challenge_section_v1(text,jsonb,integer) from public,anon,authenticated,service_role;
grant execute on function public.challenge_section_v1(text,jsonb,integer) to authenticated;
