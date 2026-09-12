-- P5: measured query bounds. Prior migrations and agreements stay immutable.
-- The public detail endpoint still validates its session. A bounded section
-- validates once, then reuses this private projection with the same actor. Each
-- row retains its membership/visibility checks; no social payload is cached.
do $$ declare definition text;
begin
 definition:=pg_get_functiondef('public.challenge_detail_v1(uuid)'::regprocedure);
 definition:=replace(definition,'public.challenge_detail_v1(p_id uuid)','app.challenge_detail_for_actor_v1(p_id uuid, a uuid)');
 definition:=replace(definition,'declare a uuid;','declare ');
 if position('a:=app.challenge_session_v1();' in definition)=0 then raise exception 'Unexpected detail session';end if;
 definition:=replace(definition,'a:=app.challenge_session_v1();','');
 execute definition;
end $$;
revoke all on function app.challenge_detail_for_actor_v1(uuid,uuid) from public,anon,authenticated,service_role;
create or replace function public.challenge_detail_v1(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1();
begin return app.challenge_detail_for_actor_v1(p_id,a);end $$;

-- Private, replaceable ordering metadata. Agreements, facts and results remain
-- in their original immutable tables. Only history membership/order changes
-- advance the actor revision; progress and privacy changes still project live.
create table app.challenge_history_v1 (
 actor_id uuid not null references public.profiles(id),
 challenge_id uuid not null references app.challenge_lobbies_v1(id),
 sort_at timestamptz not null,
 starts_at timestamptz not null,
 primary key(actor_id,challenge_id)
);
create table app.challenge_history_revisions_v1 (
 actor_id uuid primary key references public.profiles(id),revision bigint not null
);
alter table app.challenge_history_v1 enable row level security;
alter table app.challenge_history_revisions_v1 enable row level security;
revoke all on app.challenge_history_v1,app.challenge_history_revisions_v1 from public,anon,authenticated,service_role;
insert into app.challenge_history_v1
 select m.actor_id,c.id,coalesce(f.recorded_at,c.ends_at),c.starts_at
 from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id
 left join app.challenge_finals_v1 f on f.challenge_id=c.id
 where m.exited_at is not null or c.status in ('final','void','cancelled');
insert into app.challenge_history_revisions_v1 select distinct actor_id,1 from app.challenge_history_v1;

create function app.challenge_refresh_history_v1() returns trigger
language plpgsql set search_path='' as $$
declare cid uuid; member_actor uuid; row record; changed uuid;
begin
 if tg_table_name='challenge_lobbies_v1' then cid:=new.id;else cid:=new.challenge_id;end if;
 if tg_table_name='challenge_members_v1' then
  if tg_op='UPDATE' and old.exited_at is not distinct from new.exited_at then return new;end if;
  member_actor:=new.actor_id;
 end if;
 -- Existing mutations own challenge/profile locks before writing these rows.
 -- Sorted actors also keep direct owner maintenance in a deterministic order.
 for row in
  select m.actor_id,c.id,coalesce(f.recorded_at,c.ends_at) sort_at,c.starts_at,
   (m.exited_at is not null or c.status in ('final','void','cancelled')) in_history
  from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id
  left join app.challenge_finals_v1 f on f.challenge_id=c.id
  where c.id=cid and (member_actor is null or m.actor_id=member_actor) order by m.actor_id
 loop
  changed:=null;
  if row.in_history then
   insert into app.challenge_history_v1 values(row.actor_id,row.id,row.sort_at,row.starts_at)
   on conflict(actor_id,challenge_id) do update set sort_at=excluded.sort_at,starts_at=excluded.starts_at
   where (challenge_history_v1.sort_at,challenge_history_v1.starts_at) is distinct from (excluded.sort_at,excluded.starts_at)
   returning actor_id into changed;
  else
   delete from app.challenge_history_v1 where actor_id=row.actor_id and challenge_id=cid returning actor_id into changed;
  end if;
  if changed is not null then
   insert into app.challenge_history_revisions_v1 values(changed,1)
   on conflict(actor_id) do update set revision=challenge_history_revisions_v1.revision+1;
  end if;
 end loop;
 return new;
end $$;
create trigger challenge_history_lobby after update of status,starts_at,ends_at on app.challenge_lobbies_v1
 for each row when ((old.status,old.starts_at,old.ends_at) is distinct from (new.status,new.starts_at,new.ends_at)) execute function app.challenge_refresh_history_v1();
create trigger challenge_history_member after insert or update of exited_at on app.challenge_members_v1
 for each row execute function app.challenge_refresh_history_v1();
create trigger challenge_history_final after insert on app.challenge_finals_v1
 for each row execute function app.challenge_refresh_history_v1();
revoke all on function app.challenge_refresh_history_v1() from public,anon,authenticated,service_role;

alter table app.challenge_pages_v1 add column history_revision bigint;
-- Keep pre-upgrade offset cursors and other sections intact for their two-minute
-- lifetime. New history pages store NO inventory of IDs.
do $$ declare definition text;
begin
 definition:=pg_get_functiondef('public.challenge_section_v1(text,jsonb,integer)'::regprocedure);
 if position('insert into app.challenge_pages_v1 values' in definition)=0 or position('public.challenge_detail_v1(cid)' in definition)=0 or position('if page.id is null then' in definition)=0 then raise exception 'Unexpected section snapshot source';end if;
 definition:=replace(definition,'public.challenge_section_v1','app.challenge_section_snapshot_v1');
 definition:=replace(definition,'public.challenge_detail_v1(cid)','app.challenge_detail_for_actor_v1(cid,a)');
 definition:=replace(definition,'return jsonb_build_object(''section'',','perform app.challenge_session_v1(); return jsonb_build_object(''section'',');
 definition:=replace(definition,'if page.id is null then','if page.history_revision is not null then raise exception ''challenge_invalid_page'' using errcode=''22023'';end if; if page.id is null then');
 definition:=replace(definition,'insert into app.challenge_pages_v1 values','insert into app.challenge_pages_v1(id,actor_id,section,ids,created_at,expires_at) values');
 execute definition;
end $$;
revoke all on function app.challenge_section_snapshot_v1(text,jsonb,integer) from public,anon,authenticated,service_role;

-- A first-page range and three continuation ranges preserve the existing mixed sort directions. Each reads at
-- most limit+1 rows, including on a deep page; no OFFSET or full ID array.
create function app.challenge_history_slice_v1(a uuid,after_time timestamptz,after_start timestamptz,after_id uuid,bound integer)
returns table(challenge_id uuid,sort_at timestamptz,starts_at timestamptz)
language sql stable set search_path='' as $$
 select * from (
  (select h.challenge_id,h.sort_at,h.starts_at from app.challenge_history_v1 h
   where h.actor_id=a and after_id is null
   order by h.sort_at desc,h.starts_at,h.challenge_id limit bound)
  union all
  (select h.challenge_id,h.sort_at,h.starts_at from app.challenge_history_v1 h
   where h.actor_id=a and after_id is not null and h.sort_at<after_time
   order by h.sort_at desc,h.starts_at,h.challenge_id limit bound)
  union all
  (select h.challenge_id,h.sort_at,h.starts_at from app.challenge_history_v1 h
   where h.actor_id=a and h.sort_at=after_time and h.starts_at>after_start
   order by h.sort_at desc,h.starts_at,h.challenge_id limit bound)
  union all
  (select h.challenge_id,h.sort_at,h.starts_at from app.challenge_history_v1 h
   where h.actor_id=a and h.sort_at=after_time and h.starts_at=after_start and h.challenge_id>after_id
   order by h.sort_at desc,h.starts_at,h.challenge_id limit bound)
 ) s order by sort_at desc,starts_at,challenge_id limit bound
$$;
revoke all on function app.challenge_history_slice_v1(uuid,timestamptz,timestamptz,uuid,integer) from public,anon,authenticated,service_role;

create or replace function public.challenge_section_v1(p_section text,p_cursor jsonb default null,p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; page app.challenge_pages_v1; generation bigint; after_time timestamptz; after_start timestamptz; after_id uuid;
 item record; count integer:=0; rows jsonb:='[]'; last_key jsonb; next_cursor jsonb;
begin
 if p_section is distinct from 'history' or (p_cursor ? 'offset') then
  return app.challenge_section_snapshot_v1(p_section,p_cursor,p_limit);
 end if;
 a:=app.challenge_session_v1();
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_page' using errcode='22023';end if;
 select coalesce((select revision from app.challenge_history_revisions_v1 where actor_id=a),0) into generation;
 if p_cursor is null or p_cursor='null'::jsonb then
  perform set_config('app.challenge_write_v1','on',true);
  delete from app.challenge_pages_v1 where actor_id=a and (expires_at<=clock_timestamp() or id in(select id from app.challenge_pages_v1 where actor_id=a order by created_at desc offset 19));
  insert into app.challenge_pages_v1(id,actor_id,section,ids,created_at,expires_at,history_revision)
   values(extensions.gen_random_uuid(),a,p_section,'{}',clock_timestamp(),clock_timestamp()+interval '2 minutes',generation) returning * into page;
 else
  if jsonb_typeof(p_cursor) is distinct from 'object' or p_cursor-array['snapshot_id','after']<>'{}'
   or not(p_cursor ?& array['snapshot_id','after']) or jsonb_typeof(p_cursor->'after') is distinct from 'array'
   or jsonb_array_length(p_cursor->'after')<>3 then raise exception 'challenge_invalid_page' using errcode='22023';end if;
  begin
   select * into page from app.challenge_pages_v1 where id=(p_cursor->>'snapshot_id')::uuid and actor_id=a and section=p_section and expires_at>clock_timestamp();
   after_time:=(p_cursor->'after'->>0)::timestamptz; after_start:=(p_cursor->'after'->>1)::timestamptz; after_id:=(p_cursor->'after'->>2)::uuid;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
   raise exception 'challenge_invalid_page' using errcode='22023';
  end;
  if page.id is null or page.history_revision is distinct from generation then raise exception 'challenge_page_expired' using errcode='55000';end if;
  if after_time is null or after_start is null or after_id is null or not isfinite(after_time) or not isfinite(after_start)
   or not exists(select 1 from app.challenge_history_v1 h where h.actor_id=a and h.challenge_id=after_id and h.sort_at=after_time and h.starts_at=after_start)
   then raise exception 'challenge_invalid_page' using errcode='22023';end if;
 end if;
 for item in select * from app.challenge_history_slice_v1(a,after_time,after_start,after_id,p_limit+1) loop
  count:=count+1;
  if count>p_limit then next_cursor:=jsonb_build_object('snapshot_id',page.id,'after',last_key);exit;end if;
  rows:=rows||jsonb_build_array(app.challenge_detail_for_actor_v1(item.challenge_id,a));
  last_key:=jsonb_build_array(item.sort_at,item.starts_at,item.challenge_id);
 end loop;
 -- History insertions, exits or a late final can change ordering. Expire the
 -- cursor explicitly rather than silently skipping/duplicating an agreement.
 if generation<>coalesce((select revision from app.challenge_history_revisions_v1 where actor_id=a),0) then
  raise exception 'challenge_page_expired' using errcode='55000';
 end if;
 perform app.challenge_session_v1();
 return jsonb_build_object('section',p_section,'projection_revision',page.id,'server_time',app.challenge_now_v1(),'expires_at',page.expires_at,'rows',rows,'next_cursor',next_cursor);
end $$;

-- Evaluate safety as sets of live members and directed block edges. Do not call
-- the account and pairwise block functions for every member pair of every lobby.
create or replace function app.challenge_work_v1()
returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean)
language sql stable set search_path='' as $$
 with runtime as materialized (select r.actors,app.challenge_now_v1() now from app.challenge_runtime_v1 r where singleton and fixtures),
 live as materialized (
  select c.id,c.status,c.starts_at,c.ends_at from app.challenge_lobbies_v1 c,runtime r
  where c.status not in ('final','void','cancelled') and c.creator_id=any(r.actors)
   and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=c.id)
 ), members as materialized (
  select m.challenge_id,m.actor_id from live c join app.challenge_members_v1 m on m.challenge_id=c.id
  where m.selected and m.exited_at is null
 ), actors as materialized (select distinct actor_id from members),
 unavailable as materialized (
  select a.actor_id from actors a
  where app.challenge_actor_unavailable_v1(a.actor_id)
 ), unsafe as materialized (
  select m.challenge_id from members m join unavailable u using(actor_id)
  union
  select m.challenge_id from public.blocks b join members m on m.actor_id=b.blocker_id
   join members other on other.actor_id=b.blocked_id and other.challenge_id=m.challenge_id
 )
 select c.id,c.status,
 case when u.challenge_id is not null then r.now
  when c.status in ('lobby_open','published_open','consent_pending','scheduled') then c.starts_at
  when c.status='active' then c.ends_at
  when c.status='syncing' then c.ends_at+interval '48 hours 1 microsecond'
  when c.status='review' then case when exists(select 1 from app.challenge_reviews_v1 rv join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.decision='exclude' and s.recorded_at>n.recorded_at) then r.now
   else greatest(n.review_by,(select max(rv.resolve_by) from app.challenge_reviews_v1 rv left join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.review_id is null)) end
  else r.now end,
 n.challenge_id is null and r.now>c.ends_at+interval '72 hours',
 exists(select 1 from app.challenge_reviews_v1 rv left join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.review_id is null and r.now>=rv.resolve_by)
 from live c cross join runtime r left join unsafe u on u.challenge_id=c.id
 left join lateral(select challenge_id,recorded_at,review_by from app.challenge_notices_v1 where challenge_id=c.id order by revision desc limit 1) n on true
$$;

-- Capture one time bound, enabling an index range over immutable run receipts.
do $$ declare definition text;
begin
 definition:=pg_get_functiondef('public.challenge_operations_status_v1()'::regprocedure);
 if position('declare response jsonb;' in definition)=0 or position('where recorded_at>=app.challenge_now_v1()' in definition)=0 then raise exception 'Unexpected operations status source';end if;
 definition:=replace(definition,'declare response jsonb;','declare response jsonb; n timestamptz:=app.challenge_now_v1();');
 definition:=replace(definition,'app.challenge_now_v1()','n');
 definition:=replace(definition,'n timestamptz:=n;','n timestamptz:=app.challenge_now_v1();');
 execute definition;
end $$;

-- Retained only after identical-fixture index-on/off plans and write/WAL checks.
create index challenge_history_order_v1 on app.challenge_history_v1(actor_id,sort_at desc,starts_at,challenge_id);
create index challenge_live_creator_v1 on app.challenge_lobbies_v1(creator_id,id) include(status,starts_at,ends_at)
 where status not in ('final','void','cancelled');
create index challenge_worker_runs_recorded_v1 on app.challenge_worker_runs_v1(recorded_at);
