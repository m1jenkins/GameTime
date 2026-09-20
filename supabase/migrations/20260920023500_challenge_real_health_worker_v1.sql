-- Keep legacy work inventory and its paused-backlog projection byte-compatible.
-- Claim selection below decides whether each source class may actually lease.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_claim_scoped_v1(jsonb,integer)'::regprocedure);
  if position('where due_at<=app.challenge_real_health_deadline_now_v1(id)' in definition) = 0 then
    raise exception 'Unexpected scoped real worker source';
  end if;
  definition := replace(definition, 'select * from app.challenge_work_v1()', 'select work.* from app.challenge_work_v1() work');
  definition := replace(definition,
    'where due_at<=app.challenge_real_health_deadline_now_v1(id)',
    'where due_at<=app.challenge_real_health_deadline_now_v1(work.id) and exists(select 1 from app.challenge_lobbies_v1 c left join app.challenge_runtime_v1 legacy on legacy.singleton left join app.challenge_real_health_runtime_v1 real on real.singleton where c.id=work.id and ((c.real_source_policy_version is null and legacy.fixtures and legacy.processing) or (c.real_source_policy_version is not null and real.processing_enabled)))');
  execute definition;
end $$;

-- Completion rechecks one row through the same source-aware inventory used by
-- dispatch; the historical parameterized helper still had its fixture clock.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_work_v1()'::regprocedure);
  if position('where c.status not in (''final'',''void'',''cancelled'')' in definition) = 0 then
    raise exception 'Unexpected source-aware work inventory';
  end if;
  definition := replace(definition, 'app.challenge_work_v1()', 'app.challenge_work_item_v1(p_id uuid)');
  definition := replace(definition,
    'where c.status not in (''final'',''void'',''cancelled'')',
    'where (p_id is null or c.id=p_id) and c.status not in (''final'',''void'',''cancelled'')');
  execute definition;
end $$;

-- Completion previously retained its fixture gate even though claims can now
-- be real-source claims.  Select the clock and runtime from the claimed row.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.challenge_complete_claim_v1(uuid,uuid)'::regprocedure);
  if position('if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and processing) then' in definition) = 0
     or position('elsif exists(select 1 from app.challenge_work_item_v1(p_id) where due_at<=app.challenge_now_v1()) then' in definition) = 0 then
    raise exception 'Unexpected worker completion source';
  end if;
  definition := replace(definition,
    'if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and processing) then',
    'if not exists(select 1 from app.challenge_runtime_v1 legacy join app.challenge_lobbies_v1 c on c.id=p_id where legacy.singleton and c.real_source_policy_version is null and legacy.fixtures and legacy.processing) and not exists(select 1 from app.challenge_real_health_runtime_v1 real join app.challenge_lobbies_v1 c on c.id=p_id where real.singleton and c.real_source_policy_version is not null and real.processing_enabled) then');
  definition := replace(definition,
    'elsif exists(select 1 from app.challenge_work_item_v1(p_id) where due_at<=app.challenge_now_v1()) then',
    'elsif exists(select 1 from app.challenge_work_item_v1(p_id) where due_at<=app.challenge_real_health_deadline_now_v1(p_id)) then');
  definition := replace(definition,
    'insert into app.challenge_worker_runs_v1 values(p_claim_token,payload,response,app.challenge_now_v1());',
    'insert into app.challenge_worker_runs_v1 values(p_claim_token,payload,response,app.challenge_real_health_deadline_now_v1(p_id));');
  execute definition;
end $$;

create or replace function app.challenge_worker_record_heartbeat_v1(
 p_invocation_id uuid,p_status text,p_claimed integer,p_error_code text default null)
returns void language plpgsql set search_path='' as $$
declare due integer; retries integer; dead integer; failed integer; code text:=p_error_code;
begin
 if p_status not in ('healthy_empty','healthy_backlog','paused','disabled','failed')
 or p_claimed not between 0 and 50 or code is not null and code !~ '^[0-9A-Z]{5}$' then raise exception 'challenge_invalid_heartbeat' using errcode='22023'; end if;
 select count(*) filter(where due_at<=app.challenge_real_health_deadline_now_v1(id)) into due from app.challenge_work_v1();
 select count(*) filter(where state='retry'),count(*) filter(where state='dead'),count(*) filter(where state in ('retry','dead') or (state='claimed' and lease_expires_at<=clock_timestamp())) into retries,dead,failed from app.challenge_work_claims_v1;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_worker_heartbeats_v1(invocation_id,status,claimed_count,due_count,retry_count,dead_letter_count,failed_count,error_code,recorded_at)
 values(p_invocation_id,p_status,p_claimed,coalesce(due,0),coalesce(retries,0),coalesce(dead,0),coalesce(failed,0),code,clock_timestamp());
end $$;

create or replace function public.challenge_dispatch_worker_invocation_v1(p_invocation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invocation app.challenge_worker_invocations_v1; claims jsonb; response jsonb; n timestamptz:=clock_timestamp(); code text; status text; legacy app.challenge_runtime_v1; real app.challenge_real_health_runtime_v1; principal text:=app.challenge_worker_principal_v1(); enabled boolean;
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null then raise exception 'challenge_invalid_batch' using errcode='22023'; end if;
 perform app.challenge_gate_v1(); perform app.challenge_lock_v1('worker_invocation',p_invocation_id);
 select * into invocation from app.challenge_worker_invocations_v1 where id=p_invocation_id for update;
 if not found then raise exception 'challenge_invocation_required' using errcode='55000'; end if;
 if invocation.state<>'prepared' then return invocation.claim_response; end if;
 select * into legacy from app.challenge_runtime_v1 where singleton;
 select * into real from app.challenge_real_health_runtime_v1 where singleton;
 enabled:=coalesce(legacy.fixtures,false) or coalesce(real.processing_enabled,false);
 begin
  if not enabled then code:='42501'; status:='disabled'; raise exception 'challenge_processing_paused' using errcode='42501'; end if;
  claims:=app.challenge_claim_scoped_v1(invocation.scope,invocation.limit_count);
  status:=case when jsonb_array_length(claims)>0 then 'dispatched' when legacy.fixtures and not legacy.processing and not real.processing_enabled then 'paused' else 'healthy_empty' end;
  response:=jsonb_build_object('invocation_id',p_invocation_id,'status',status,'claims',claims,'server_time',clock_timestamp());
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_worker_invocations_v1 set state='dispatched',claim_response=response,dispatch_attempts=dispatch_attempts+1,dispatched_at=n,updated_at=n where id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,principal,status_code,recorded_at) values('dispatch',p_invocation_id,p_invocation_id,principal,'00000',n);
  perform app.challenge_worker_record_heartbeat_v1(p_invocation_id,case when status='paused' then 'paused' when status='healthy_empty' then 'healthy_empty' else 'healthy_backlog' end,jsonb_array_length(claims));
 exception when others then
  if code is null then code:=sqlstate; end if;
  if status is null then status:=case when not enabled then 'disabled' else 'failed' end; end if;
  response:=jsonb_build_object('invocation_id',p_invocation_id,'status',status,'error_code',code);
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_worker_invocations_v1 set state='failed',claim_response=response,dispatch_attempts=dispatch_attempts+1,last_error_code=code,dispatched_at=n,updated_at=n where id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,principal,status_code,recorded_at) values('dispatch',p_invocation_id,p_invocation_id,principal,code,n);
  perform app.challenge_worker_record_heartbeat_v1(p_invocation_id,status,0,code);
 end;
 return response;
end $$;

-- A real community projection uses its source clock and real processing gate;
-- the legacy projection remains fixture/discovery controlled.
create or replace function public.challenge_community_snapshot_status_v1(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare legacy app.challenge_runtime_v1; real app.challenge_real_health_runtime_v1; source text; wall timestamptz:=statement_timestamp(); reference_at timestamptz; capture_at timestamptz; prepared_at timestamptz; attempted_at timestamptz; succeeded_at timestamptz; attempt_state text; error_code text; published boolean;
begin
 perform app.duel_require_service_v1(); if p_id is null then raise exception 'challenge_snapshot_selection_required' using errcode='22023'; end if;
 select * into legacy from app.challenge_runtime_v1 where singleton; select * into real from app.challenge_real_health_runtime_v1 where singleton;
 select real_source_policy_version into source from app.challenge_lobbies_v1 where id=p_id;
 reference_at:=case when legacy.singleton is null then null when source is null then coalesce(legacy.fictional_now,wall) else app.challenge_real_health_now_v1() end;
 select exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) into published;
 if published then select max(captured_at) into capture_at from app.challenge_community_snapshots_v1 where challenge_id=p_id; select max(i.prepared_at),max(i.dispatched_at) filter(where i.state='dispatched') into prepared_at,succeeded_at from app.challenge_snapshot_invocations_v1 i where i.challenge_id=p_id; select i.dispatched_at,i.state,i.last_error_code into attempted_at,attempt_state,error_code from app.challenge_snapshot_invocations_v1 i where i.challenge_id=p_id and i.dispatched_at is not null order by i.dispatched_at desc,i.id desc limit 1; end if;
 return jsonb_build_object('observed_wall_at',wall,'reference_clock',case when legacy.singleton is null then 'unavailable' when source is null and legacy.fictional_now is not null then 'fixture' else 'wall' end,'snapshot_reference_at',reference_at,'capture_state',case when not published then 'cohort_unavailable' when legacy.singleton is null then 'runtime_unavailable' when source is null and not legacy.fixtures then 'fixtures_disabled' when source is null and not legacy.discovery then 'discovery_disabled' when source is not null and not real.processing_enabled then 'fixtures_disabled' else 'enabled' end,'snapshot_state',case when not published then 'unavailable' when reference_at is null then 'clock_unavailable' when capture_at is null then 'missing' when capture_at>reference_at then 'clock_ahead' else 'recorded' end,'last_capture_at',capture_at,'capture_age_seconds',case when capture_at<=reference_at then floor(extract(epoch from reference_at-capture_at)) end,'last_prepared_wall_at',prepared_at,'last_attempt_wall_at',attempted_at,'last_attempt_state',case when attempt_state='dispatched' then 'checked' when attempt_state='failed' then 'failed' else 'none' end,'last_attempt_error_code',case when error_code ~ '^[0-9A-Z]{5}$' then error_code end,'last_successful_invocation_wall_at',succeeded_at);
end $$;

create or replace function app.challenge_community_counts_v1(c uuid) returns jsonb
language plpgsql set search_path='' as $$
declare s app.challenge_community_snapshots_v1; live integer; n timestamptz; source text;
begin
 select real_source_policy_version into source from app.challenge_lobbies_v1 where id=c;
 n:=case when source is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end;
 select count(*) into live from app.challenge_members_v1 m where m.challenge_id=c and m.selected and m.exited_at is null and not app.challenge_actor_unavailable_v1(m.actor_id);
 if live<5 then return '{"joined":null,"state":"threshold","as_of":null}'; end if;
 select * into s from app.challenge_community_snapshots_v1 where challenge_id=c and captured_at<=n-interval '15 minutes' order by captured_at desc limit 1;
 if s.joined is null then return '{"joined":null,"state":"pending","as_of":null}'; end if;
 return jsonb_build_object('joined',s.joined,'state','available','as_of',s.captured_at);
end $$;

create or replace function public.challenge_capture_community_snapshot_v1(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare n timestamptz; joined integer; source text;
begin
 perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1('challenge',p_id);
 select real_source_policy_version into source from app.challenge_lobbies_v1 where id=p_id;
 if source is null then
  if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and discovery) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
  n:=app.challenge_now_v1();
 else
  if not exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and processing_enabled) then raise exception 'challenge_processing_paused' using errcode='42501'; end if;
  n:=app.challenge_real_health_now_v1();
 end if;
 if not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 if exists(select 1 from app.challenge_community_snapshots_v1 where challenge_id=p_id and captured_at>n-interval '15 minutes') then return; end if;
 select count(*) into joined from app.challenge_members_v1 m where m.challenge_id=p_id and m.selected and m.exited_at is null and not app.challenge_actor_unavailable_v1(m.actor_id);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_community_snapshots_v1 values(p_id,n,case when joined>=5 then joined end);
end $$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.challenge_local_worker_status_v1()'::regprocedure);
  if position('select count(*) filter(where due_at<=app.challenge_now_v1()) into due' in definition) = 0
     or position('when not runtime.fixtures then ''disabled'' when not runtime.processing then ''paused''' in definition) = 0 then
    raise exception 'Unexpected local worker status source';
  end if;
  definition := replace(definition, 'runtime record; due integer;', 'runtime record; real record; due integer;');
  definition := replace(definition, 'select * into runtime from app.challenge_runtime_v1 where singleton;', 'select * into runtime from app.challenge_runtime_v1 where singleton; select * into real from app.challenge_real_health_runtime_v1 where singleton;');
  definition := replace(definition, 'select count(*) filter(where due_at<=app.challenge_now_v1()) into due', 'select count(*) filter(where due_at<=app.challenge_real_health_deadline_now_v1(id)) into due');
  definition := replace(definition, 'when not runtime.fixtures then ''disabled'' when not runtime.processing then ''paused''', 'when not runtime.fixtures and not coalesce(real.processing_enabled,false) then ''disabled'' when not runtime.processing and not coalesce(real.processing_enabled,false) then ''paused''');
  definition := replace(definition,
    $replace$'processing_paused',not runtime.processing,$replace$,
    $replace$'processing_paused',not runtime.processing and not coalesce(real.processing_enabled,false),$replace$);
  execute definition;
end $$;
