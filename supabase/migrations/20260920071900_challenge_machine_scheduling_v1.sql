-- Local P11 Cron -> Edge boundary. No secrets, selected cohort or activation.
-- Applied with the migration transaction: no observer can see an active new job.
-- Historical lifecycle RPCs and receipts remain the authority for each item.

create table app.challenge_schedule_config_v1 (
 singleton boolean primary key default true check(singleton),
 worker_enabled boolean not null default false,
 snapshot_enabled boolean not null default false,
 monitor_enabled boolean not null default false,
 edge_base_url text check(edge_base_url is null or
   edge_base_url ~ '^https://[a-zA-Z0-9.-]+(:[0-9]{1,5})?/functions/v1$' or
   edge_base_url ~ '^http://(127[.]0[.]0[.]1|host[.]docker[.]internal):[0-9]{1,5}/functions/v1$'),
 worker_secret_id uuid,
 monitor_secret_id uuid,
 community_id uuid references app.challenge_lobbies_v1(id),
 check(worker_secret_id is null or monitor_secret_id is null or worker_secret_id<>monitor_secret_id)
);
insert into app.challenge_schedule_config_v1(singleton) values(true);

create table app.challenge_schedule_ticks_v1 (
 kind text primary key check(kind in ('worker','snapshot','monitor')),
 last_queued_at timestamptz,
 last_request_id bigint,
 -- Diagnostic only: pg_net's unlogged queue/response is never replay authority.
 queued_count bigint not null default 0 check(queued_count>=0)
);
insert into app.challenge_schedule_ticks_v1(kind) values('worker'),('snapshot'),('monitor');

create table app.challenge_machine_runs_v1 (
 invocation_id uuid primary key,
 kind text not null check(kind in ('worker','snapshot')),
 state text not null default 'pending' check(state in ('pending','running','finished')),
 run_token uuid,
 lease_expires_at timestamptz,
 prepared_at timestamptz not null default clock_timestamp(),
 last_queued_at timestamptz,
 queue_attempts integer not null default 0 check(queue_attempts>=0),
 finished_at timestamptz,
 result jsonb,
 check((state='running')=(run_token is not null and lease_expires_at is not null)),
 check((state='finished')=(result is not null and finished_at is not null))
);
create unique index challenge_machine_unfinished_v1 on app.challenge_machine_runs_v1(kind)
 where state<>'finished';

do $$ declare relation text; begin
 foreach relation in array array['challenge_schedule_config_v1','challenge_schedule_ticks_v1','challenge_machine_runs_v1'] loop
  execute format('alter table app.%I enable row level security',relation);
  execute format('revoke all on app.%I from public,anon,authenticated,service_role',relation);
 end loop;
end $$;

-- Only the private administrator configures destinations/secret references. The
-- bridge appends a fixed endpoint, never a caller-supplied RPC, URL or cohort.
create function app.challenge_schedule_state_v1(p_kind text) returns text
language plpgsql stable set search_path='' as $$
declare config app.challenge_schedule_config_v1; worker_secret text; monitor_secret text;
begin
 if p_kind not in ('worker','snapshot','monitor') or p_kind is null then return 'unavailable'; end if;
 select * into config from app.challenge_schedule_config_v1 where singleton;
 if not found or config.edge_base_url is null or config.worker_secret_id is null or config.monitor_secret_id is null
  or (p_kind='snapshot' and config.community_id is null) then return 'unconfigured'; end if;
 select decrypted_secret into worker_secret from vault.decrypted_secrets where id=config.worker_secret_id;
 select decrypted_secret into monitor_secret from vault.decrypted_secrets where id=config.monitor_secret_id;
 if coalesce(length(worker_secret),0) not between 32 and 256 or coalesce(length(monitor_secret),0) not between 32 and 256
  or worker_secret=monitor_secret then return 'unconfigured'; end if;
 if not (case p_kind when 'worker' then config.worker_enabled when 'snapshot' then config.snapshot_enabled else config.monitor_enabled end) then
  return 'disabled';
 end if;
 return 'available';
end $$;

-- Distinguish a real processing pause from an empty queue or missing runtime.
-- The historical projection retains its own vocabulary and receipt meanings.
create function app.challenge_machine_processing_state_v1() returns text
language plpgsql stable set search_path='' as $$
declare legacy app.challenge_runtime_v1; real app.challenge_real_health_runtime_v1;
begin
 select * into legacy from app.challenge_runtime_v1 where singleton;
 select * into real from app.challenge_real_health_runtime_v1 where singleton;
 if legacy.singleton is null or real.singleton is null then return 'unavailable'; end if;
 if real.processing_enabled or (legacy.fixtures and legacy.processing) then return 'available'; end if;
 if legacy.fixtures or real.admission_enabled or real.ingestion_enabled
  or exists(select 1 from app.challenge_lobbies_v1 where real_source_policy_version is not null and status not in ('final','void','cancelled')) then
  return 'paused';
 end if;
 return 'disabled';
end $$;

create function app.challenge_machine_worker_result_v1(p_invocation_id uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare batch jsonb; total integer; completed integer; failed integer; paused integer; state text;
begin
 select claim_response into batch from app.challenge_worker_invocations_v1 where id=p_invocation_id;
 select count(*),count(receipt.id),count(*) filter(where receipt.result ? 'error_code'),
   count(*) filter(where receipt.result->>'status'='paused')
 into total,completed,failed,paused
 from jsonb_array_elements(coalesce(batch->'claims','[]')) claim
 left join app.challenge_worker_runs_v1 receipt on receipt.id=(claim->>'claim_token')::uuid;
 state:=case when batch is null then 'unavailable'
  when batch->>'status' in ('failed','disabled','paused') then batch->>'status'
  when completed<total then 'pending' when failed>0 then 'failed' when paused>0 then 'paused'
  when total=0 then 'empty' else 'completed' end;
 return jsonb_build_object('status',state,'completed_count',completed,'failed_count',failed,
   'pending_count',total-completed,'server_time',statement_timestamp());
end $$;

create function app.challenge_cron_tick_v1(p_kind text) returns void
language plpgsql security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare config app.challenge_schedule_config_v1; tick app.challenge_schedule_ticks_v1;
 run app.challenge_machine_runs_v1; prior_snapshot_run app.challenge_machine_runs_v1;
 invocation uuid; body jsonb:='{}'; dispatch_secret text;
 request_id bigint; n timestamptz; summary jsonb; batch jsonb; prepared_cohort uuid;
begin
 -- Serialize only preparation/queueing, never lifecycle completion. Each tick
 -- is a short transaction; Edge's independent RPCs commit one item at a time.
 select * into config from app.challenge_schedule_config_v1 where singleton for update;
 if app.challenge_schedule_state_v1(p_kind)<>'available' then return; end if;
 select * into tick from app.challenge_schedule_ticks_v1 where kind=p_kind for update;
 n:=clock_timestamp();
 if tick.last_queued_at>n-(case when p_kind='snapshot' then interval '900 seconds' else interval '60 seconds' end) then return; end if;
 if p_kind in ('worker','snapshot') then
  select * into run from app.challenge_machine_runs_v1 where kind=p_kind and state<>'finished' for update;
  n:=clock_timestamp();
  if found and run.state='running' and run.lease_expires_at>n then return; end if;
  if run.invocation_id is not null and p_kind='worker' then
   summary:=app.challenge_machine_worker_result_v1(run.invocation_id);
   select claim_response into batch from app.challenge_worker_invocations_v1 where id=run.invocation_id;
   if summary->>'status' not in ('pending','unavailable') or exists(
     select 1 from jsonb_array_elements(coalesce(batch->'claims','[]')) claim
     where (claim->>'lease_expires_at')::timestamptz<=n
   ) then
    -- Never extend item leases or lease with an old invocation. A fresh one
    -- reclaims expired items through the original bounded retry/dead-letter RPC.
    if summary->>'status'='pending' then summary:=summary||'{"status":"failed","error_category":"lease_expired"}'::jsonb; end if;
    update app.challenge_machine_runs_v1 set state='finished',run_token=null,lease_expires_at=null,
      finished_at=n,result=summary where invocation_id=run.invocation_id;
    run:=null;
   end if;
  end if;
  if run.invocation_id is not null and p_kind='snapshot' then
   select challenge_id into prepared_cohort from app.challenge_snapshot_invocations_v1
    where id=run.invocation_id;
   if prepared_cohort is distinct from config.community_id then
    -- A config switch must not strand the one unfinished snapshot slot. The
    -- old invocation remains durable but is never sent to the new cohort.
    update app.challenge_machine_runs_v1 set state='finished',run_token=null,lease_expires_at=null,
      finished_at=n,result='{"status":"unavailable","error_category":"selection_changed"}'::jsonb
      where invocation_id=run.invocation_id;
    run:=null;
   end if;
  end if;
  if run.invocation_id is null then
   invocation:=extensions.gen_random_uuid();
   if p_kind='worker' then
    perform public.challenge_prepare_worker_invocation_v1(invocation,'{"version":"challenge_worker_scope_v1","kind":"due"}',20);
   else
    if not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=config.community_id) then return; end if;
    -- Recover an already prepared selected-cohort snapshot (including a local
    -- operator's preparation); do not compete with its unique prepared scope.
    select id into invocation from app.challenge_snapshot_invocations_v1 where challenge_id=config.community_id and state='prepared';
    invocation:=coalesce(invocation,extensions.gen_random_uuid());
    perform public.challenge_prepare_community_snapshot_invocation_v1(invocation,config.community_id);
   end if;
   if p_kind='snapshot' then
    select * into prior_snapshot_run from app.challenge_machine_runs_v1 where invocation_id=invocation for update;
    if found then
     if prior_snapshot_run.kind<>'snapshot' or prior_snapshot_run.state<>'finished'
       or prior_snapshot_run.result->>'error_category' is distinct from 'selection_changed' then
      raise exception 'challenge_snapshot_machine_conflict' using errcode='55000';
     end if;
     -- Switching back reuses the exact prepared journal and invocation ID.
     -- Only a cohort-switch retirement is reversible; checked/failed results
     -- and their saved responses remain terminal.
     update app.challenge_machine_runs_v1 set state='pending',finished_at=null,result=null,
       run_token=null,lease_expires_at=null where invocation_id=invocation;
    else
     insert into app.challenge_machine_runs_v1(invocation_id,kind) values(invocation,p_kind);
    end if;
   else
    insert into app.challenge_machine_runs_v1(invocation_id,kind) values(invocation,p_kind);
   end if;
  else
   invocation:=run.invocation_id;
  end if;
  body:=jsonb_build_object('invocation_id',invocation);
 end if;
 select decrypted_secret into dispatch_secret from vault.decrypted_secrets
 where id=case when p_kind='monitor' then config.monitor_secret_id else config.worker_secret_id end;
 -- pg_net only sends after commit. Durable preparation and exact parameters
 -- above are visible before any HTTP can run, even if its queue is later lost.
 request_id:=net.http_post(url:=config.edge_base_url||'/challenge-'||p_kind,
  headers:=jsonb_build_object('Content-Type','application/json',
   case when p_kind='monitor' then 'x-gametime-monitor-secret' else 'x-gametime-worker-secret' end,dispatch_secret),
  body:=body,timeout_milliseconds:=55000);
 update app.challenge_schedule_ticks_v1 set last_queued_at=n,last_request_id=request_id,queued_count=queued_count+1 where kind=p_kind;
 if invocation is not null then
  update app.challenge_machine_runs_v1 set last_queued_at=n,queue_attempts=queue_attempts+1 where invocation_id=invocation;
 end if;
end $$;

create function public.challenge_machine_worker_dispatch_v1(p_invocation_id uuid,p_run_token uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare run app.challenge_machine_runs_v1; batch jsonb; state text; n timestamptz;
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null or p_run_token is null then raise exception 'challenge_invalid_invocation' using errcode='22023'; end if;
 select * into run from app.challenge_machine_runs_v1 where invocation_id=p_invocation_id and kind='worker' for update;
 if not found then return jsonb_build_object('status','unavailable'); end if;
 if run.state='finished' then return jsonb_build_object('status','completed','result',run.result); end if;
 state:=app.challenge_schedule_state_v1('worker');
 if state<>'available' then return jsonb_build_object('status',state); end if;
 state:=app.challenge_machine_processing_state_v1();
 if state<>'available' then return jsonb_build_object('status',state); end if;
 n:=clock_timestamp();
 if run.state='running' and run.lease_expires_at>n and run.run_token<>p_run_token then return '{"status":"busy"}'; end if;
 if run.state='running' and run.run_token=p_run_token and run.lease_expires_at<=n then return '{"status":"failed","error_category":"lease_expired"}'; end if;
 if run.state<>'running' or run.run_token<>p_run_token then
  update app.challenge_machine_runs_v1 set state='running',run_token=p_run_token,lease_expires_at=n+interval '60 seconds' where invocation_id=p_invocation_id;
 end if;
 -- Replays return the original claim response, even after a process restart.
 batch:=public.challenge_dispatch_worker_invocation_v1(p_invocation_id);
 return jsonb_build_object('status','running','run_token',p_run_token,'claims',coalesce(batch->'claims','[]'),
   'server_time',clock_timestamp());
end $$;

create function public.challenge_machine_complete_v1(p_invocation_id uuid,p_run_token uuid,p_id uuid,p_claim_token uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare run app.challenge_machine_runs_v1; batch jsonb;
begin
 perform app.duel_require_service_v1();
 -- Shared row locks allow five completions concurrently. Lease takeover and
 -- finish require UPDATE locks and must wait for every admitted completion.
 select * into run from app.challenge_machine_runs_v1 where invocation_id=p_invocation_id and kind='worker' for share;
 if not found or run.state<>'running' or run.run_token is distinct from p_run_token or run.lease_expires_at<=clock_timestamp() then
  raise exception 'challenge_stale_machine_run' using errcode='55000';
 end if;
 select claim_response into batch from app.challenge_worker_invocations_v1 where id=p_invocation_id;
 if not exists(select 1 from jsonb_array_elements(coalesce(batch->'claims','[]')) claim
   where claim->>'id'=p_id::text and claim->>'claim_token'=p_claim_token::text) then
  raise exception 'challenge_unselected_claim' using errcode='42501';
 end if;
 if app.challenge_schedule_state_v1('worker')<>'available' then return '{"status":"disabled"}'; end if;
 return public.challenge_complete_claim_v1(p_id,p_claim_token);
end $$;

create function public.challenge_machine_finish_v1(p_invocation_id uuid,p_run_token uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare run app.challenge_machine_runs_v1; summary jsonb;
begin
 perform app.duel_require_service_v1();
 select * into run from app.challenge_machine_runs_v1 where invocation_id=p_invocation_id and kind='worker' for update;
 if not found then return '{"status":"unavailable"}'; end if;
 if run.state='finished' then return run.result; end if;
 if run.state<>'running' or run.run_token is distinct from p_run_token or run.lease_expires_at<=clock_timestamp() then
  raise exception 'challenge_stale_machine_run' using errcode='55000';
 end if;
 summary:=app.challenge_machine_worker_result_v1(p_invocation_id);
 if summary->>'status'<>'pending' then
  update app.challenge_machine_runs_v1 set state='finished',run_token=null,lease_expires_at=null,
   finished_at=clock_timestamp(),result=summary where invocation_id=p_invocation_id;
 end if;
 return summary;
end $$;

create function public.challenge_machine_snapshot_dispatch_v1(p_invocation_id uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare run app.challenge_machine_runs_v1; config app.challenge_schedule_config_v1;
 state text; response jsonb; snapshot jsonb; cohort uuid;
begin
 perform app.duel_require_service_v1();
 select * into config from app.challenge_schedule_config_v1 where singleton for share;
 select * into run from app.challenge_machine_runs_v1 where invocation_id=p_invocation_id and kind='snapshot' for update;
 if not found then return '{"status":"unavailable"}'; end if;
 -- Recheck the configured cohort before even returning a saved snapshot result.
 select challenge_id into cohort from app.challenge_snapshot_invocations_v1 where id=p_invocation_id;
 if cohort is distinct from config.community_id then return '{"status":"unavailable"}'; end if;
 if run.state='finished' then return run.result; end if;
 state:=app.challenge_schedule_state_v1('snapshot');
 if state<>'available' then return jsonb_build_object('status',state); end if;
 if app.challenge_machine_processing_state_v1()='unavailable' then return '{"status":"unavailable"}'; end if;
 response:=public.challenge_dispatch_community_snapshot_invocation_v1(p_invocation_id);
 snapshot:=public.challenge_community_snapshot_status_v1(cohort);
 -- "checked" means invocation success, never a promise of a new capture.
 response:=jsonb_build_object('status',case response->>'status' when 'checked' then 'checked' when 'disabled' then 'paused' else 'failed' end,
  'last_capture_at',snapshot->'last_capture_at','capture_age_seconds',snapshot->'capture_age_seconds',
  'last_successful_invocation_wall_at',snapshot->'last_successful_invocation_wall_at','server_time',clock_timestamp());
 update app.challenge_machine_runs_v1 set state='finished',finished_at=clock_timestamp(),result=response where invocation_id=p_invocation_id;
 return response;
end $$;

create function public.challenge_machine_monitor_v1() returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='5s' set lock_timeout='4s' as $$
declare state text; processing text; worker_schedule text; worker jsonb:='{}'; reviews jsonb:='{}'; snapshot jsonb:='{}';
 config app.challenge_schedule_config_v1;
begin
 perform app.duel_require_service_v1();
 select * into config from app.challenge_schedule_config_v1 where singleton;
 state:=app.challenge_schedule_state_v1('monitor');
 if state='available' then
  state:=case
   when not exists(select 1 from cron.job where jobname='challenge-monitor-v1') then 'unavailable'
   when current_setting('cron.launch_active_jobs',true) is distinct from 'on'
     or not exists(select 1 from cron.job where jobname='challenge-monitor-v1' and active) then 'disabled'
   else 'available' end;
 end if;
 processing:=app.challenge_machine_processing_state_v1();
 worker_schedule:=app.challenge_schedule_state_v1('worker');
 if worker_schedule='available' then
  worker_schedule:=case
   when not exists(select 1 from cron.job where jobname='challenge-worker-v1') then 'unavailable'
   when current_setting('cron.launch_active_jobs',true) is distinct from 'on'
     or not exists(select 1 from cron.job where jobname='challenge-worker-v1' and active) then 'disabled'
   else 'available' end;
 end if;
 if processing<>'unavailable' then
  worker:=public.challenge_local_worker_status_v1();
  reviews:=public.challenge_local_review_status_v1();
  worker:=worker||jsonb_build_object('processing_state',case when worker_schedule<>'available' then worker_schedule when processing<>'available' then processing
   when (worker->>'failed_count')::integer>0 then 'failed' when (worker->>'due_count')::integer=0 then 'empty' else 'available' end,
   'processing_paused',processing='paused');
  reviews:=reviews||jsonb_build_object('monitoring_state',case when processing='available' then 'available' else processing end);
 else
  worker:='{"processing_state":"unavailable"}'; reviews:='{"monitoring_state":"unavailable"}';
 end if;
 if config.community_id is null then snapshot:='{"capture_state":"unconfigured","snapshot_state":"unavailable"}';
 elsif processing='unavailable' then snapshot:='{"capture_state":"unavailable","snapshot_state":"unavailable"}';
 else
  snapshot:=public.challenge_community_snapshot_status_v1(config.community_id);
  snapshot:=snapshot||jsonb_build_object('capture_state',case
   when snapshot->>'capture_state'='cohort_unavailable' then 'unavailable'
   when app.challenge_schedule_state_v1('snapshot')<>'available' then app.challenge_schedule_state_v1('snapshot')
   when not exists(select 1 from cron.job where jobname='challenge-snapshot-v1') then 'unavailable'
   when current_setting('cron.launch_active_jobs',true) is distinct from 'on'
     or not exists(select 1 from cron.job where jobname='challenge-snapshot-v1' and active) then 'disabled'
   when snapshot->>'capture_state'='enabled' then 'enabled'
   when snapshot->>'capture_state'='fixtures_disabled' and exists(select 1 from app.challenge_lobbies_v1 where id=config.community_id and real_source_policy_version is not null) then 'paused'
   when snapshot->>'capture_state' in ('fixtures_disabled','discovery_disabled') then 'disabled' else 'unavailable' end);
 end if;
 if state='available' then
  state:=case when worker_schedule<>'available' then worker_schedule when processing<>'available' then processing when worker->>'processing_state'='failed' then 'failed'
   when worker->>'processing_state'='empty' then 'empty' else 'available' end;
 end if;
 -- Explicit key projection. Adding a field to a reused RPC cannot disclose it.
 select coalesce(jsonb_object_agg(key,value),'{}') into worker from jsonb_each(worker) where key=any(array[
  'processing_state','admission_paused','processing_paused','due_count','retry_count','dead_letter_count','abandoned_count','failed_count',
  'heartbeat_status','last_heartbeat_at','heartbeat_age_seconds','recent_failure_count']);
 select coalesce(jsonb_object_agg(key,value),'{}') into reviews from jsonb_each(reviews) where key=any(array[
  'monitoring_state','outstanding_review_count','reviews_without_eligible_operator_count','earliest_review_resolve_by',
  'next_review_grant_expires_at','pending_appeal_count','appeals_without_eligible_operator_count','oldest_pending_appeal_at','next_appeal_grant_expires_at']);
 select coalesce(jsonb_object_agg(key,value),'{}') into snapshot from jsonb_each(snapshot) where key=any(array[
  'capture_state','snapshot_state','last_capture_at','capture_age_seconds','last_prepared_wall_at','last_attempt_wall_at',
  'last_attempt_state','last_successful_invocation_wall_at']);
 return jsonb_build_object('state',state,'observed_at',statement_timestamp(),'worker',worker,'reviews',reviews,'snapshot',snapshot);
end $$;

revoke all on function app.challenge_schedule_state_v1(text),app.challenge_machine_processing_state_v1(),
 app.challenge_machine_worker_result_v1(uuid),app.challenge_cron_tick_v1(text),
 public.challenge_machine_worker_dispatch_v1(uuid,uuid),public.challenge_machine_complete_v1(uuid,uuid,uuid,uuid),
 public.challenge_machine_finish_v1(uuid,uuid),public.challenge_machine_snapshot_dispatch_v1(uuid),public.challenge_machine_monitor_v1()
 from public,anon,authenticated,service_role;
grant execute on function public.challenge_machine_worker_dispatch_v1(uuid,uuid),
 public.challenge_machine_complete_v1(uuid,uuid,uuid,uuid),public.challenge_machine_finish_v1(uuid,uuid),
 public.challenge_machine_snapshot_dispatch_v1(uuid),public.challenge_machine_monitor_v1() to service_role;

-- Versioned implementation defaults only. Credentials/configuration and hosted
-- operating acceptance remain separate; no product admission switch changes.
do $$ declare job bigint; begin
 job:=cron.schedule('challenge-worker-v1','* * * * *',$cron$set statement_timeout='5s'; select app.challenge_cron_tick_v1('worker')$cron$);
 perform cron.alter_job(job,active:=false);
 job:=cron.schedule('challenge-snapshot-v1','*/15 * * * *',$cron$set statement_timeout='5s'; select app.challenge_cron_tick_v1('snapshot')$cron$);
 perform cron.alter_job(job,active:=false);
 job:=cron.schedule('challenge-monitor-v1','* * * * *',$cron$set statement_timeout='5s'; select app.challenge_cron_tick_v1('monitor')$cron$);
 perform cron.alter_job(job,active:=false);
end $$;
