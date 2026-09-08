-- D134: separate local fictional Beta contract; no historical agreement changes.
create table app.challenge_runtime_v1 (
 singleton boolean primary key default true check(singleton),
 admission boolean not null default false, fixtures boolean not null default false,
 processing boolean not null default false, discovery boolean not null default false,
 ingestion boolean not null default false check(not ingestion),
 steps_source boolean not null default false check(not steps_source),
 exercise_source boolean not null default false check(not exercise_source),
 distance_source boolean not null default false check(not distance_source),
 timed_source boolean not null default false check(not timed_source),
 analytics boolean not null default false check(not analytics),
 actors uuid[] not null default '{}', fictional_now timestamptz,
 check(fictional_now is null or (fixtures and isfinite(fictional_now)))
);
insert into app.challenge_runtime_v1 default values;
create table app.challenge_lobbies_v1 (
 id uuid primary key, creator_id uuid not null references public.profiles(id),
 policy text not null check(policy='friend_steps_goal_v1'),
 config jsonb not null, starts_at timestamptz not null, ends_at timestamptz not null,
 status text not null check(status in ('lobby_open','consent_pending','scheduled','active','syncing','review','final','cancelled','void')),
 revision bigint not null default 1, agreement_version integer not null default 0,
 created_at timestamptz not null, check(starts_at<ends_at)
);
create table app.challenge_members_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id), actor_id uuid not null references public.profiles(id),
 selected boolean not null default false, target bigint check(target between 1 and 1000000000),
 exited_at timestamptz, primary key(challenge_id,actor_id)
);
create index challenge_members_actor_v1 on app.challenge_members_v1(actor_id);
create table app.challenge_agreements_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id), version integer not null,
 terms jsonb not null, digest text generated always as(encode(extensions.digest(terms::text,'sha256'),'hex')) stored,
 created_at timestamptz not null, primary key(challenge_id,version)
);
create table app.challenge_consents_v1 (
 challenge_id uuid not null, version integer not null, actor_id uuid not null references public.profiles(id),
 digest text not null, recorded_at timestamptz not null,
 primary key(challenge_id,version,actor_id), foreign key(challenge_id,version) references app.challenge_agreements_v1(challenge_id,version)
);
create table app.challenge_slots_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id), actor_id uuid not null references public.profiles(id),
 mode text not null default 'friend', metric text not null default 'steps', starts_at timestamptz not null, ends_at timestamptz not null,
 primary key(challenge_id,actor_id)
);
create index challenge_slots_actor_v1 on app.challenge_slots_v1(actor_id);
create table app.challenge_requests_v1 (
 actor_id uuid not null, request_id uuid not null, payload jsonb not null, response jsonb not null, recorded_at timestamptz not null,
 primary key(actor_id,request_id)
);
create table app.challenge_facts_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id), actor_id uuid not null references public.profiles(id),
 revision integer not null, value bigint check(value between 0 and 1000000000),
 state text not null check(state in ('complete','unresolved','deleted')),
 recorded_at timestamptz not null, request_id uuid not null unique,
 primary key(challenge_id,actor_id,revision), check((state='complete')=(value is not null))
);
create table app.challenge_notices_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id), revision integer not null,
 result jsonb not null, recorded_at timestamptz not null, review_by timestamptz not null,
 primary key(challenge_id,revision), check(review_by=recorded_at+interval '48 hours')
);
create table app.challenge_reviews_v1 (
 id uuid primary key, challenge_id uuid not null, notice_revision integer not null, actor_id uuid not null references public.profiles(id),
 reason text not null check(reason in ('wrong_total','missing_activity','wrong_result')),
 filed_at timestamptz not null, resolve_by timestamptz not null,
 unique(challenge_id,notice_revision,actor_id),
 foreign key(challenge_id,notice_revision) references app.challenge_notices_v1(challenge_id,revision),
 check(resolve_by=filed_at+interval '72 hours')
);
create table app.challenge_resolutions_v1 (
 review_id uuid primary key references app.challenge_reviews_v1(id), decision text not null check(decision in ('upheld','exclude')),
 operator_id uuid not null, recorded_at timestamptz not null
);
create table app.challenge_exits_v1 (
 id uuid primary key, challenge_id uuid not null references app.challenge_lobbies_v1(id), actor_id uuid not null references public.profiles(id),
 reason text not null, recorded_at timestamptz not null
);
create table app.challenge_finals_v1 (
 challenge_id uuid primary key references app.challenge_lobbies_v1(id), result jsonb not null,
 recorded_at timestamptz not null, revision bigint not null
);
create table app.challenge_readiness_v1 (
 actor_id uuid primary key references public.profiles(id), recorded_at timestamptz not null,
 source text not null check(source='fictional_steps_v1')
);

create function app.challenge_guard_v1() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
 or coalesce(current_setting('app.challenge_write_v1',true),'')<>'on' then
  raise exception 'challenge_rpc_required' using errcode='42501'; end if;
 if tg_op='INSERT' then return new; end if;
 if tg_table_name in ('challenge_runtime_v1','challenge_lobbies_v1','challenge_members_v1','challenge_slots_v1','challenge_readiness_v1') then
  if tg_op='UPDATE' then return new; end if;
  if tg_op='DELETE' and tg_table_name='challenge_slots_v1' then return old; end if;
 end if;
 raise exception 'challenge_immutable' using errcode='23001';
end $$;
do $$ declare t text; begin
 foreach t in array array['runtime','lobbies','members','agreements','consents','slots','requests','facts','notices','reviews','resolutions','exits','finals','readiness'] loop
  execute format('alter table app.challenge_%s_v1 enable row level security',t);
  execute format('revoke all on app.challenge_%s_v1 from public,anon,authenticated,service_role',t);
  execute format('create trigger challenge_guard before insert or update or delete on app.challenge_%s_v1 for each row execute function app.challenge_guard_v1()',t);
  execute format('create trigger challenge_no_truncate before truncate on app.challenge_%s_v1 for each statement execute function app.challenge_guard_v1()',t);
 end loop;
end $$;

create function app.challenge_now_v1() returns timestamptz language sql stable set search_path='' as $$
 select coalesce(fictional_now,clock_timestamp()) from app.challenge_runtime_v1 where singleton
$$;
create function app.challenge_session_v1() returns uuid language plpgsql set search_path='' as $$
declare a uuid:=auth.uid(); begin
 -- One bounded local-domain mutex serializes admission, transitions, exact
 -- requests and worker commits. Profile locks are always acquired in UUID order.
 perform 1 from app.challenge_runtime_v1 where singleton for update;
 if current_setting('role')<>'authenticated' or not app.is_active_actor(a)
 or not exists(select 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=a
   and (not_after is null or not_after>clock_timestamp())) then
  raise exception 'challenge_session_required' using errcode='42501'; end if;
 return a;
end $$;
create function app.challenge_admit_v1(a uuid) returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and admission and fixtures and a=any(actors)) then
  raise exception 'challenge_admission_paused' using errcode='42501'; end if;
end $$;
create function app.challenge_window_v1(j jsonb,n timestamptz) returns jsonb language plpgsql set search_path='' set timezone='UTC' as $$
declare d date; count_days integer; z text; amount integer; s timestamptz; e timestamptz; begin
 if jsonb_typeof(j) is distinct from 'object' or j-array['start_date','days','timezone','amount_cents']<>'{}'
  or not(j ?& array['start_date','days','timezone','amount_cents'])
  or j->>'days' !~ '^[0-9]+$' or j->>'amount_cents' !~ '^[0-9]+$'
  or j->>'start_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'challenge_invalid_window' using errcode='22023'; end if;
 d:=(j->>'start_date')::date; count_days:=(j->>'days')::integer; z:=j->>'timezone'; amount:=(j->>'amount_cents')::integer;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=z) or count_days not between 1 and 30
 or amount not between 100 and 50000 or amount%100<>0 then raise exception 'challenge_invalid_window' using errcode='22023'; end if;
 if d-(n at time zone z)::date not between 2 and 30 then raise exception 'challenge_invalid_lead' using errcode='22023'; end if;
 s:=d::timestamp at time zone z; e:=(d+count_days)::timestamp at time zone z;
 return j||jsonb_build_object('starts_at',s,'ends_at',e,'sync_by',e+interval '24 hours','corrections_by',e+interval '48 hours','notice_due',e+interval '72 hours');
end $$;
create function app.challenge_slot_v1(a uuid,c app.challenge_lobbies_v1) returns void language plpgsql set search_path='' as $$
begin
 if (select count(*) from app.challenge_slots_v1 where actor_id=a and challenge_id<>c.id)>=3 then
  raise exception 'challenge_unsettled_limit' using errcode='23505'; end if;
 if exists(select 1 from app.challenge_slots_v1 where actor_id=a and challenge_id<>c.id and mode='friend' and metric='steps'
  and tstzrange(starts_at,ends_at,'[)') && tstzrange(c.starts_at,c.ends_at,'[)')) then
  raise exception 'challenge_metric_overlap' using errcode='23505'; end if;
end $$;

create function public.challenge_preview_v1(p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform app.challenge_session_v1(); return app.challenge_window_v1(p_config,app.challenge_now_v1()); end $$;

create function public.challenge_mutate_v1(p_request_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare a uuid; op text; c app.challenge_lobbies_v1; member app.challenge_members_v1; saved app.challenge_requests_v1;
 n timestamptz; target_actor uuid; cid uuid; result jsonb; cfg jsonb; terms jsonb; ag app.challenge_agreements_v1;
 roster uuid[]; x uuid; notice app.challenge_notices_v1; allowed text[];
begin
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>16384 then
  raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 a:=app.challenge_session_v1(); op:=p_payload->>'op';
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then
  if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.response;
 end if;
 allowed:=case op
 when 'create' then array['op','config']
 when 'configure' then array['op','id','revision','config']
 when 'invite' then array['op','id','revision','username']
 when 'target' then array['op','id','revision','target']
 when 'select' then array['op','id','revision','actor_id','selected']
 when 'freeze' then array['op','id','revision']
 when 'reopen' then array['op','id','revision']
 when 'consent' then array['op','id','revision','digest','consent']
 when 'leave' then array['op','id','revision']
 when 'cancel' then array['op','id','revision']
 when 'review' then array['op','id','revision','notice_revision','reason'] end;
 if allowed is null or p_payload-allowed<>'{}' or not(p_payload ?& allowed) then raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 perform set_config('app.challenge_write_v1','on',true); n:=app.challenge_now_v1();
 if op='create' then
  perform app.challenge_admit_v1(a);
  if (select count(*) from app.challenge_lobbies_v1 where creator_id=a and status='lobby_open')>=10 then raise exception 'challenge_lobby_limit' using errcode='23505'; end if;
  cfg:=app.challenge_window_v1(p_payload->'config',n); cid:=extensions.gen_random_uuid();
  insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
   values(cid,a,'friend_steps_goal_v1',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,'lobby_open',n);
  insert into app.challenge_members_v1(challenge_id,actor_id,selected) values(cid,a,true);
 else
  cid:=(p_payload->>'id')::uuid;
  -- Bound participants are known only from persisted membership, never a caller roster.
  perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id=cid) order by id for update;
  a:=app.challenge_session_v1();
  select * into c from app.challenge_lobbies_v1 where id=cid for update;
  select * into member from app.challenge_members_v1 where challenge_id=cid and actor_id=a;
  if c.id is null or member.actor_id is null then raise exception 'challenge_unavailable' using errcode='42501'; end if;
  if c.revision is distinct from (p_payload->>'revision')::bigint then raise exception 'challenge_stale' using errcode='40001'; end if;
  n:=app.challenge_now_v1();
  if op not in ('leave','cancel','review') then
   perform app.challenge_admit_v1(a);
   if member.exited_at is not null or not app.is_active_actor(c.creator_id)
    or exists(select 1 from app.challenge_members_v1 p where p.challenge_id=cid and p.exited_at is null and app.is_blocked_either_way(a,p.actor_id)) then
     raise exception 'challenge_unavailable' using errcode='42501'; end if;
  end if;
  if op in ('configure','invite','target','select','freeze') and (c.status<>'lobby_open' or n>=c.starts_at) then raise exception 'challenge_lobby_closed' using errcode='55000'; end if;
  if op in ('configure','invite','select','freeze','reopen','cancel') and a<>c.creator_id then raise exception 'challenge_creator_required' using errcode='42501'; end if;
  if op='configure' then
   cfg:=app.challenge_window_v1(p_payload->'config',n);
   update app.challenge_lobbies_v1 set config=cfg,starts_at=(cfg->>'starts_at')::timestamptz,ends_at=(cfg->>'ends_at')::timestamptz where id=cid;
  elsif op='invite' then
   select id into target_actor from public.profiles where lower(handle)=lower(p_payload->>'username') and app.is_active_actor(id);
   if target_actor is null or not app.is_friend(a,target_actor) or app.is_blocked_either_way(a,target_actor) then raise exception 'challenge_friend_unavailable' using errcode='42501'; end if;
   if (select count(*) from app.challenge_members_v1 where challenge_id=cid)>=30 then raise exception 'challenge_entrant_limit' using errcode='23505'; end if;
   insert into app.challenge_members_v1(challenge_id,actor_id) values(cid,target_actor) on conflict do nothing;
  elsif op='target' then
   if jsonb_typeof(p_payload->'target') is distinct from 'number' or p_payload->>'target' !~ '^[0-9]+$'
    or (p_payload->>'target')::numeric not between 1 and 1000000000 then raise exception 'challenge_invalid_target' using errcode='22023'; end if;
   update app.challenge_members_v1 set target=(p_payload->>'target')::bigint where challenge_id=cid and actor_id=a;
  elsif op='select' then
   target_actor:=(p_payload->>'actor_id')::uuid;
   if jsonb_typeof(p_payload->'selected') is distinct from 'boolean' or target_actor=a then raise exception 'challenge_invalid_selection' using errcode='22023'; end if;
   update app.challenge_members_v1 set selected=(p_payload->>'selected')::boolean where challenge_id=cid and actor_id=target_actor and exited_at is null;
   if not found then raise exception 'challenge_entrant_unavailable' using errcode='22023'; end if;
   if (select count(*) from app.challenge_members_v1 where challenge_id=cid and selected and exited_at is null)>6 then raise exception 'challenge_capacity' using errcode='23505'; end if;
  elsif op='freeze' then
   select array_agg(actor_id order by actor_id) into roster from app.challenge_members_v1 where challenge_id=cid and selected and exited_at is null;
   if cardinality(roster) not between 2 and 6 or not(a=any(roster)) or exists(select 1 from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster) and target is null) then raise exception 'challenge_incomplete_roster' using errcode='22023'; end if;
   foreach x in array roster loop
    perform app.challenge_admit_v1(x);
    if not app.is_active_actor(x) or exists(select 1 from unnest(roster) y where app.is_blocked_either_way(x,y)) then raise exception 'challenge_participant_unavailable' using errcode='42501'; end if;
    perform app.challenge_slot_v1(x,c);
    insert into app.challenge_slots_v1(challenge_id,actor_id,starts_at,ends_at) values(cid,x,c.starts_at,c.ends_at);
   end loop;
   select jsonb_build_object('policy',c.policy,'source','fictional_steps_v1','mode','friend','competition','goal',
    'metric','steps','unit','whole_counts','config',c.config,'version',c.agreement_version+1,
    'participants',jsonb_agg(jsonb_build_object('actor_id',actor_id,'target',target) order by actor_id),
    'simulation','nonredeemable','review_hours',48,'resolution_hours',72,
    'missing_rule','exclude_refund_minimum_two','exit_rule','exclude_refund_minimum_two',
    'allocation_rule','return_qualifiers_split_misses_remainder_unallocated') into terms
    from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster);
   insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at) values(cid,c.agreement_version+1,terms,n);
   update app.challenge_lobbies_v1 set status='consent_pending',agreement_version=agreement_version+1 where id=cid;
  elsif op='reopen' then
   if c.status not in ('consent_pending','scheduled') or n>=c.starts_at then raise exception 'challenge_cannot_reopen' using errcode='55000'; end if;
   delete from app.challenge_slots_v1 where challenge_id=cid;
   update app.challenge_lobbies_v1 set status='lobby_open' where id=cid;
  elsif op='consent' then
   select * into ag from app.challenge_agreements_v1 where challenge_id=cid and version=c.agreement_version;
   if c.status<>'consent_pending' or n>=c.starts_at or not member.selected or member.exited_at is not null
    or p_payload->'consent' is distinct from 'true'::jsonb or p_payload->>'digest' is distinct from ag.digest then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
   if not exists(select 1 from app.challenge_readiness_v1 where actor_id=a and recorded_at between n-interval '30 days' and n) then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
   insert into app.challenge_consents_v1 values(cid,c.agreement_version,a,ag.digest,n) on conflict do nothing;
   if not exists(select 1 from app.challenge_slots_v1 p where p.challenge_id=cid and not exists(select 1 from app.challenge_consents_v1 s where s.challenge_id=cid and s.version=c.agreement_version and s.actor_id=p.actor_id)) then
    update app.challenge_lobbies_v1 set status='scheduled' where id=cid;
   end if;
  elsif op in ('leave','cancel') then
   if c.status in ('final','cancelled','void') then raise exception 'challenge_already_closed' using errcode='55000'; end if;
   if op='cancel' and n>=c.starts_at then raise exception 'challenge_use_leave' using errcode='55000'; end if;
   insert into app.challenge_exits_v1 values(p_request_id,cid,a,op,n);
   update app.challenge_members_v1 set exited_at=n where challenge_id=cid and actor_id=a;
   if op='cancel' then
    update app.challenge_lobbies_v1 set status='cancelled' where id=cid;
   elsif c.status='lobby_open' then
    update app.challenge_members_v1 set selected=false where challenge_id=cid and actor_id=a;
    if a=c.creator_id then update app.challenge_lobbies_v1 set status='cancelled' where id=cid; end if;
   end if;
  elsif op='review' then
   select * into notice from app.challenge_notices_v1 where challenge_id=cid order by revision desc limit 1;
   if c.status<>'review' or n>=notice.review_by or (p_payload->>'notice_revision')::integer is distinct from notice.revision
    or not exists(select 1 from app.challenge_slots_v1 where challenge_id=cid and actor_id=a)
    or p_payload->>'reason' not in ('wrong_total','missing_activity','wrong_result') then raise exception 'challenge_review_closed' using errcode='55000'; end if;
   insert into app.challenge_reviews_v1 values(p_request_id,cid,notice.revision,a,p_payload->>'reason',n,n+interval '72 hours');
  end if;
  update app.challenge_lobbies_v1 set revision=revision+1 where id=cid;
 end if;
 select jsonb_build_object('id',id,'revision',revision,'status',status) into result from app.challenge_lobbies_v1 where id=cid;
 insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,n);
 return result;
end $$;

create function public.challenge_detail_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; c app.challenge_lobbies_v1; hidden boolean; projection jsonb; begin
 a:=app.challenge_session_v1(); select * into c from app.challenge_lobbies_v1 where id=p_id;
 if not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_unavailable' using errcode='42501'; end if;
 hidden:=not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a and selected and exited_at is null) or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id<>a and (not app.is_active_actor(actor_id) or app.is_blocked_either_way(a,actor_id)));
 projection:=jsonb_build_object('id',c.id,'creator_id',case when not hidden or c.creator_id=a then c.creator_id end,'policy',c.policy,'config',c.config,
  'status',c.status,'revision',c.revision,'agreement_version',c.agreement_version,'server_time',app.challenge_now_v1(),'social_hidden',hidden,
  'agreement',(select jsonb_build_object('digest',digest,'terms',case when not hidden then terms end) from app.challenge_agreements_v1 where challenge_id=p_id and version=c.agreement_version),
  'members',(select coalesce(jsonb_agg(jsonb_build_object('actor_id',m.actor_id,'username',p.handle,'target',m.target,'selected',m.selected,'exited',m.exited_at is not null,
    'consented',exists(select 1 from app.challenge_consents_v1 where challenge_id=p_id and version=c.agreement_version and actor_id=m.actor_id),
    'fact',(select jsonb_build_object('value',value,'state',state,'recorded_at',recorded_at,'revision',revision) from app.challenge_facts_v1 where challenge_id=p_id and actor_id=m.actor_id order by revision desc limit 1)) order by m.actor_id),'[]')
    from app.challenge_members_v1 m join public.profiles p on p.id=m.actor_id where m.challenge_id=p_id and (not hidden or m.actor_id=a)),
  'notice',(select jsonb_build_object('revision',revision,'recorded_at',recorded_at,'review_by',review_by,'result',case when not hidden then result end) from app.challenge_notices_v1 where challenge_id=p_id order by revision desc limit 1),
  'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'reason',r.reason,'filed_at',r.filed_at,'resolve_by',r.resolve_by,'decision',s.decision) order by r.filed_at),'[]') from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=p_id and r.actor_id=a),
  'final',(select jsonb_build_object('recorded_at',recorded_at,'result',case when not hidden then result else jsonb_build_object('own',result->'participants'->a::text) end) from app.challenge_finals_v1 where challenge_id=p_id));
 return projection;
end $$;
create function public.challenge_list_v1() returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; begin
 a:=app.challenge_session_v1();
 return (select coalesce(jsonb_agg(public.challenge_detail_v1(id) order by created_at desc,id),'[]') from
  (select c.* from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id where m.actor_id=a order by c.created_at desc,c.id limit 100) q);
end $$;

do $$ declare f regprocedure; begin
 for f in select oid::regprocedure from pg_proc where pronamespace='app'::regnamespace and proname like 'challenge_%_v1' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f); end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname like 'challenge_%_v1' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
