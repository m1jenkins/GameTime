-- P4 completion. Retained migrations and challenge agreements are immutable.
-- Reads: session SHARE only. Mutations: gate SHARE -> calling actor -> session
-- SHARE -> request scope (if any) -> challenge UUIDs ascending -> profile UUIDs
-- ascending -> lobby/link/member rows. Never acquire another actor mutex after
-- taking a challenge. Profiles serialize cross-challenge admission and legacy
-- account safety. Only control-plane changes take the gate EXCLUSIVE.
create or replace function app.challenge_session_v1()
returns uuid language plpgsql set search_path = '' as $$
declare a uuid := auth.uid(); live uuid; expires timestamptz;
begin
 if current_setting('role') <> 'authenticated' or a is null or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode='42501';
 end if;
 select id,not_after into live,expires from auth.sessions
 where id::text=auth.jwt()->>'session_id' and user_id=a
  and (not_after is null or not_after>clock_timestamp()) for share;
 if live is null or expires<=clock_timestamp() or not app.is_active_actor(a) then
  raise exception 'challenge_session_required' using errcode='42501';
 end if;
 return a;
end $$;

create function app.challenge_mutation_session_v1()
returns uuid language plpgsql set search_path = '' as $$
declare a uuid := auth.uid();
begin
 if current_setting('role') <> 'authenticated' or a is null then
  raise exception 'challenge_session_required' using errcode='42501';
 end if;
 perform app.challenge_gate_v1();
 perform app.challenge_lock_v1('actor',a);
 return app.challenge_session_v1();
end $$;

do $$
declare signature text; definition text; marker text;
begin
 -- All public entry points which journal a request use the mutation helper,
 -- including direct RPC calls and the dispatcher/abandon path.
 foreach signature in array array[
  'public.challenge_command_v1(uuid,jsonb)', 'public.challenge_mutate_v1(uuid,jsonb)',
  'public.challenge_abandon_v1(uuid,jsonb)', 'public.challenge_confirm_age_v1(uuid,boolean)',
  'public.challenge_issue_link_v1(uuid,uuid)', 'public.challenge_redeem_link_v1(uuid,text)',
  'public.challenge_revoke_link_v1(uuid,uuid)', 'public.challenge_report_v1(uuid,uuid,text)',
  'public.challenge_block_v1(uuid,uuid)', 'public.challenge_join_community_v1(uuid,jsonb)',
  'public.challenge_operator_action_v1(uuid,jsonb)', 'public.challenge_operator_close_v1(uuid,uuid)'
 ] loop
  definition := pg_get_functiondef(signature::regprocedure);
  if position('app.challenge_session_v1()' in definition)=0 then raise exception 'Missing session in %',signature; end if;
  -- Only the entry validation takes mutation locks. Later rechecks must not
  -- introduce a new order after resource/profile locks.
  execute regexp_replace(definition,'app.challenge_session_v1\(\)','app.challenge_mutation_session_v1()');
 end loop;

 -- Redemption must take challenge before link, matching issue/revoke/closure.
 definition := pg_get_functiondef('public.challenge_redeem_link_v1(uuid,text)'::regprocedure);
 marker := E'select * into l from app.challenge_links_v1 where token_hash=payload->>''token_hash'' for update;\n perform app.challenge_lock_v1(''challenge'',l.challenge_id);';
 if position(marker in definition)=0 then raise exception 'Unexpected redemption locks'; end if;
 execute replace(definition,marker,E'select * into l from app.challenge_links_v1 where token_hash=payload->>''token_hash'';\n perform app.challenge_lock_v1(''challenge'',l.challenge_id);\n perform id from public.profiles where id in(a,l.issuer) order by id for update;\n perform app.challenge_session_v1();\n select * into l from app.challenge_links_v1 where token_hash=payload->>''token_hash'' for update;');

 definition := pg_get_functiondef('public.challenge_revoke_link_v1(uuid,uuid)'::regprocedure);
 marker := 'perform set_config(''app.challenge_write_v1'',''on'',true);update app.challenge_links_v1';
 if position(marker in definition)=0 then raise exception 'Unexpected revoke locks'; end if;
 execute replace(definition,marker,'perform app.challenge_lock_v1(''challenge'',(select challenge_id from app.challenge_links_v1 where id=p_link_id)); '||marker);

 -- Freeze already locks every bound profile. Join/personal must lock the same
 -- profile before checking the shared three-unsettled/overlap limit.
 definition := pg_get_functiondef('public.challenge_join_community_v1(uuid,jsonb)'::regprocedure);
 marker := 'select * into c from app.challenge_lobbies_v1 where id=(p_payload->>''id'')::uuid for update;';
 if position(marker in definition)=0 then raise exception 'Unexpected community join locks'; end if;
 execute replace(definition,marker,'perform id from public.profiles where id=actor for update; perform app.challenge_session_v1(); perform app.challenge_admit_v1(actor); '||marker||' n:=app.challenge_now_v1();');

 definition := pg_get_functiondef('public.challenge_issue_link_v1(uuid,uuid)'::regprocedure);
 marker := 'select * into c from app.challenge_lobbies_v1 where id=p_id for update;';
 if position(marker in definition)=0 then raise exception 'Unexpected link issue locks'; end if;
 execute replace(definition,marker,'perform id from public.profiles where id=a for update; perform app.challenge_session_v1(); perform app.challenge_admit_v1(a); '||marker||' n:=app.challenge_now_v1();');

 definition := pg_get_functiondef('app.challenge_personal_commit_v1(uuid,jsonb)'::regprocedure);
 marker := 'perform id from public.profiles where id=a for update;perform app.challenge_session_v1();';
 if position(marker in definition)=0 then raise exception 'Unexpected personal admission locks'; end if;
 execute replace(definition,marker,marker||'perform app.challenge_admit_v1(a);');

 -- Include a new invitee in the first sorted profile set. The membership FK
 -- otherwise locks that profile later and reciprocal invitations can deadlock.
 definition := pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 marker := 'select id into target_actor from public.profiles where lower(handle)=lower(p_payload->>''username'') and app.is_active_actor(id);';
 if position(marker in definition)=0 then raise exception 'Unexpected invite lookup'; end if;
 definition := replace(definition,marker,'if not exists(select 1 from public.profiles where id=target_actor and lower(handle)=lower(p_payload->>''username'') and app.is_active_actor(id)) then raise exception ''challenge_friend_unavailable'' using errcode=''42501''; end if;');
 if position('perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id=cid) order by id for update;' in definition)=0 then raise exception 'Unexpected invite profile locks'; end if;
 execute replace(definition,'perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id=cid) order by id for update;',
  'if op=''invite'' then '||marker||' end if; perform id from public.profiles where id=target_actor or id in(select actor_id from app.challenge_members_v1 where challenge_id=cid) order by id for update;');

 -- Prelock the UNION of profiles for multi-challenge safety work. Locking only
 -- blocker/subject first can invert the UUID order in a nested safe tick.
 definition := pg_get_functiondef('public.challenge_block_v1(uuid,uuid)'::regprocedure);
 marker := 'perform id from public.profiles where id in(a,p_subject) order by id for update;';
 if position(marker in definition)=0 then raise exception 'Unexpected block locks'; end if;
 execute replace(definition,marker,'perform id from public.profiles where id in(a,p_subject) or id in(select actor_id from app.challenge_members_v1 where challenge_id=any(ids)) order by id for update; perform app.challenge_session_v1();');

 -- Moderation must coordinate with admission on other challenges; acquire the
 -- complete profile set before writing an exit (whose deferred trigger ticks).
 foreach signature in array array['public.challenge_operator_action_v1(uuid,jsonb)','public.challenge_operator_close_v1(uuid,uuid)'] loop
  definition := pg_get_functiondef(signature::regprocedure);
  marker := case when signature like '%action%' then 'perform app.challenge_lock_v1(''challenge'',cid);' else 'perform app.challenge_lock_v1(''challenge'',p_id);' end;
  if position(marker in definition)=0 then raise exception 'Unexpected operator locks'; end if;
  execute replace(definition,marker,marker||' perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id='||case when signature like '%action%' then 'cid' else 'p_id' end||') order by id for update; perform app.challenge_session_v1();');
 end loop;

 -- A direct safe tick of an already cancelled draft is also a no-op. A
 -- cancelled agreement without a final still needs its synchronous safe exit.
 definition := pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
 marker := 'if exists(select 1 from app.challenge_finals_v1 where challenge_id=p_id) then return c.status; end if;';
 if position(marker in definition)=0 then raise exception 'Unexpected tick terminal guard'; end if;
 execute replace(definition,marker,marker||' if c.status=''cancelled'' and not exists(select 1 from app.challenge_slots_v1 where challenge_id=p_id) then return c.status; end if;');
end $$;

-- The parameterized inventory lets completion recheck ONE challenge. Discovery
-- evaluates the inventory once per batch, not once again for every candidate.
do $$ declare definition text;
begin
 definition := pg_get_functiondef('app.challenge_work_v1()'::regprocedure);
 definition := replace(definition,'app.challenge_work_v1()','app.challenge_work_item_v1(p_id uuid)');
 definition := replace(definition,'where not exists(select 1 from app.challenge_finals_v1','where (p_id is null or c.id=p_id) and not exists(select 1 from app.challenge_finals_v1');
 execute definition;
end $$;
create or replace function app.challenge_work_v1()
returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean)
language sql stable set search_path = '' as $$ select * from app.challenge_work_item_v1(null) $$;

-- One coordination row per challenge, no generic job/queue framework. Timing for
-- leases/backoff is wall clock; agreement/notice deadlines use challenge_now.
create table app.challenge_work_claims_v1 (
 challenge_id uuid primary key references app.challenge_lobbies_v1(id),
 state text not null default 'ready' check(state in ('ready','claimed','retry','dead')),
 claim_token uuid unique,
 attempts integer not null default 0 check(attempts between 0 and 5),
 total_attempts bigint not null default 0 check(total_attempts>=attempts),
 next_attempt_at timestamptz not null default clock_timestamp(),
 lease_expires_at timestamptz,
 last_error_code text check(last_error_code ~ '^[0-9A-Z]{5}$'),
 updated_at timestamptz not null default clock_timestamp(),
 check((state='claimed')=(lease_expires_at is not null)),
 check(state<>'claimed' or claim_token is not null)
);
alter table app.challenge_work_claims_v1 enable row level security;
revoke all on app.challenge_work_claims_v1 from public,anon,authenticated,service_role;
insert into app.challenge_work_claims_v1(challenge_id) select id from app.challenge_lobbies_v1;

create function app.challenge_seed_work_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
 insert into app.challenge_work_claims_v1(challenge_id) values(new.id);
 return new;
end $$;
create trigger challenge_seed_work after insert on app.challenge_lobbies_v1
for each row execute function app.challenge_seed_work_v1();

create function public.challenge_claim_batch_v1(p_run_id uuid,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare saved app.challenge_worker_runs_v1; item record; token uuid;
 payload jsonb := jsonb_build_object('version','challenge_claim_batch_v1','limit',p_limit);
 claims jsonb := '[]'; response jsonb; wall timestamptz;
begin
 perform app.duel_require_service_v1();
 if p_run_id is null or p_limit is null or p_limit not between 1 and 50 then
  raise exception 'challenge_invalid_batch' using errcode='22023';
 end if;
 perform app.challenge_gate_v1();
 perform app.challenge_lock_v1('worker_run',p_run_id);
 select * into saved from app.challenge_worker_runs_v1 where id=p_run_id;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.result;
 end if;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures) then
  raise exception 'challenge_fixture_disabled' using errcode='42501';
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 wall := clock_timestamp();
 if (select processing from app.challenge_runtime_v1 where singleton) then
  for item in
   with work as materialized (select * from app.challenge_work_v1() where due_at<=app.challenge_now_v1())
   select q.*,w.due_at from app.challenge_work_claims_v1 q join work w on w.id=q.challenge_id
   where (q.state in ('ready','retry') and q.next_attempt_at<=wall)
      or (q.state='claimed' and q.lease_expires_at<=wall)
   order by w.due_at,q.challenge_id limit p_limit
   for update of q skip locked
  loop
   -- An abandoned fifth attempt is dead-lettered rather than leased forever.
   if item.attempts>=5 then
    update app.challenge_work_claims_v1 set state='dead',lease_expires_at=null,
     last_error_code='57014',updated_at=wall where challenge_id=item.challenge_id;
    continue;
   end if;
   token := extensions.gen_random_uuid();
   update app.challenge_work_claims_v1 set state='claimed',claim_token=token,
    attempts=attempts+1,total_attempts=total_attempts+1,lease_expires_at=wall+interval '60 seconds',
    last_error_code=case when item.state='claimed' then '57014' else last_error_code end,
    updated_at=wall where challenge_id=item.challenge_id;
   claims := claims||jsonb_build_array(jsonb_build_object('id',item.challenge_id,'claim_token',token,
    'attempt',item.attempts+1,'lease_expires_at',wall+interval '60 seconds','due_at',item.due_at));
  end loop;
 end if;
 response := jsonb_build_object('run_id',p_run_id,'claims',claims,'server_time',app.challenge_now_v1());
 insert into app.challenge_worker_runs_v1 values(p_run_id,payload,response,app.challenge_now_v1());
 return response;
end $$;

create function public.challenge_complete_claim_v1(p_id uuid,p_claim_token uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare q app.challenge_work_claims_v1; saved app.challenge_worker_runs_v1;
 payload jsonb := jsonb_build_object('version','challenge_complete_claim_v1','id',p_id);
 response jsonb; outcome text; code text; wall timestamptz;
begin
 perform app.duel_require_service_v1();
 if p_id is null or p_claim_token is null then raise exception 'challenge_invalid_claim' using errcode='22023'; end if;
 perform app.challenge_gate_v1();
 -- Completion takes the challenge BEFORE its claim row. It never waits for a
 -- challenge while owning a claim row needed by another completion.
 perform app.challenge_lock_v1('challenge',p_id);
 select * into saved from app.challenge_worker_runs_v1 where id=p_claim_token;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.result;
 end if;
 select * into q from app.challenge_work_claims_v1 where challenge_id=p_id for update;
 wall := clock_timestamp();
 if q.state is distinct from 'claimed' or q.claim_token is distinct from p_claim_token or q.lease_expires_at<=wall then
  raise exception 'challenge_stale_claim' using errcode='55000';
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 -- This subtransaction rolls back ALL lifecycle effects if an item fails.
 -- Only a categorical SQLSTATE and bounded retry schedule are persisted.
 begin
  if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and processing) then
   outcome := 'paused';
  elsif exists(select 1 from app.challenge_work_item_v1(p_id) where due_at<=app.challenge_now_v1()) then
   outcome := app.challenge_tick_v1(p_id);
  else
   outcome := 'not_due';
  end if;
  response := jsonb_build_object('id',p_id,'claim_token',p_claim_token,'status',outcome);
 exception when others then
  code := sqlstate;
  response := jsonb_build_object('id',p_id,'claim_token',p_claim_token,'error_code',code);
 end;
 update app.challenge_work_claims_v1 set
  state=case when code is null then 'ready' when attempts>=5 then 'dead' else 'retry' end,
  attempts=case when code is null then 0 else attempts end,
  next_attempt_at=clock_timestamp()+case when code is null then interval '0 seconds'
   else least(300,power(2,attempts)::integer)*interval '1 second' end,
  lease_expires_at=null,last_error_code=code,updated_at=clock_timestamp()
 where challenge_id=p_id;
 insert into app.challenge_worker_runs_v1 values(p_claim_token,payload,response,app.challenge_now_v1());
 return response;
end $$;

-- Keep historical receipts readable, but fail closed for a new old-style run.
-- A SQL function cannot commit between items: callers must use claim + complete.
create or replace function public.challenge_run_batch_v1(p_run_id uuid,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare saved app.challenge_worker_runs_v1;
begin
 perform app.duel_require_service_v1();
 select * into saved from app.challenge_worker_runs_v1 where id=p_run_id;
 if found then
  if saved.payload is distinct from jsonb_build_object('version','challenge_batch_v1','limit',p_limit) then
   raise exception 'challenge_request_conflict' using errcode='22023';
  end if;
  return saved.result;
 end if;
 raise exception 'challenge_use_claim_batch' using errcode='0A000';
end $$;
drop function app.challenge_claim_work_v1(integer);

create or replace function public.challenge_operations_status_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare response jsonb;
begin
 perform app.duel_require_service_v1();
 with work as materialized (select * from app.challenge_work_v1())
 select jsonb_build_object('server_time',app.challenge_now_v1(),
  'gates',(select to_jsonb(r)-'actors'-'fictional_now' from app.challenge_runtime_v1 r where singleton),
  'due_count',count(*) filter(where due_at<=app.challenge_now_v1()),
  'notice_overdue_count',count(*) filter(where notice_overdue),
  'review_overdue_count',count(*) filter(where review_overdue),'oldest_due',min(due_at),
  'claimed_count',count(*) filter(where q.state='claimed'),
  'abandoned_count',count(*) filter(where q.state='claimed' and lease_expires_at<=clock_timestamp()),
  'retry_count',count(*) filter(where q.state='retry'),
  'dead_letter_count',count(*) filter(where q.state='dead'),
  'failed_work',(select coalesce(jsonb_agg(to_jsonb(f)),'[]') from
   (select c.challenge_id,c.state,c.attempts,c.next_attempt_at,c.lease_expires_at,c.last_error_code
    from app.challenge_work_claims_v1 c join work on work.id=c.challenge_id
    where c.state in ('retry','dead') or (c.state='claimed' and c.lease_expires_at<=clock_timestamp())
    order by c.updated_at,c.challenge_id limit 50) f),
  'recent_failures',(select coalesce(sum(coalesce((result->>'failed_count')::integer,0)+case when result ? 'error_code' then 1 else 0 end),0) from app.challenge_worker_runs_v1 where recorded_at>=app.challenge_now_v1()-interval '24 hours')
 ) into response from work w left join app.challenge_work_claims_v1 q on q.challenge_id=w.id;
 return response;
end $$;

revoke all on function app.challenge_mutation_session_v1(),app.challenge_work_item_v1(uuid),
 app.challenge_seed_work_v1(),public.challenge_claim_batch_v1(uuid,integer),public.challenge_complete_claim_v1(uuid,uuid)
from public,anon,authenticated,service_role;
grant execute on function public.challenge_claim_batch_v1(uuid,integer),public.challenge_complete_claim_v1(uuid,uuid) to service_role;
