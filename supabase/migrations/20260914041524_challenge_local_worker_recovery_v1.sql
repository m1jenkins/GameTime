-- P11A: local-only worker invocation journals, bounded recovery, delayed
-- snapshot dispatch and sanitized operational health. This does not register a
-- scheduler, add credentials, or enable a real-source runtime.

create table app.challenge_worker_invocations_v1 (
 id uuid primary key,
 scope jsonb not null check(jsonb_typeof(scope)='object' and octet_length(scope::text)<=4096),
 scope_digest text not null check(scope_digest ~ '^[0-9a-f]{64}$'),
 limit_count integer not null check(limit_count between 1 and 50),
 state text not null check(state in ('prepared','dispatched','failed')),
 claim_response jsonb,
 dispatch_attempts integer not null default 0 check(dispatch_attempts between 0 and 3),
 last_error_code text check(last_error_code is null or last_error_code ~ '^[0-9A-Z]{5}$'),
 prepared_at timestamptz not null,
 dispatched_at timestamptz,
 updated_at timestamptz not null,
 check((state='prepared')=(claim_response is null)),
 check(state<>'dispatched' or claim_response is not null),
 check(state<>'failed' or claim_response is not null)
);
create index challenge_worker_invocations_updated_v1
 on app.challenge_worker_invocations_v1(updated_at desc);

create table app.challenge_snapshot_invocations_v1 (
 id uuid primary key,
 challenge_id uuid not null references app.challenge_lobbies_v1(id),
 state text not null check(state in ('prepared','dispatched','failed')),
 response jsonb,
 dispatch_attempts integer not null default 0 check(dispatch_attempts between 0 and 3),
 last_error_code text check(last_error_code is null or last_error_code ~ '^[0-9A-Z]{5}$'),
 prepared_at timestamptz not null,
 dispatched_at timestamptz,
 updated_at timestamptz not null,
 check((state='prepared')=(response is null)),
 check(state<>'prepared' or response is null),
 check(state<>'dispatched' or response is not null),
 check(state<>'failed' or response is not null)
);
create unique index challenge_snapshot_invocations_scope_v1
 on app.challenge_snapshot_invocations_v1(challenge_id)
 where state='prepared';

create table app.challenge_worker_recoveries_v1 (
 request_id uuid primary key,
 challenge_id uuid not null references app.challenge_lobbies_v1(id),
 previous_state text not null check(previous_state='dead'),
 previous_attempts integer not null check(previous_attempts between 0 and 5),
 previous_total_attempts bigint not null check(previous_total_attempts>=previous_attempts),
 previous_error_code text check(previous_error_code is null or previous_error_code ~ '^[0-9A-Z]{5}$'),
 response jsonb not null,
 authorized_principal text not null check(authorized_principal in ('service_role','postgres')),
 recorded_at timestamptz not null
);

create table app.challenge_worker_audit_v1 (
 id bigint generated always as identity primary key,
 operation text not null check(operation in ('prepare','dispatch','recover','snapshot_prepare','snapshot_dispatch')),
 request_id uuid not null,
 invocation_id uuid,
 challenge_id uuid,
 principal text not null check(principal in ('service_role','postgres')),
 status_code text not null check(status_code ~ '^[0-9A-Z]{5}$'),
 recorded_at timestamptz not null
);
create index challenge_worker_audit_recorded_v1
 on app.challenge_worker_audit_v1(recorded_at desc);

create table app.challenge_worker_heartbeats_v1 (
 id bigint generated always as identity primary key,
 invocation_id uuid,
 status text not null check(status in ('healthy_empty','healthy_backlog','paused','disabled','failed')),
 claimed_count integer not null check(claimed_count between 0 and 50),
 due_count integer not null check(due_count>=0),
 retry_count integer not null check(retry_count>=0),
 dead_letter_count integer not null check(dead_letter_count>=0),
 failed_count integer not null check(failed_count>=0),
 error_code text check(error_code is null or error_code ~ '^[0-9A-Z]{5}$'),
 recorded_at timestamptz not null
);
create index challenge_worker_heartbeats_recorded_v1
 on app.challenge_worker_heartbeats_v1(recorded_at desc);

do $$ declare t text; begin
 foreach t in array array[
  'worker_invocations','snapshot_invocations','worker_recoveries',
  'worker_audit','worker_heartbeats'
 ] loop
  execute format('alter table app.challenge_%s_v1 enable row level security',t);
  execute format('revoke all on app.challenge_%s_v1 from public,anon,authenticated,service_role',t);
 end loop;
end $$;

create function app.challenge_worker_state_guard_v1() returns trigger
language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
 or coalesce(current_setting('app.challenge_write_v1',true),'')<>'on' then
  raise exception 'challenge_rpc_required' using errcode='42501';
 end if;
 if tg_op='INSERT' then return new; end if;
 if tg_op='UPDATE' and tg_table_name in ('challenge_worker_invocations_v1','challenge_snapshot_invocations_v1','challenge_work_claims_v1') then
  return new;
 end if;
 raise exception 'challenge_immutable' using errcode='23001';
end $$;

create function app.challenge_worker_principal_v1() returns text
language sql stable set search_path='' as $$
 select case when current_setting('role',true) in ('service_role','postgres')
             then current_setting('role')
             when current_user='postgres' then 'postgres'
             else current_setting('role') end
$$;

do $$ declare t text; begin
 foreach t in array array['worker_invocations','snapshot_invocations','worker_recoveries','worker_audit','worker_heartbeats'] loop
  execute format('create trigger challenge_%s_guard before insert or update or delete on app.challenge_%s_v1 for each row execute function app.challenge_worker_state_guard_v1()',t,t);
  execute format('create trigger challenge_%s_no_truncate before truncate on app.challenge_%s_v1 for each statement execute function app.challenge_worker_state_guard_v1()',t,t);
 end loop;
 create trigger challenge_worker_claims_guard before insert or update or delete on app.challenge_work_claims_v1
  for each row execute function app.challenge_worker_state_guard_v1();
 create trigger challenge_worker_claims_no_truncate before truncate on app.challenge_work_claims_v1
  for each statement execute function app.challenge_worker_state_guard_v1();
end $$;

create function app.challenge_worker_scope_ids_v1(p_scope jsonb)
returns uuid[] language plpgsql stable set search_path='' as $$
declare ids uuid[]; item text;
begin
 if p_scope is null or jsonb_typeof(p_scope)<>'object'
 or p_scope->>'version' is distinct from 'challenge_worker_scope_v1'
 or p_scope->>'kind' not in ('due','challenge_ids') then
  raise exception 'challenge_invalid_scope' using errcode='22023';
 end if;
 if p_scope->>'kind'='due' then
  if p_scope-'version'-'kind'<>'{}'::jsonb then raise exception 'challenge_invalid_scope' using errcode='22023'; end if;
  return null;
 end if;
 if p_scope - 'version' - 'kind' - 'ids' <> '{}'::jsonb
 or jsonb_typeof(p_scope->'ids')<>'array'
 or jsonb_array_length(p_scope->'ids')>50 then
  raise exception 'challenge_invalid_scope' using errcode='22023';
 end if;
 for item in select value from jsonb_array_elements_text(p_scope->'ids') loop
  if item !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   raise exception 'challenge_invalid_scope' using errcode='22023';
  end if;
 end loop;
 ids:=coalesce((select array_agg(value::uuid order by value::uuid) from jsonb_array_elements_text(p_scope->'ids')),'{}'::uuid[]);
 if cardinality(ids)<>(select count(distinct value::uuid) from jsonb_array_elements_text(p_scope->'ids')) then
  raise exception 'challenge_invalid_scope' using errcode='22023';
 end if;
 if exists(select 1 from unnest(ids) selected(id) where not exists(select 1 from app.challenge_lobbies_v1 where id=selected.id)) then
  raise exception 'challenge_invalid_scope' using errcode='22023';
 end if;
 return ids;
end $$;

create function app.challenge_worker_scope_digest_v1(p_scope jsonb)
returns text language sql immutable strict set search_path='' as $$
 select encode(extensions.digest(p_scope::text,'sha256'),'hex')
$$;

create function app.challenge_claim_scoped_v1(p_scope jsonb,p_limit integer)
returns jsonb language plpgsql set search_path='' as $$
declare item record; token uuid; claims jsonb:='[]'; wall timestamptz; ids uuid[];
begin
 ids:=app.challenge_worker_scope_ids_v1(p_scope);
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_batch' using errcode='22023'; end if;
 wall:=clock_timestamp();
 if (select processing from app.challenge_runtime_v1 where singleton) then
  for item in
   with work as materialized (
    select * from app.challenge_work_v1()
    where due_at<=app.challenge_now_v1()
      and (ids is null or id=any(ids))
   )
   select q.*,w.due_at from app.challenge_work_claims_v1 q join work w on w.id=q.challenge_id
   where (q.state in ('ready','retry') and q.next_attempt_at<=wall)
      or (q.state='claimed' and q.lease_expires_at<=wall)
   order by w.due_at,q.challenge_id limit p_limit
   for update of q skip locked
  loop
   if item.attempts>=5 then
    update app.challenge_work_claims_v1 set state='dead',lease_expires_at=null,last_error_code='57014',updated_at=wall
    where challenge_id=item.challenge_id;
    continue;
   end if;
   token:=extensions.gen_random_uuid();
   update app.challenge_work_claims_v1 set state='claimed',claim_token=token,
    attempts=attempts+1,total_attempts=total_attempts+1,
    lease_expires_at=wall+interval '60 seconds',
    last_error_code=case when item.state='claimed' then '57014' else last_error_code end,
    updated_at=wall where challenge_id=item.challenge_id;
   claims:=claims||jsonb_build_array(jsonb_build_object(
    'id',item.challenge_id,'claim_token',token,'attempt',item.attempts+1,
    'lease_expires_at',wall+interval '60 seconds','due_at',item.due_at));
  end loop;
 end if;
 return claims;
end $$;

create function app.challenge_worker_record_heartbeat_v1(
 p_invocation_id uuid,p_status text,p_claimed integer,p_error_code text default null)
returns void language plpgsql set search_path='' as $$
declare due integer; retries integer; dead integer; failed integer; code text:=p_error_code;
begin
 if p_status not in ('healthy_empty','healthy_backlog','paused','disabled','failed')
 or p_claimed not between 0 and 50 or code is not null and code !~ '^[0-9A-Z]{5}$' then
  raise exception 'challenge_invalid_heartbeat' using errcode='22023';
 end if;
 select count(*) filter(where due_at<=app.challenge_now_v1()) into due from app.challenge_work_v1();
 select count(*) filter(where state='retry'),count(*) filter(where state='dead'),
  count(*) filter(where state in ('retry','dead') or (state='claimed' and lease_expires_at<=clock_timestamp()))
  into retries,dead,failed from app.challenge_work_claims_v1;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_worker_heartbeats_v1
  (invocation_id,status,claimed_count,due_count,retry_count,dead_letter_count,failed_count,error_code,recorded_at)
 values(p_invocation_id,p_status,p_claimed,coalesce(due,0),coalesce(retries,0),coalesce(dead,0),coalesce(failed,0),code,clock_timestamp());
end $$;

create function public.challenge_prepare_worker_invocation_v1(
 p_invocation_id uuid,p_scope jsonb,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved app.challenge_worker_invocations_v1; digest text; ids uuid[]; n timestamptz:=clock_timestamp(); response jsonb; principal text:=app.challenge_worker_principal_v1();
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null or p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_batch' using errcode='22023'; end if;
 ids:=app.challenge_worker_scope_ids_v1(p_scope); digest:=app.challenge_worker_scope_digest_v1(p_scope);
 perform app.challenge_gate_v1();perform app.challenge_lock_v1('worker_invocation',p_invocation_id);
 select * into saved from app.challenge_worker_invocations_v1 where id=p_invocation_id;
 if found then
  if saved.scope is distinct from p_scope or saved.limit_count is distinct from p_limit then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return jsonb_build_object('invocation_id',saved.id,'status',saved.state,'scope_digest',saved.scope_digest,'limit',saved.limit_count);
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_worker_invocations_v1(id,scope,scope_digest,limit_count,state,prepared_at,updated_at)
 values(p_invocation_id,p_scope,digest,p_limit,'prepared',n,n);
 insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,principal,status_code,recorded_at)
 values('prepare',p_invocation_id,p_invocation_id,principal,'00000',n);
 return jsonb_build_object('invocation_id',p_invocation_id,'status','prepared','scope_digest',digest,'limit',p_limit);
end $$;

create function public.challenge_dispatch_worker_invocation_v1(p_invocation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invocation app.challenge_worker_invocations_v1; claims jsonb; response jsonb; n timestamptz:=clock_timestamp(); code text; status text; runtime record; principal text:=app.challenge_worker_principal_v1();
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null then raise exception 'challenge_invalid_batch' using errcode='22023'; end if;
 perform app.challenge_gate_v1();perform app.challenge_lock_v1('worker_invocation',p_invocation_id);
 select * into invocation from app.challenge_worker_invocations_v1 where id=p_invocation_id for update;
 if not found then raise exception 'challenge_invocation_required' using errcode='55000'; end if;
 if invocation.state<>'prepared' then return invocation.claim_response; end if;
 select * into runtime from app.challenge_runtime_v1 where singleton;
 begin
  if not runtime.fixtures then
   code:='42501';status:='disabled';
   raise exception 'challenge_fixture_disabled' using errcode='42501';
  end if;
  claims:=app.challenge_claim_scoped_v1(invocation.scope,invocation.limit_count);
  status:=case when not runtime.processing then 'paused' when jsonb_array_length(claims)=0 then 'healthy_empty' else 'dispatched' end;
  response:=jsonb_build_object('invocation_id',p_invocation_id,'status',status,'claims',claims,'server_time',app.challenge_now_v1());
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_worker_invocations_v1 set state='dispatched',claim_response=response,dispatch_attempts=dispatch_attempts+1,dispatched_at=n,updated_at=n where id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,principal,status_code,recorded_at) values('dispatch',p_invocation_id,p_invocation_id,principal,'00000',n);
  perform app.challenge_worker_record_heartbeat_v1(p_invocation_id,case when status='paused' then 'paused' when status='healthy_empty' then 'healthy_empty' else 'healthy_backlog' end,jsonb_array_length(claims));
 exception when others then
  if code is null then code:=sqlstate; end if;
  if status is null then status:=case when not runtime.fixtures then 'disabled' else 'failed' end; end if;
  response:=jsonb_build_object('invocation_id',p_invocation_id,'status',status,'error_code',code);
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_worker_invocations_v1 set state='failed',claim_response=response,dispatch_attempts=dispatch_attempts+1,last_error_code=code,dispatched_at=n,updated_at=n where id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,principal,status_code,recorded_at) values('dispatch',p_invocation_id,p_invocation_id,principal,code,n);
  perform app.challenge_worker_record_heartbeat_v1(p_invocation_id,status,0,code);
 end;
 return response;
end $$;

create function public.challenge_recover_failed_item_v1(p_request_id uuid,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q app.challenge_work_claims_v1; prior app.challenge_worker_recoveries_v1; response jsonb; n timestamptz:=clock_timestamp(); principal text:=app.challenge_worker_principal_v1();
begin
 perform app.duel_require_service_v1();
 if p_request_id is null or p_id is null then raise exception 'challenge_invalid_recovery' using errcode='22023'; end if;
 perform app.challenge_gate_v1();perform app.challenge_lock_v1('challenge',p_id);perform app.challenge_lock_v1('worker_recovery',p_request_id);
 select * into prior from app.challenge_worker_recoveries_v1 where request_id=p_request_id;
 if found then
  if prior.challenge_id is distinct from p_id then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return prior.response;
 end if;
 select * into q from app.challenge_work_claims_v1 where challenge_id=p_id for update;
 if q.challenge_id is null or q.state is distinct from 'dead' then raise exception 'challenge_recovery_unavailable' using errcode='55000'; end if;
 response:=jsonb_build_object('id',p_id,'status','ready','recovered',true,'total_attempts',q.total_attempts);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_worker_recoveries_v1(request_id,challenge_id,previous_state,previous_attempts,previous_total_attempts,previous_error_code,response,authorized_principal,recorded_at)
 values(p_request_id,p_id,q.state,q.attempts,q.total_attempts,q.last_error_code,response,principal,n);
 update app.challenge_work_claims_v1 set state='ready',claim_token=null,attempts=0,next_attempt_at=clock_timestamp(),lease_expires_at=null,updated_at=n where challenge_id=p_id;
 insert into app.challenge_worker_audit_v1(operation,request_id,challenge_id,principal,status_code,recorded_at) values('recover',p_request_id,p_id,principal,'00000',n);
 return response;
end $$;

create function public.challenge_prepare_community_snapshot_invocation_v1(p_invocation_id uuid,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved app.challenge_snapshot_invocations_v1; n timestamptz:=clock_timestamp(); principal text:=app.challenge_worker_principal_v1();
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null or p_id is null or not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) then
  raise exception 'challenge_snapshot_unavailable' using errcode='42501';
 end if;
 perform app.challenge_gate_v1();perform app.challenge_lock_v1('snapshot_invocation',p_invocation_id);
 select * into saved from app.challenge_snapshot_invocations_v1 where id=p_invocation_id;
 if found then
  if saved.challenge_id is distinct from p_id then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return jsonb_build_object('invocation_id',saved.id,'status',saved.state);
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_snapshot_invocations_v1(id,challenge_id,state,prepared_at,updated_at) values(p_invocation_id,p_id,'prepared',n,n);
 insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,challenge_id,principal,status_code,recorded_at) values('snapshot_prepare',p_invocation_id,p_invocation_id,p_id,principal,'00000',n);
 return jsonb_build_object('invocation_id',p_invocation_id,'status','prepared');
end $$;

create function public.challenge_dispatch_community_snapshot_invocation_v1(p_invocation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invocation app.challenge_snapshot_invocations_v1; snapshot_response jsonb; n timestamptz:=clock_timestamp(); code text; status text; principal text:=app.challenge_worker_principal_v1();
begin
 perform app.duel_require_service_v1();
 if p_invocation_id is null then raise exception 'challenge_invalid_snapshot' using errcode='22023'; end if;
 perform app.challenge_gate_v1();perform app.challenge_lock_v1('snapshot_invocation',p_invocation_id);
 select * into invocation from app.challenge_snapshot_invocations_v1 where id=p_invocation_id for update;
 if not found then raise exception 'challenge_snapshot_invocation_required' using errcode='55000'; end if;
 if invocation.state<>'prepared' then return invocation.response; end if;
 begin
  perform public.challenge_capture_community_snapshot_v1(invocation.challenge_id);
  snapshot_response:=jsonb_build_object('invocation_id',p_invocation_id,'status','checked');
  status:='checked';
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_snapshot_invocations_v1 as s set state='dispatched',response=snapshot_response,dispatch_attempts=s.dispatch_attempts+1,dispatched_at=n,updated_at=n where s.id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,challenge_id,principal,status_code,recorded_at) values('snapshot_dispatch',p_invocation_id,p_invocation_id,invocation.challenge_id,principal,'00000',n);
 exception when others then
  code:=sqlstate;status:=case when code='42501' then 'disabled' else 'failed' end;
  snapshot_response:=jsonb_build_object('invocation_id',p_invocation_id,'status',status,'error_code',code);
  perform set_config('app.challenge_write_v1','on',true);
  update app.challenge_snapshot_invocations_v1 as s set state='failed',response=snapshot_response,dispatch_attempts=s.dispatch_attempts+1,last_error_code=code,dispatched_at=n,updated_at=n where s.id=p_invocation_id;
  insert into app.challenge_worker_audit_v1(operation,request_id,invocation_id,challenge_id,principal,status_code,recorded_at) values('snapshot_dispatch',p_invocation_id,p_invocation_id,invocation.challenge_id,principal,code,n);
 end;
 return snapshot_response;
end $$;

-- Keep the existing restricted operations contract, including its failed-work
-- summaries and historical failure count.  The generic local projection below
-- is deliberately separate so existing restricted callers do not lose the
-- ability to select one failed item for an authorized recovery.
create function public.challenge_local_worker_status_v1()
returns jsonb language plpgsql security definer set search_path='' as $$
declare response jsonb; hb app.challenge_worker_heartbeats_v1; runtime record; due integer; retry integer; dead integer; abandoned integer; failed integer;
begin
 perform app.duel_require_service_v1();
 select * into runtime from app.challenge_runtime_v1 where singleton;
 select count(*) filter(where due_at<=app.challenge_now_v1()) into due from app.challenge_work_v1();
 select count(*) filter(where state='retry'),count(*) filter(where state='dead'),count(*) filter(where state='claimed' and lease_expires_at<=clock_timestamp()),
  count(*) filter(where state in ('retry','dead') or (state='claimed' and lease_expires_at<=clock_timestamp()))
  into retry,dead,abandoned,failed from app.challenge_work_claims_v1;
 select * into hb from app.challenge_worker_heartbeats_v1 order by recorded_at desc,id desc limit 1;
 response:=jsonb_build_object(
  'server_time',clock_timestamp(),
  'processing_state',case when not runtime.fixtures then 'disabled' when not runtime.processing then 'paused' when failed>0 then 'failure' when coalesce(due,0)=0 then 'healthy_empty' else 'healthy_backlog' end,
  'admission_paused',not runtime.admission,
  'processing_paused',not runtime.processing,
  'fixtures_enabled',runtime.fixtures,
  'discovery_enabled',runtime.discovery,
  'due_count',coalesce(due,0),
  'retry_count',coalesce(retry,0),
  'dead_letter_count',coalesce(dead,0),
  'abandoned_count',coalesce(abandoned,0),
  'failed_count',coalesce(failed,0),
  'heartbeat_status',hb.status,
  'last_heartbeat_at',hb.recorded_at,
  'heartbeat_age_seconds',case when hb.recorded_at is null then null else greatest(0,floor(extract(epoch from clock_timestamp()-hb.recorded_at))) end,
  'recent_failure_count',(select count(*) from app.challenge_worker_audit_v1 where status_code<>'00000' and recorded_at>=clock_timestamp()-interval '24 hours'),
  'failure_codes',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'count',count) order by code),'[]') from (select last_error_code code,count(*) from app.challenge_work_claims_v1 where last_error_code is not null group by last_error_code limit 20) codes)
 );
 return response;
end $$;

revoke all on function
 app.challenge_worker_scope_ids_v1(jsonb),app.challenge_worker_scope_digest_v1(jsonb),app.challenge_claim_scoped_v1(jsonb,integer),app.challenge_worker_record_heartbeat_v1(uuid,text,integer,text),
 public.challenge_prepare_worker_invocation_v1(uuid,jsonb,integer),public.challenge_dispatch_worker_invocation_v1(uuid),public.challenge_recover_failed_item_v1(uuid,uuid),
 public.challenge_prepare_community_snapshot_invocation_v1(uuid,uuid),public.challenge_dispatch_community_snapshot_invocation_v1(uuid),public.challenge_local_worker_status_v1()
 from public,anon,authenticated,service_role;
grant execute on function public.challenge_prepare_worker_invocation_v1(uuid,jsonb,integer),public.challenge_dispatch_worker_invocation_v1(uuid),public.challenge_recover_failed_item_v1(uuid,uuid),
 public.challenge_prepare_community_snapshot_invocation_v1(uuid,uuid),public.challenge_dispatch_community_snapshot_invocation_v1(uuid),public.challenge_local_worker_status_v1() to service_role;
