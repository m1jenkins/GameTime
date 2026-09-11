-- Prompt 4: replace the singleton runtime-row mutex with a shared gate fence,
-- actor/link/challenge scoped locks, and bounded nonblocking worker claims.
-- Historical agreements and every existing public signature remain unchanged.

create function app.challenge_lock_key_v1(p_scope text, p_id uuid)
returns bigint
language sql immutable strict parallel safe
set search_path = ''
as $$
 select pg_catalog.hashtextextended(
  'gametime.challenge.v1.' || p_scope || '.' || p_id::text,
  0
 )
$$;

create function app.challenge_gate_v1(p_exclusive boolean default false)
returns void
language plpgsql
set search_path = ''
as $$
declare
 key bigint := app.challenge_lock_key_v1(
  'gate',
  '00000000-0000-0000-0000-000000000000'::uuid
 );
begin
 if p_exclusive then
  perform pg_catalog.pg_advisory_xact_lock(key);
 else
  perform pg_catalog.pg_advisory_xact_lock_shared(key);
 end if;
end
$$;

create function app.challenge_lock_v1(p_scope text, p_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
 if p_scope is null then
  raise exception 'challenge_invalid_lock' using errcode = '22023';
 end if;
 -- Public functions retain their existing validation/error semantics for null
 -- resource IDs; they reject before mutation, so there is nothing to lock.
 if p_id is null then return; end if;
 perform pg_catalog.pg_advisory_xact_lock(
  app.challenge_lock_key_v1(p_scope, p_id)
 );
end
$$;

create function app.challenge_lock_many_v1(p_scope text, p_ids uuid[])
returns void
language plpgsql
set search_path = ''
as $$
declare
 item uuid;
begin
 if p_scope is null or p_ids is null or array_position(p_ids, null) is not null then
  raise exception 'challenge_invalid_lock' using errcode = '22023';
 end if;
 for item in
  select distinct value from unnest(p_ids) value order by value
 loop
  perform app.challenge_lock_v1(p_scope, item);
 end loop;
end
$$;

-- Gate changes remain an exclusive fence, while ordinary authenticated and
-- worker transactions take a shared gate lock and may proceed concurrently.
create or replace function app.challenge_session_v1()
returns uuid
language plpgsql
set search_path = ''
as $$
declare
 a uuid := auth.uid();
 live uuid;
 expires timestamptz;
begin
 if current_setting('role') <> 'authenticated' or a is null then
  raise exception 'challenge_session_required' using errcode = '42501';
 end if;
 perform app.challenge_gate_v1();
 perform app.challenge_lock_v1('actor', a);
 if not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode = '42501';
 end if;
 select id, not_after into live, expires from auth.sessions
  where id::text = auth.jwt()->>'session_id' and user_id = a
   and (not_after is null or not_after > clock_timestamp())
  for share;
 if live is null or expires <= clock_timestamp() or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode = '42501';
 end if;
 return a;
end
$$;

do $$
declare
 definition text;
 revised text;
 marker text;
begin
 -- The control plane is the sole exclusive gate owner.
 definition := pg_get_functiondef('public.challenge_runtime_v1(boolean,boolean,boolean,uuid[],timestamptz)'::regprocedure);
 marker := 'perform app.duel_require_service_v1();';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge runtime function'; end if;
 revised := replace(definition, marker, marker || ' perform app.challenge_gate_v1(true);');
 execute revised;

 -- Existing-challenge participant mutations lock actor -> challenge -> profiles.
 definition := pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 marker := 'cid:=(p_payload->>''id'')::uuid;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge mutate function'; end if;
 revised := replace(definition, marker, marker || E'\n  perform app.challenge_lock_v1(''challenge'',cid);');
 execute revised;

 -- Lifecycle work locks gate -> challenge -> profiles -> lobby everywhere.
 definition := pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
 marker := 'perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge tick function'; end if;
 revised := replace(definition, marker, E'perform app.challenge_gate_v1();\n perform app.challenge_lock_v1(''challenge'',p_id);');
 execute revised;

 -- Fixture writes use the same actor/challenge scopes as product work.
 definition := pg_get_functiondef('public.challenge_readiness_metric_fixture_v1(uuid,text)'::regprocedure);
 marker := 'perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge readiness function'; end if;
 revised := replace(definition, marker, 'perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1(''actor'',p_actor);');
 execute revised;

 definition := pg_get_functiondef('public.challenge_capture_fixture_v1(uuid,uuid,uuid,bigint,text)'::regprocedure);
 marker := 'perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge capture function'; end if;
 revised := replace(definition, marker, 'perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1(''fixture_request'',p_request_id); perform app.challenge_lock_v1(''challenge'',p_id);');
 execute revised;

 -- Service review resolution is scoped to its durable request and challenge.
 definition := pg_get_functiondef('public.challenge_resolve_v1(uuid,uuid,text)'::regprocedure);
 marker := 'perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge resolve function'; end if;
 revised := replace(definition, marker, 'perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1(''review'',p_review_id);');
 marker := 'select * into r from app.challenge_reviews_v1 where id=p_review_id;';
 revised := replace(revised, marker, marker || E'\n if r.id is not null then perform app.challenge_lock_v1(''challenge'',r.challenge_id); select * into r from app.challenge_reviews_v1 where id=p_review_id; end if;');
 execute revised;

 -- Link issue/join and operator writes coordinate with the same challenge tick.
 definition := pg_get_functiondef('public.challenge_issue_link_v1(uuid,uuid)'::regprocedure);
 marker := 'perform app.challenge_admit_v1(a);n:=app.challenge_now_v1();';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge issue-link function'; end if;
 revised := replace(definition, marker, marker || 'perform app.challenge_lock_v1(''challenge'',p_id);');
 execute revised;

 definition := pg_get_functiondef('public.challenge_join_community_v1(uuid,jsonb)'::regprocedure);
 marker := 'perform app.challenge_admit_v1(actor);n:=app.challenge_now_v1();';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge community join function'; end if;
 revised := replace(definition, marker, marker || 'perform app.challenge_lock_v1(''challenge'',(p_payload->>''id'')::uuid);');
 execute revised;

 definition := pg_get_functiondef('public.challenge_redeem_link_v1(uuid,text)'::regprocedure);
 marker := 'select * into l from app.challenge_links_v1 where token_hash=payload->>''token_hash'' for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge redeem-link function'; end if;
 revised := replace(definition, marker, marker || E'\n perform app.challenge_lock_v1(''challenge'',l.challenge_id);');
 execute revised;

 definition := pg_get_functiondef('public.challenge_operator_action_v1(uuid,jsonb)'::regprocedure);
 marker := 'actor:=app.challenge_session_v1();op:=p_payload->>''op'';cid:=(p_payload->>''id'')::uuid;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge operator-action function'; end if;
 revised := replace(definition, marker, marker || 'perform app.challenge_lock_v1(''challenge'',cid);');
 execute revised;

 definition := pg_get_functiondef('public.challenge_grant_operator_v1(uuid,uuid,text,timestamptz)'::regprocedure);
 marker := 'perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge grant function'; end if;
 revised := replace(definition, marker, 'perform app.duel_require_service_v1();perform app.challenge_gate_v1();perform app.challenge_lock_v1(''challenge'',p_id);');
 execute revised;
end
$$;

-- A block can touch several shared challenges. Acquire every challenge scope in
-- UUID order before profile rows; nested safe ticks reacquire the same locks.
create or replace function public.challenge_block_v1(p_request_id uuid,p_subject uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
 a uuid;
 c uuid;
 ids uuid[];
 saved app.challenge_requests_v1;
 payload jsonb;
begin
 a := app.challenge_session_v1();
 payload := jsonb_build_object('op','block','subject',p_subject);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.response;
 end if;
 select array_agg(me.challenge_id order by me.challenge_id) into ids
  from app.challenge_members_v1 me
  join app.challenge_members_v1 other using(challenge_id)
  where me.actor_id=a and other.actor_id=p_subject;
 if p_request_id is null or p_subject is null or a=p_subject or ids is null then
  raise exception 'challenge_block_unavailable' using errcode='42501';
 end if;
 perform app.challenge_lock_many_v1('challenge',ids);
 perform id from public.profiles where id in(a,p_subject) order by id for update;
 perform set_config('app.challenge_write_v1','on',true);
 insert into public.blocks(blocker_id,blocked_id) values(a,p_subject) on conflict do nothing;
 foreach c in array ids loop
  perform app.challenge_tick_v1(c,true);
 end loop;
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"blocked":true}',app.challenge_now_v1());
 return jsonb_build_object('blocked',true);
end
$$;

-- One fixture may exercise the adopted 250-person Beta planning boundary. This
-- changes no published setting: community publication remains fixture-only.
do $$
declare
 constraint_name text;
begin
 select conname into strict constraint_name
 from pg_catalog.pg_constraint
 where conrelid='app.challenge_lobbies_v1'::regclass
  and contype='c'
  and pg_catalog.pg_get_constraintdef(oid) like '%capacity <= 100%'
  and pg_catalog.pg_get_constraintdef(oid) like '%capacity >= minimum%';
 execute format('alter table app.challenge_lobbies_v1 drop constraint %I',constraint_name);
end
$$;
alter table app.challenge_lobbies_v1
 add constraint challenge_lobbies_v1_capacity_check
 check(capacity between 1 and 250 and capacity>=minimum);

do $$
declare
 definition text;
 revised text;
begin
 definition := pg_get_functiondef('public.challenge_publish_community_fixture_v1(uuid,uuid,jsonb,bigint,integer,integer,boolean)'::regprocedure);
 if position('p_capacity not between p_minimum and 100' in definition) = 0
  or position('perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;' in definition) = 0 then
  raise exception 'Unexpected challenge community publication function';
 end if;
 revised := replace(definition,'p_capacity not between p_minimum and 100','p_capacity not between p_minimum and 250');
 revised := replace(revised,
  'perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;',
  'perform app.duel_require_service_v1();perform app.challenge_gate_v1();perform app.challenge_lock_v1(''actor'',p_operator);perform app.challenge_lock_v1(''community_publication'',''00000000-0000-0000-0000-000000000000''::uuid);');
 execute revised;

 definition := pg_get_functiondef('app.challenge_evaluate_policy_v1(text,jsonb,integer,integer,boolean)'::regprocedure);
 if position('count_people>100' in definition) = 0 then raise exception 'Unexpected challenge evaluator capacity'; end if;
 execute replace(definition,'count_people>100','count_people>250');
end
$$;

create or replace function app.challenge_work_v1()
returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean)
language sql stable
set search_path = ''
as $$
 select c.id,c.status,
 case when exists(select 1 from app.challenge_members_v1 p where p.challenge_id=c.id and p.selected and p.exited_at is null and
  (app.challenge_actor_unavailable_v1(p.actor_id) or exists(select 1 from app.challenge_members_v1 other where other.challenge_id=c.id and other.selected and other.exited_at is null and app.is_blocked_either_way(p.actor_id,other.actor_id)))) then app.challenge_now_v1()
 when c.status in ('lobby_open','published_open','consent_pending','scheduled') then c.starts_at
 when c.status='active' then c.ends_at
 when c.status='syncing' then c.ends_at+interval '48 hours 1 microsecond'
 when c.status='review' then case when exists(select 1 from app.challenge_reviews_v1 r join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.decision='exclude' and s.recorded_at>n.recorded_at) then app.challenge_now_v1()
 else greatest(n.review_by,(select max(r.resolve_by) from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.review_id is null)) end
 else app.challenge_now_v1() end,
 n.challenge_id is null and app.challenge_now_v1()>c.ends_at+interval '72 hours',
 exists(select 1 from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.review_id is null and app.challenge_now_v1()>=r.resolve_by)
 from app.challenge_lobbies_v1 c
 left join lateral(select * from app.challenge_notices_v1 where challenge_id=c.id order by revision desc limit 1)n on true
 where not exists(select 1 from app.challenge_finals_v1 where challenge_id=c.id)
  and c.status not in ('final','void','cancelled')
  and exists(select 1 from app.challenge_runtime_v1 r where r.singleton and r.fixtures and c.creator_id=any(r.actors))
$$;

create function app.challenge_claim_work_v1(p_limit integer)
returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean)
language plpgsql
set search_path = ''
as $$
declare
 item record;
 claimed integer := 0;
begin
 if p_limit is null or p_limit not between 1 and 50 then
  raise exception 'challenge_invalid_batch' using errcode='22023';
 end if;
 for item in
  select work.* from app.challenge_work_v1() work
  where work.due_at<=app.challenge_now_v1()
  order by work.due_at,work.id
  limit least(p_limit*10,500)
 loop
  if pg_catalog.pg_try_advisory_xact_lock(app.challenge_lock_key_v1('challenge',item.id))
   and exists(select 1 from app.challenge_work_v1() current_work where current_work.id=item.id and current_work.due_at<=app.challenge_now_v1()) then
   id:=item.id;status:=item.status;due_at:=item.due_at;
   notice_overdue:=item.notice_overdue;review_overdue:=item.review_overdue;
   claimed:=claimed+1;
   return next;
   exit when claimed>=p_limit;
  end if;
 end loop;
end
$$;

create or replace function public.challenge_run_batch_v1(p_run_id uuid,p_limit integer default 20)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
 saved app.challenge_worker_runs_v1;
 payload jsonb:=jsonb_build_object('version','challenge_batch_v1','limit',p_limit);
 item record;
 processed jsonb:=jsonb_build_array();
 failed integer:=0;
 outcome text;
 response jsonb;
begin
 perform app.duel_require_service_v1();
 if p_run_id is null or p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_batch' using errcode='22023'; end if;
 perform app.challenge_gate_v1();
 perform app.challenge_lock_v1('worker_run',p_run_id);
 select * into saved from app.challenge_worker_runs_v1 where id=p_run_id;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.result;
 end if;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 for item in select * from app.challenge_claim_work_v1(p_limit) loop
  begin
   outcome:=app.challenge_tick_v1(item.id,not (select processing from app.challenge_runtime_v1 where singleton));
   processed:=processed||jsonb_build_array(jsonb_build_object('id',item.id,'status',outcome));
  exception when others then
   failed:=failed+1;
   processed:=processed||jsonb_build_array(jsonb_build_object('id',item.id,'error_code',sqlstate));
  end;
 end loop;
 response:=jsonb_build_object('run_id',p_run_id,'processed',processed,'failed_count',failed,'server_time',app.challenge_now_v1());
 insert into app.challenge_worker_runs_v1 values(p_run_id,payload,response,app.challenge_now_v1());
 return response;
end
$$;

do $$
declare
 definition text;
 revised text;
 marker text;
begin
 definition := pg_get_functiondef('public.challenge_operator_close_v1(uuid,uuid)'::regprocedure);
 marker := 'a:=app.challenge_session_v1();';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge operator-close function'; end if;
 revised := replace(definition,marker,marker||'perform app.challenge_lock_v1(''challenge'',p_id);');
 revised := replace(revised,'select * into c from app.challenge_lobbies_v1 where id=p_id;','select * into c from app.challenge_lobbies_v1 where id=p_id for update;');
 execute revised;

 definition := pg_get_functiondef('public.challenge_discovery_fixture_v1(boolean)'::regprocedure);
 marker := 'perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;';
 if position(marker in definition) = 0 then raise exception 'Unexpected challenge discovery function'; end if;
 execute replace(definition,marker,'perform app.duel_require_service_v1();perform app.challenge_gate_v1(true);');
end
$$;

-- Restore the exact existing public ACLs after replacement, and keep every new
-- helper internal. CREATE OR REPLACE preserves security mode and other grants.
revoke all on function
 app.challenge_lock_key_v1(text,uuid),
 app.challenge_gate_v1(boolean),
 app.challenge_lock_v1(text,uuid),
 app.challenge_lock_many_v1(text,uuid[]),
 app.challenge_claim_work_v1(integer)
from public,anon,authenticated,service_role;
