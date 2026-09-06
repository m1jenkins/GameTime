-- Phase 3(e): local fictional lifecycle. No endpoint, schedule or live money.
-- Preserve agreement receipts; operational finality is an independent ledger.
create table app.performance_lifecycle_runtime (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false
);
insert into app.performance_lifecycle_runtime values(true,false);
create table app.performance_lifecycle_activations (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
create table app.performance_lifecycle_notices (
  commitment_id uuid not null,
  proof_revision integer not null check(proof_revision>=0),
  actor_id uuid not null,
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  outcome jsonb not null check(jsonb_typeof(outcome)='object'),
  primary key(commitment_id,proof_revision),
  foreign key(commitment_id,actor_id) references app.performance_commitment_agreements(id,actor_id)
);
create index performance_lifecycle_notice_actor_idx on app.performance_lifecycle_notices(actor_id);
create table app.performance_lifecycle_cases (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null,
  proof_revision integer not null,
  reason text not null check(reason in ('wrong_result','wrong_identity','missing_result')),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  unique(commitment_id,proof_revision),
  foreign key(commitment_id,proof_revision) references app.performance_lifecycle_notices(commitment_id,proof_revision)
);
-- Append-only, scope-specific authorizations; a later grant never revives an old one.
create table app.performance_lifecycle_grants (
  id bigint generated always as identity primary key,
  request_id uuid not null unique,
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  operator_id uuid not null references public.profiles(id),
  scope text not null check(scope in ('review','support')),
  enabled boolean not null,
  expires_at timestamptz,
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  check((enabled and expires_at>recorded_at and expires_at<=recorded_at+interval '168 hours' and isfinite(expires_at))
    or (not enabled and expires_at is null))
);
create index performance_lifecycle_grant_current_idx on app.performance_lifecycle_grants(commitment_id,operator_id,scope,id desc);
create index performance_lifecycle_grant_operator_idx on app.performance_lifecycle_grants(operator_id);
create table app.performance_lifecycle_resolutions (
  case_id uuid primary key references app.performance_lifecycle_cases(id),
  operator_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.performance_lifecycle_grants(id),
  decision text not null check(decision in ('uphold','inconclusive')),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
create index performance_lifecycle_resolution_operator_idx on app.performance_lifecycle_resolutions(operator_id);
create index performance_lifecycle_resolution_grant_idx on app.performance_lifecycle_resolutions(grant_id);
create table app.performance_lifecycle_results (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  result jsonb not null check(jsonb_typeof(result)='object'),
  input_digest text not null check(input_digest ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
-- Simulation accounting units only: no balance, debt, payee or transfer.
create table app.performance_lifecycle_settlements (
  commitment_id uuid primary key references app.performance_lifecycle_results(commitment_id),
  returned_cents integer not null check(returned_cents in (0,2000)),
  lost_cents integer not null check(lost_cents in (0,2000)),
  fee_cents integer not null default 0 check(fee_cents=0),
  mode text not null default 'simulated' check(mode='simulated'),
  redeemable boolean not null default false check(not redeemable),
  forfeiture_recipient text not null default 'unselected' check(forfeiture_recipient='unselected'),
  payee uuid check(payee is null),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  check(returned_cents+lost_cents=2000)
);
create table app.performance_lifecycle_support (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null references app.performance_lifecycle_results(commitment_id),
  operator_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.performance_lifecycle_grants(id),
  category text not null check(category in ('result_correction','identity_correction','missing_result')),
  note text not null check(char_length(note) between 1 and 500 and note=btrim(note) and note !~ '[[:cntrl:]]'),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
create index performance_lifecycle_support_commitment_idx on app.performance_lifecycle_support(commitment_id);
create index performance_lifecycle_support_operator_idx on app.performance_lifecycle_support(operator_id);
create index performance_lifecycle_support_grant_idx on app.performance_lifecycle_support(grant_id);
create table app.performance_lifecycle_requests (
  actor_id uuid not null references public.profiles(id), request_id uuid not null,
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  payload jsonb not null, result jsonb not null, primary key(actor_id,request_id)
);
create index performance_lifecycle_request_commitment_idx on app.performance_lifecycle_requests(commitment_id);
create table app.performance_lifecycle_retention (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  scope text not null default 'performance_lifecycle_v1' check(scope='performance_lifecycle_v1'),
  reason text not null default 'awaiting_approved_result_support_retention_policy'
    check(reason='awaiting_approved_result_support_retention_policy')
);
create table app.performance_lifecycle_audit (
  id bigint generated always as identity primary key,
  commitment_id uuid references app.performance_commitment_agreements(id),
  actor_id uuid references public.profiles(id),
  operation text not null check(operation in ('gate_on','gate_off','snapshot_read','review_read','support_read','grant_on','grant_off')),
  grant_id bigint references app.performance_lifecycle_grants(id),
  recorded_at timestamptz not null default clock_timestamp() check(isfinite(recorded_at))
);
create index performance_lifecycle_audit_commitment_idx on app.performance_lifecycle_audit(commitment_id);
create index performance_lifecycle_audit_actor_idx on app.performance_lifecycle_audit(actor_id);
create index performance_lifecycle_audit_grant_idx on app.performance_lifecycle_audit(grant_id);

create function app.performance_lifecycle_guard_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
    or current_setting('app.performance_lifecycle_write_v1',true) is distinct from 'on' then
    raise exception 'performance_lifecycle_rpc_required' using errcode='42501'; end if;
  if tg_op<>'INSERT' and not(tg_op='UPDATE' and tg_table_name='performance_lifecycle_runtime') then
    raise exception 'performance_lifecycle_history_retained' using errcode='23001'; end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['runtime','activations','notices','cases','grants','resolutions','results','settlements','support','requests','retention','audit'] loop
    execute format('alter table app.performance_lifecycle_%I enable row level security',t);
    execute format('revoke all on app.performance_lifecycle_%I from public,anon,authenticated,service_role',t);
    execute format('create trigger performance_lifecycle_guard before insert or update or delete on app.performance_lifecycle_%I
      for each row execute function app.performance_lifecycle_guard_v1()',t);
    execute format('create trigger performance_lifecycle_truncate before truncate on app.performance_lifecycle_%I
      for each statement execute function app.performance_lifecycle_guard_v1()',t);
  end loop;
end; $$;
revoke all on sequence app.performance_lifecycle_audit_id_seq,app.performance_lifecycle_grants_id_seq from public,anon,authenticated,service_role;

create function public.set_commitment_lifecycle_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$ begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'performance_lifecycle_invalid_gate' using errcode='22023'; end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  update app.performance_lifecycle_runtime set enabled=p_enabled where singleton;
  insert into app.performance_lifecycle_audit(operation) values(case when p_enabled then 'gate_on' else 'gate_off' end);
  return p_enabled;
end; $$;
-- Sorted owner/operator profiles -> caller session -> lifecycle runtime -> agreement.
-- Existing attempt/social/deletion writes serialize on the owner profile first.
create function app.performance_lifecycle_lock_v1(p_commitment uuid,p_actor uuid)
returns app.performance_commitment_agreements language plpgsql set search_path='' as $$
declare c app.performance_commitment_agreements;
begin
  select * into c from app.performance_commitment_agreements where id=p_commitment;
  if not found then raise exception 'performance_lifecycle_unavailable' using errcode='42501'; end if;
  perform 1 from public.profiles where id in(c.actor_id,p_actor) order by id for update;
  if p_actor is not null then perform app.performance_commitment_lock_actor_v1(); end if;
  perform 1 from app.performance_lifecycle_runtime where singleton for share;
  select * into strict c from app.performance_commitment_agreements where id=p_commitment for update;
  if p_actor is not null then perform app.performance_commitment_lock_actor_v1(); end if;
  return c;
end; $$;
create function app.performance_lifecycle_admit_v1() returns void
language plpgsql set search_path='' as $$ begin
  if not(select enabled from app.performance_lifecycle_runtime where singleton) then
    raise exception 'performance_lifecycle_disabled' using errcode='42501'; end if;
end; $$;
create function app.performance_lifecycle_clock_v1(c app.performance_commitment_agreements,p_now timestamptz) returns timestamptz
language plpgsql set search_path='' as $$ declare t timestamptz:=coalesce(p_now,clock_timestamp()); begin
  if not isfinite(t) or t<c.created_at then raise exception 'performance_lifecycle_invalid_clock' using errcode='22023'; end if;
  return t;
end; $$;
create function app.performance_lifecycle_save_v1(p_request uuid,p_commitment uuid,p_payload jsonb,p_result jsonb) returns jsonb
language plpgsql set search_path='' as $$ begin
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_retention(commitment_id) values(p_commitment) on conflict do nothing;
  insert into app.performance_lifecycle_requests values(auth.uid(),p_request,p_commitment,p_payload,p_result);
  return p_result;
end; $$;
create function app.performance_lifecycle_recover_v1(p_request uuid,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$ declare r app.performance_lifecycle_requests; begin
  if p_request is null then raise exception 'performance_lifecycle_request_required' using errcode='22023'; end if;
  select * into r from app.performance_lifecycle_requests where actor_id=auth.uid() and request_id=p_request;
  if found and r.payload is distinct from p_payload then
    raise exception 'performance_lifecycle_request_conflict' using errcode='22023'; end if;
  return r.result;
end; $$;

-- Complete evaluator input, with every captured source also compared even when
-- it has not been independently reviewed yet. No progress or social inputs.
create function app.performance_lifecycle_snapshot_v1(c app.performance_commitment_agreements,p_now timestamptz) returns jsonb
language sql stable set search_path='' set timezone='UTC' as $$
  select jsonb_build_object(
    'agreement',to_jsonb(c)||jsonb_build_object('consent',(select to_jsonb(s) from app.performance_commitment_consents s where commitment_id=c.id)),
    'now',p_now,
    'attempts',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('event',to_jsonb(e)) order by a.nominated_at,a.id)
      from app.performance_attempt_nominations a join app.performance_attempt_events e on e.id=a.event_id where a.commitment_id=c.id),'[]'::jsonb),
    'confirmation',(select to_jsonb(f) from app.performance_attempt_confirmations f where commitment_id=c.id),
    'proofRevisions',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('source',to_jsonb(s)) order by r.revision)
      from app.performance_attempt_revisions r join app.performance_attempt_sources s on s.id=r.source_id where r.commitment_id=c.id),'[]'::jsonb),
    'capturedSources',coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from app.performance_attempt_sources s where commitment_id=c.id),'[]'::jsonb),
    'notices',coalesce((select jsonb_agg(jsonb_build_object('proofRevision',proof_revision,'actorId',actor_id,'recordedAt',recorded_at)
      order by proof_revision) from app.performance_lifecycle_notices where commitment_id=c.id),'[]'::jsonb),
    'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'proofRevision',k.proof_revision,'filedBy',c.actor_id,
      'filedAt',k.recorded_at,'resolution',case when r.case_id is null then null else
      jsonb_build_object('reviewerId',r.operator_id,'decidedAt',r.recorded_at,'decision',r.decision) end) order by k.recorded_at,k.id)
      from app.performance_lifecycle_cases k left join app.performance_lifecycle_resolutions r on r.case_id=k.id
      where k.commitment_id=c.id),'[]'::jsonb),
    'finalResult',(select result from app.performance_lifecycle_results where commitment_id=c.id));
$$;
create function app.performance_lifecycle_load_at_v1(p_commitment_id uuid,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; t timestamptz;
begin
  perform app.duel_require_service_v1(); c:=app.performance_lifecycle_lock_v1(p_commitment_id,null);
  perform app.performance_lifecycle_admit_v1(); t:=app.performance_lifecycle_clock_v1(c,p_now);
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_retention(commitment_id) values(c.id) on conflict do nothing;
  insert into app.performance_lifecycle_audit(commitment_id,operation) values(c.id,'snapshot_read');
  if c.status='open' and t>=c.starts_at and not exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id) then
    insert into app.performance_lifecycle_activations values(c.id,t) on conflict do nothing;
  end if;
  return app.performance_lifecycle_snapshot_v1(c,t);
end; $$;
create function public.load_commitment_lifecycle_v1(p_commitment_id uuid) returns jsonb
language sql security definer set search_path='' as $$select app.performance_lifecycle_load_at_v1(p_commitment_id)$$;

create function app.performance_lifecycle_commit_at_v1(p_input jsonb,p_decision jsonb,p_now timestamptz default null)
returns text language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; t timestamptz; evaluated timestamptz; current_input jsonb;
  phase text:=p_decision->>'phase'; rev integer; outcome jsonb:=p_decision->'outcome'; boundary timestamptz;
begin
  perform app.duel_require_service_v1();
  c:=app.performance_lifecycle_lock_v1((p_input->'agreement'->>'id')::uuid,null);
  perform app.performance_lifecycle_admit_v1();
  t:=app.performance_lifecycle_clock_v1(c,p_now); evaluated:=(p_input->>'now')::timestamptz;
  if evaluated is null or not isfinite(evaluated) or evaluated>t or evaluated<c.created_at then
    raise exception 'performance_lifecycle_invalid_clock' using errcode='22023'; end if;
  current_input:=app.performance_lifecycle_snapshot_v1(c,evaluated);
  if current_input is distinct from p_input then return 'stale'; end if;
  -- Time is sampled again after locks. Even a one-microsecond crossing is stale.
  for boundary in select unnest(array[c.starts_at,c.deadline_at,
    (c.terms->>'results_due_at')::timestamptz,(c.terms->>'finality_due_at')::timestamptz])
    union all select recorded_at+interval '168 hours' from app.performance_lifecycle_notices where commitment_id=c.id
    union all select recorded_at+interval '168 hours' from app.performance_lifecycle_cases where commitment_id=c.id loop
    if evaluated<boundary and t>=boundary then return 'stale'; end if;
  end loop;
  -- The service-only worker runs the versioned pure evaluator. SQL validates
  -- binding/shape and optimistic concurrency, not a second implementation of it.
  if not app.duel_proof_keys_v1(p_decision,array['version','commitmentId','termsDigest','proofRevision','phase',
      'outcome','disputeClosesAt','reviewDueAt','supportCorrectionRequired'])
    or p_decision->>'version' is distinct from 'performance-fixture-official-5k-v1'
    or p_decision->>'commitmentId' is distinct from c.id::text
    or p_decision->>'termsDigest' is distinct from c.terms_digest
    or jsonb_typeof(p_decision->'supportCorrectionRequired') is distinct from 'boolean'
    or jsonb_typeof(p_decision->'proofRevision') is distinct from 'number'
    or (p_decision->>'proofRevision') !~ '^[0-9]+$'
    or phase is null or phase not in ('scheduled','active','awaiting_proof','provisional','ready_to_finalize','final') then
    raise exception 'performance_lifecycle_invalid_decision' using errcode='22023'; end if;
  rev:=(p_decision->>'proofRevision')::integer;
  if rev>(select count(*) from app.performance_attempt_revisions where commitment_id=c.id) then
    raise exception 'performance_lifecycle_invalid_decision' using errcode='22023'; end if;
  if current_input->'finalResult'<>'null'::jsonb then return 'final'; end if;
  if phase='final' then raise exception 'performance_final_result_required' using errcode='55000'; end if;
  if phase in ('provisional','ready_to_finalize') then
    if outcome->>'kind' is null or not (
      (app.duel_proof_keys_v1(outcome,array['kind','reason','attemptId']) and outcome->>'kind'='success'
        and outcome->>'reason'='strict_target_met' and exists(select 1 from app.performance_attempt_nominations
          where commitment_id=c.id and id::text=outcome->>'attemptId'))
      or (app.duel_proof_keys_v1(outcome,array['kind','reason']) and (
        (outcome->>'kind'='miss' and outcome->>'reason' in ('confirmed_attempt_set','explicit_no_attempts')) or
        (outcome->>'kind'='inconclusive' and outcome->>'reason' in ('unresolved_proof','review_timeout','review_inconclusive','finality_timeout')) or
        (outcome->>'kind'='closed' and outcome->>'reason' in ('cancel','withdrawal','injury','account_deleted'))))) then
      raise exception 'performance_lifecycle_invalid_outcome' using errcode='22023'; end if;
  elsif outcome is distinct from 'null'::jsonb then
    raise exception 'performance_lifecycle_invalid_outcome' using errcode='22023';
  end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_retention(commitment_id) values(c.id) on conflict do nothing;
  if phase='provisional' then
    if t>=(c.terms->>'finality_due_at')::timestamptz or t<(c.terms->>'results_due_at')::timestamptz or c.status<>'open' then
      return 'stale'; end if;
    insert into app.performance_lifecycle_notices values(c.id,rev,c.actor_id,t,outcome) on conflict do nothing;
    return 'provisional';
  elsif phase='ready_to_finalize' then
    insert into app.performance_lifecycle_results values(c.id,jsonb_build_object('version',p_decision->'version',
      'commitmentId',c.id,'termsDigest',c.terms_digest,'proofRevision',rev,'finalizedAt',t,'outcome',outcome),
      encode(extensions.digest(p_input::text,'sha256'),'hex'),t);
    perform set_config('app.performance_commitment_write_v1','on',true);
    update app.performance_commitment_enrollments set released_at=t where commitment_id=c.id and released_at is null;
    -- Finality does not expand the old sharing consent. End access permanently.
    perform set_config('app.performance_following_write_v1','on',true);
    update app.performance_following_grants set status='revoked',ended_at=clock_timestamp(),reminder_at=null,revision=revision+1
      where commitment_id=c.id and status in ('pending','active');
    return 'final';
  end if;
  return phase;
end; $$;
create function public.commit_commitment_lifecycle_v1(p_input jsonb,p_decision jsonb) returns text
language sql security definer set search_path='' as $$select app.performance_lifecycle_commit_at_v1(p_input,p_decision)$$;

create function app.performance_lifecycle_settle_at_v1(p_commitment_id uuid,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; r app.performance_lifecycle_results; s app.performance_lifecycle_settlements; t timestamptz; lost integer;
begin
  perform app.duel_require_service_v1(); c:=app.performance_lifecycle_lock_v1(p_commitment_id,null);
  select * into s from app.performance_lifecycle_settlements where commitment_id=c.id;
  if found then return to_jsonb(s); end if;
  perform app.performance_lifecycle_admit_v1(); t:=app.performance_lifecycle_clock_v1(c,p_now);
  select * into r from app.performance_lifecycle_results where commitment_id=c.id;
  if not found or t<r.recorded_at then raise exception 'performance_final_result_required' using errcode='55000'; end if;
  lost:=case when r.result->'outcome'->>'kind'='miss' then 2000 else 0 end;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_settlements(commitment_id,returned_cents,lost_cents,recorded_at)
    values(c.id,2000-lost,lost,t) returning * into s;
  return to_jsonb(s);
end; $$;
create function public.settle_commitment_simulation_v1(p_commitment_id uuid) returns jsonb
language sql security definer set search_path='' as $$select app.performance_lifecycle_settle_at_v1(p_commitment_id)$$;

create function app.performance_lifecycle_case_at_v1(p_request_id uuid,p_commitment_id uuid,p_revision integer,
  p_reason text,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; t timestamptz; notice_at timestamptz; k uuid; p jsonb; r jsonb;
begin
  c:=app.performance_lifecycle_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_lifecycle_unavailable' using errcode='42501'; end if;
  p:=jsonb_build_object('operation','file_review','commitment_id',c.id,'revision',p_revision,'reason',p_reason);
  r:=app.performance_lifecycle_recover_v1(p_request_id,p); if r is not null then return r; end if;
  -- Filing and exact owner recovery remain available during a gate shutdown.
  t:=app.performance_lifecycle_clock_v1(c,p_now);
  if p_reason is null or p_reason not in ('wrong_result','wrong_identity','missing_result') then
    raise exception 'performance_lifecycle_invalid_case' using errcode='22023'; end if;
  select recorded_at into notice_at from app.performance_lifecycle_notices where commitment_id=c.id and proof_revision=p_revision;
  if notice_at is null or t<notice_at or t>=notice_at+interval '168 hours'
    or t>=(c.terms->>'finality_due_at')::timestamptz or c.status<>'open'
    or exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id) then
    raise exception 'performance_review_window_closed' using errcode='55000'; end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_cases(commitment_id,proof_revision,reason,recorded_at)
    values(c.id,p_revision,p_reason,t) returning id into k;
  return app.performance_lifecycle_save_v1(p_request_id,c.id,p,jsonb_build_object('case_id',k,'recorded_at',t));
end; $$;
create function public.file_commitment_review_v1(p_request_id uuid,p_commitment_id uuid,p_revision integer,p_reason text) returns jsonb
language sql security definer set search_path='' as $$select app.performance_lifecycle_case_at_v1(p_request_id,p_commitment_id,p_revision,p_reason)$$;

create function public.set_commitment_lifecycle_operator_v1(p_request_id uuid,p_commitment_id uuid,p_operator_id uuid,
  p_scope text,p_expires_at timestamptz) returns bigint
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; g app.performance_lifecycle_grants; t timestamptz; v_id bigint;
begin
  perform app.duel_require_service_v1();
  select * into c from app.performance_commitment_agreements where id=p_commitment_id;
  perform 1 from public.profiles where id in(c.actor_id,p_operator_id) order by id for update;
  c:=app.performance_lifecycle_lock_v1(p_commitment_id,null);
  select * into g from app.performance_lifecycle_grants where request_id=p_request_id;
  if found then
    if (g.commitment_id,g.operator_id,g.scope,g.expires_at) is distinct from (c.id,p_operator_id,p_scope,p_expires_at) then
      raise exception 'performance_lifecycle_request_conflict' using errcode='22023'; end if;
    return g.id;
  end if;
  t:=clock_timestamp();
  if p_request_id is null or p_operator_id is null or p_operator_id=c.actor_id or p_scope is null or p_scope not in ('review','support') then
    raise exception 'performance_lifecycle_invalid_operator' using errcode='22023'; end if;
  if p_expires_at is not null then
    perform app.performance_lifecycle_admit_v1();
    if not app.is_active_actor(p_operator_id) or app.is_blocked_either_way(c.actor_id,p_operator_id)
      or not isfinite(p_expires_at) or p_expires_at<=t or p_expires_at>t+interval '168 hours'
      or (p_scope='review' and (not app.is_active_actor(c.actor_id) or c.status<>'open'
        or exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id)))
      or (p_scope='support' and not exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id)) then
      raise exception 'performance_lifecycle_operator_unavailable' using errcode='42501'; end if;
  end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_retention(commitment_id) values(c.id) on conflict do nothing;
  insert into app.performance_lifecycle_grants(request_id,commitment_id,operator_id,scope,enabled,expires_at,recorded_at)
    values(p_request_id,c.id,p_operator_id,p_scope,p_expires_at is not null,p_expires_at,t) returning id into v_id;
  insert into app.performance_lifecycle_audit(commitment_id,actor_id,operation,grant_id)
    values(c.id,p_operator_id,case when p_expires_at is null then 'grant_off' else 'grant_on' end,v_id);
  return v_id;
end; $$;
-- Call only after lifecycle locks; authorization always uses real server time,
-- including tests with an injected historical evaluation clock.
create function app.performance_lifecycle_operator_v1(c app.performance_commitment_agreements,p_scope text) returns bigint
language plpgsql set search_path='' as $$ declare g app.performance_lifecycle_grants; begin
  perform app.performance_commitment_lock_actor_v1(); perform app.performance_lifecycle_admit_v1();
  select * into g from app.performance_lifecycle_grants where commitment_id=c.id and operator_id=auth.uid() and scope=p_scope order by id desc limit 1;
  if auth.uid()=c.actor_id or g.id is null or not g.enabled or g.expires_at<=clock_timestamp()
    or app.is_blocked_either_way(c.actor_id,auth.uid())
    or (p_scope='review' and (not app.is_active_actor(c.actor_id) or c.status<>'open'
      or exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id)))
    or (p_scope='support' and not exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id)) then
    raise exception 'performance_lifecycle_operator_required' using errcode='42501'; end if;
  return g.id;
end; $$;
create function public.read_commitment_lifecycle_operator_v1(p_commitment_id uuid,p_scope text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g bigint;
begin
  c:=app.performance_lifecycle_lock_v1(p_commitment_id,auth.uid()); g:=app.performance_lifecycle_operator_v1(c,p_scope);
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_audit(commitment_id,actor_id,operation,grant_id)
    values(c.id,auth.uid(),case when p_scope='review' then 'review_read' else 'support_read' end,g);
  return jsonb_build_object('snapshot',app.performance_lifecycle_snapshot_v1(c,clock_timestamp()),
    'cases',coalesce((select jsonb_agg(to_jsonb(k) order by k.recorded_at,k.id) from app.performance_lifecycle_cases k where commitment_id=c.id),'[]'::jsonb),
    'support',case when p_scope='support' then coalesce((select jsonb_agg(to_jsonb(s)-array['operator_id','grant_id'] order by s.recorded_at,s.id)
      from app.performance_lifecycle_support s where commitment_id=c.id),'[]'::jsonb) else '[]'::jsonb end);
end; $$;
create function app.performance_lifecycle_resolve_at_v1(p_request_id uuid,p_case_id uuid,p_decision text,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; k app.performance_lifecycle_cases; g bigint; t timestamptz; p jsonb; r jsonb;
begin
  select * into k from app.performance_lifecycle_cases where id=p_case_id;
  c:=app.performance_lifecycle_lock_v1(k.commitment_id,auth.uid()); g:=app.performance_lifecycle_operator_v1(c,'review');
  p:=jsonb_build_object('operation','resolve_review','case_id',p_case_id,'decision',p_decision);
  r:=app.performance_lifecycle_recover_v1(p_request_id,p); if r is not null then return r; end if;
  t:=app.performance_lifecycle_clock_v1(c,p_now);
  if p_decision is null or p_decision not in ('uphold','inconclusive') then
    raise exception 'performance_lifecycle_invalid_resolution' using errcode='22023'; end if;
  if t<k.recorded_at or t>=k.recorded_at+interval '168 hours' or t>=(c.terms->>'finality_due_at')::timestamptz
    or c.status<>'open' or exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id) then
    raise exception 'performance_review_resolution_closed' using errcode='55000'; end if;
  if not exists(select 1 from app.performance_lifecycle_audit where commitment_id=c.id and actor_id=auth.uid()
    and grant_id=g and operation='review_read' and recorded_at>=k.recorded_at) then
    raise exception 'performance_review_read_required' using errcode='42501'; end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_resolutions values(k.id,auth.uid(),g,p_decision,t);
  return app.performance_lifecycle_save_v1(p_request_id,c.id,p,jsonb_build_object('case_id',k.id,'decision',p_decision,'recorded_at',t));
end; $$;
create function public.resolve_commitment_review_v1(p_request_id uuid,p_case_id uuid,p_decision text) returns jsonb
language sql security definer set search_path='' as $$select app.performance_lifecycle_resolve_at_v1(p_request_id,p_case_id,p_decision)$$;

-- Audited post-final intake is a support note, never new qualifying proof.
create function public.submit_commitment_support_correction_v1(p_request_id uuid,p_commitment_id uuid,p_category text,p_note text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g bigint; p jsonb; r jsonb; t timestamptz; v_id uuid;
begin
  c:=app.performance_lifecycle_lock_v1(p_commitment_id,auth.uid()); g:=app.performance_lifecycle_operator_v1(c,'support');
  p:=jsonb_build_object('operation','support_correction','commitment_id',c.id,'category',p_category,'note',p_note);
  r:=app.performance_lifecycle_recover_v1(p_request_id,p); if r is not null then return r; end if;
  t:=clock_timestamp();
  if not exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id and recorded_at<=t) then
    raise exception 'performance_final_result_required' using errcode='55000'; end if;
  if p_category is null or p_category not in ('result_correction','identity_correction','missing_result') or p_note is null
    or char_length(p_note) not between 1 and 500 or p_note<>btrim(p_note) or p_note ~ '[[:cntrl:]]'
    or (select count(*) from app.performance_lifecycle_support where commitment_id=c.id)>=64 then
    raise exception 'performance_lifecycle_invalid_support' using errcode='22023'; end if;
  if not exists(select 1 from app.performance_lifecycle_audit where commitment_id=c.id and actor_id=auth.uid()
    and grant_id=g and operation='support_read') then raise exception 'performance_support_read_required' using errcode='42501'; end if;
  perform set_config('app.performance_lifecycle_write_v1','on',true);
  insert into app.performance_lifecycle_support(commitment_id,operator_id,grant_id,category,note,recorded_at)
    values(c.id,auth.uid(),g,p_category,p_note,t) returning id into v_id;
  return app.performance_lifecycle_save_v1(p_request_id,c.id,p,jsonb_build_object('support_id',v_id,'recorded_at',t));
end; $$;

-- Owner projection: no bibs, source documents, reviewer identity, grants or requests.
create function public.get_commitment_lifecycle_v1(p_commitment_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; t timestamptz;
begin
  c:=app.performance_lifecycle_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_lifecycle_unavailable' using errcode='42501'; end if;
  t:=clock_timestamp();
  return jsonb_build_object('commitment_id',c.id,'server_now',t,
    'activation',(select recorded_at from app.performance_lifecycle_activations where commitment_id=c.id),
    'closure',case when c.closed_at is null then null else jsonb_build_object('reason',c.close_reason,'recorded_at',c.closed_at) end,
    'notices',coalesce((select jsonb_agg(jsonb_build_object('proof_revision',n.proof_revision,'recorded_at',n.recorded_at,
      'outcome',n.outcome,'dispute_closes_at',n.recorded_at+interval '168 hours',
      'can_file_review',c.status='open' and t>=n.recorded_at and t<n.recorded_at+interval '168 hours'
        and t<(c.terms->>'finality_due_at')::timestamptz
        and not exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id)
        and not exists(select 1 from app.performance_lifecycle_cases where commitment_id=c.id and proof_revision=n.proof_revision))
      order by n.proof_revision) from app.performance_lifecycle_notices n where commitment_id=c.id),'[]'::jsonb),
    'reviews',coalesce((select jsonb_agg(jsonb_build_object('case_id',k.id,'proof_revision',k.proof_revision,'reason',k.reason,
      'filed_at',k.recorded_at,'review_due_at',k.recorded_at+interval '168 hours',
      'resolution',case when r.case_id is null then null else jsonb_build_object('decision',r.decision,'recorded_at',r.recorded_at) end)
      order by k.recorded_at,k.id) from app.performance_lifecycle_cases k left join app.performance_lifecycle_resolutions r on r.case_id=k.id
      where k.commitment_id=c.id),'[]'::jsonb),
    'final_result',(select result from app.performance_lifecycle_results where commitment_id=c.id),
    'simulation',(select to_jsonb(s) from app.performance_lifecycle_settlements s where commitment_id=c.id),
    'support_receipts',coalesce((select jsonb_agg(jsonb_build_object('support_id',s.id,'category',s.category,'recorded_at',s.recorded_at)
      order by s.recorded_at,s.id) from app.performance_lifecycle_support s where commitment_id=c.id),'[]'::jsonb));
end; $$;

-- Existing exact attempts still recover before INSERT. New writes cannot change
-- a final proof set; closed agreement history retains its earlier safe exits.
create function app.performance_lifecycle_proof_open_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if exists(select 1 from app.performance_lifecycle_results where commitment_id=new.commitment_id) then
    raise exception 'performance_result_closed_use_support' using errcode='55000'; end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['nominations','confirmations','sources','revisions'] loop
    execute format('create trigger performance_lifecycle_proof_open before insert on app.performance_attempt_%I
      for each row execute function app.performance_lifecycle_proof_open_v1()',t);
  end loop;
end; $$;
create function app.performance_lifecycle_agreement_open_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if exists(select 1 from app.performance_lifecycle_results where commitment_id=old.id) then
    raise exception 'performance_result_closed_use_support' using errcode='55000'; end if;
  return new;
end; $$;
create trigger performance_lifecycle_agreement_open before update on app.performance_commitment_agreements
  for each row execute function app.performance_lifecycle_agreement_open_v1();

-- Permit slot release only at the historical exit or the immutable final receipt.
create or replace function app.performance_commitment_check_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; v_id uuid;
begin
  v_id:=case when tg_table_name='performance_commitment_agreements' then to_jsonb(new)->>'id'
    else to_jsonb(new)->>'commitment_id' end;
  select * into strict c from app.performance_commitment_agreements where id=v_id;
  if c.terms is distinct from app.performance_commitment_terms_v1(c.actor_id,c.target_seconds,c.starts_at,c.deadline_at,c.display_timezone,c.policy_version)
    or not exists(select 1 from app.performance_commitment_consents s where s.commitment_id=c.id
      and s.actor_id=c.actor_id and s.accepted_at=c.created_at and s.policy_version=c.policy_version and s.terms_digest=c.terms_digest)
    or not exists(select 1 from app.performance_commitment_enrollments e where e.commitment_id=c.id
      and e.actor_id=c.actor_id and e.reserved_at=c.created_at
      and e.released_at is not distinct from coalesce(c.closed_at,(select recorded_at from app.performance_lifecycle_results where commitment_id=c.id))) then
    raise exception 'performance_commitment_aggregate_invariant' using errcode='23514'; end if;
  return null;
end; $$;
create or replace function app.resolve_performance_commitments_on_deletion_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements;
begin
  if old.deleted_at is not null or new.deleted_at is null then return new; end if;
  if not exists(select 1 from app.account_deletion_transactions where transaction_id=txid_current()
    and backend_pid=pg_backend_pid() and actor_id=new.id) then
    raise exception 'performance_commitment_deletion_requires_rpc' using errcode='42501'; end if;
  for c in select * from app.performance_commitment_agreements a where actor_id=new.id and closed_at is null
    and not exists(select 1 from app.performance_lifecycle_results r where r.commitment_id=a.id) order by id for update loop
    perform app.performance_commitment_close_v1(c.id,'account_deleted',new.deleted_at);
  end loop;
  perform set_config('app.performance_commitment_write_v1','on',true);
  delete from app.performance_commitment_beta_allowlist where actor_id=new.id;
  return new;
end; $$;

-- Explicit function allowlist; private clock seams are never client/service RPCs.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and (p.proname like '%performance_lifecycle%v1' or p.proname like '%commitment_lifecycle%v1'
      or p.proname in ('file_commitment_review_v1','resolve_commitment_review_v1','settle_commitment_simulation_v1','submit_commitment_support_correction_v1')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.get_commitment_lifecycle_v1(uuid),public.file_commitment_review_v1(uuid,uuid,integer,text),
  public.resolve_commitment_review_v1(uuid,uuid,text),public.read_commitment_lifecycle_operator_v1(uuid,text),
  public.submit_commitment_support_correction_v1(uuid,uuid,text,text) to authenticated;
grant execute on function public.set_commitment_lifecycle_enabled_v1(boolean),public.load_commitment_lifecycle_v1(uuid),
  public.commit_commitment_lifecycle_v1(jsonb,jsonb),public.settle_commitment_simulation_v1(uuid),
  public.set_commitment_lifecycle_operator_v1(uuid,uuid,uuid,text,timestamptz) to service_role;

-- Reuse the existing attempt admission seam so old grants cannot read private
-- proof after finality; committed exact attempt receipts retain their meaning.
create or replace function app.performance_attempt_open_v1(c app.performance_commitment_agreements) returns void
language plpgsql set search_path='' as $$ begin
  if c.status<>'open' or not app.is_active_actor(c.actor_id)
    or not (select enabled from app.performance_attempt_runtime where singleton) then
    raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  if exists(select 1 from app.performance_lifecycle_results where commitment_id=c.id) then
    raise exception 'performance_result_closed_use_support' using errcode='55000'; end if;
end; $$;

create function app.performance_lifecycle_follow_open_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if new.status in ('pending','active') and exists(select 1 from app.performance_lifecycle_results where commitment_id=new.commitment_id) then
    raise exception 'performance_result_closed_use_support' using errcode='55000'; end if;
  return new;
end; $$;
create trigger performance_lifecycle_follow_open before insert or update on app.performance_following_grants
  for each row execute function app.performance_lifecycle_follow_open_v1();
create trigger performance_lifecycle_progress_open before insert on app.performance_progress_entries
  for each row execute function app.performance_lifecycle_proof_open_v1();
create trigger performance_lifecycle_publication_open before insert on app.performance_following_publications
  for each row execute function app.performance_lifecycle_proof_open_v1();
revoke all on function app.performance_lifecycle_follow_open_v1() from public,anon,authenticated,service_role;
