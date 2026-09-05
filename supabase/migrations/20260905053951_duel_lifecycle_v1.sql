-- Phase 2(c). Local fictional simulation only. No scheduler or external delivery.
-- Agreement status remains its Phase 1 receipt; operational facts live separately.
create table app.duel_lifecycle_runtime (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false
);
insert into app.duel_lifecycle_runtime values(true,false);
create table app.duel_lifecycle_gate_events (
  id bigint generated always as identity primary key,
  enabled boolean not null, recorded_at timestamptz not null,
  authority text not null check(authority in ('postgres','service_role'))
);
create table app.duel_lifecycle_activations (
  challenge_id uuid primary key references public.duel_challenges(id),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
create table app.duel_lifecycle_notices (
  challenge_id uuid not null references public.duel_challenges(id),
  proof_revision integer not null check(proof_revision>=0),
  actor_id uuid not null,
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  outcome jsonb not null,
  primary key(challenge_id,proof_revision,actor_id),
  foreign key(challenge_id,actor_id) references public.duel_participants(challenge_id,actor_id)
);
create index duel_lifecycle_notice_actor_idx on app.duel_lifecycle_notices(actor_id);
create table app.duel_lifecycle_cases (
  id uuid primary key,
  challenge_id uuid not null,
  proof_revision integer not null,
  actor_id uuid not null,
  request_id uuid not null,
  reason text not null check(reason in ('wrong_result','wrong_identity','missing_result')),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  unique(actor_id,request_id),
  unique(challenge_id,proof_revision,actor_id),
  foreign key(challenge_id,proof_revision,actor_id)
    references app.duel_lifecycle_notices(challenge_id,proof_revision,actor_id)
);
create table app.duel_lifecycle_resolutions (
  case_id uuid primary key references app.duel_lifecycle_cases(id),
  reviewer_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.duel_proof_grants(id),
  request_id uuid not null,
  decision text not null check(decision in ('uphold','void')),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  unique(reviewer_id,request_id)
);
create index duel_lifecycle_resolution_grant_idx on app.duel_lifecycle_resolutions(grant_id);
create table app.duel_lifecycle_closures (
  challenge_id uuid primary key references public.duel_challenges(id),
  actor_id uuid references public.profiles(id),
  request_id uuid not null unique,
  kind text not null check(kind in ('withdrawal','injury','event_cancelled')),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  check((kind='event_cancelled')=(actor_id is null))
);
create index duel_lifecycle_closure_actor_idx on app.duel_lifecycle_closures(actor_id);
create table app.duel_lifecycle_results (
  challenge_id uuid primary key references public.duel_challenges(id),
  result jsonb not null check(jsonb_typeof(result)='object'),
  input_digest text not null check(length(input_digest)=64),
  recorded_at timestamptz not null check(isfinite(recorded_at))
);
-- Nonredeemable cents are a simulation accounting unit, never a balance or debt.
create table app.duel_lifecycle_settlements (
  challenge_id uuid primary key references app.duel_lifecycle_results(challenge_id),
  creator_cents integer not null check(creator_cents in (0,2000,4000)),
  invitee_cents integer not null check(invitee_cents in (0,2000,4000)),
  fee_cents integer not null default 0 check(fee_cents=0),
  mode text not null default 'simulated' check(mode='simulated'),
  redeemable boolean not null default false check(not redeemable),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  check(creator_cents+invitee_cents+fee_cents=4000)
);
create table app.duel_lifecycle_support (
  id uuid primary key,
  challenge_id uuid not null references app.duel_lifecycle_results(challenge_id),
  reviewer_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.duel_proof_grants(id),
  request_id uuid not null,
  document jsonb not null,
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  unique(reviewer_id,request_id)
);
create index duel_lifecycle_support_challenge_idx on app.duel_lifecycle_support(challenge_id);
create index duel_lifecycle_support_grant_idx on app.duel_lifecycle_support(grant_id);

create function app.duel_lifecycle_guard_v1() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
    or coalesce(current_setting('app.duel_lifecycle_write_v1',true),'')<>'on' then
    raise exception 'duel_lifecycle_write_requires_rpc' using errcode='42501';
  end if;
  if tg_op<>'INSERT' and not(tg_op='UPDATE' and tg_table_name='duel_lifecycle_runtime') then
    raise exception 'duel_lifecycle_append_only' using errcode='23001';
  end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['runtime','gate_events','activations','notices','cases','resolutions','closures','results','settlements','support'] loop
    execute format('alter table app.duel_lifecycle_%I enable row level security',t);
    execute format('revoke all on app.duel_lifecycle_%I from public,anon,authenticated,service_role',t);
    execute format('create trigger lifecycle_guard before insert or update or delete on app.duel_lifecycle_%I
      for each row execute function app.duel_lifecycle_guard_v1()',t);
    execute format('create trigger lifecycle_no_truncate before truncate on app.duel_lifecycle_%I
      for each statement execute function app.duel_lifecycle_guard_v1()',t);
  end loop;
end; $$;
revoke all on sequence app.duel_lifecycle_gate_events_id_seq from public,anon,authenticated,service_role;

create function public.set_duel_lifecycle_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'duel_lifecycle_invalid_gate' using errcode='22023'; end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  update app.duel_lifecycle_runtime set enabled=p_enabled where singleton;
  insert into app.duel_lifecycle_gate_events(enabled,recorded_at,authority)
    values(p_enabled,clock_timestamp(),app.duel_proof_authority_v1());
  return p_enabled;
end; $$;
create function app.duel_lifecycle_admit_v1() returns void
language plpgsql set search_path='' as $$
begin
  perform 1 from app.duel_lifecycle_runtime where singleton and enabled for share;
  if not found then raise exception 'duel_lifecycle_disabled' using errcode='42501'; end if;
end; $$;
create function app.duel_lifecycle_clock_v1(c public.duel_challenges,p_now timestamptz) returns timestamptz
language plpgsql set search_path='' as $$
declare t timestamptz:=coalesce(p_now,clock_timestamp());
begin
  if not isfinite(t) or t<c.created_at then raise exception 'duel_invalid_clock' using errcode='22023'; end if;
  return t;
end; $$;

-- Private complete snapshot. Call only under actor-then-challenge locks.
-- Include agreement closure, deletion tombstones, every case and resolution.
create function app.duel_lifecycle_snapshot_v1(c public.duel_challenges,p_now timestamptz) returns jsonb
language sql stable set search_path='' set timezone='UTC' as $$
  select jsonb_build_object(
    'agreement',to_jsonb(c)||jsonb_build_object('participants',
      (select jsonb_agg(to_jsonb(p) order by p.actor_id) from public.duel_participants p where challenge_id=c.id)),
    'now',p_now,'proofRevisions',app.duel_proof_history_v1(c.id),
    'notices',(select coalesce(jsonb_agg(jsonb_build_object('proofRevision',proof_revision,'actorId',actor_id,
      'recordedAt',recorded_at) order by proof_revision,actor_id),'[]'::jsonb) from app.duel_lifecycle_notices where challenge_id=c.id),
    'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'proofRevision',k.proof_revision,
      'filedBy',k.actor_id,'filedAt',k.recorded_at,'resolution',case when r.case_id is null then null else
        jsonb_build_object('reviewerId',r.reviewer_id,'decidedAt',r.recorded_at,'decision',r.decision) end)
      order by k.recorded_at,k.id),'[]'::jsonb) from app.duel_lifecycle_cases k
      left join app.duel_lifecycle_resolutions r on r.case_id=k.id where k.challenge_id=c.id),
    'closure',(select jsonb_build_object('kind',kind,'actorId',actor_id,'recordedAt',at) from (
      select kind,actor_id,recorded_at at from app.duel_lifecycle_closures where challenge_id=c.id
      union all select 'account_deleted',id,deleted_at from public.profiles
        where id in (c.creator_id,c.invitee_id) and deleted_at is not null
      union all select case when c.close_reason='account_deleted' then 'account_deleted' else 'withdrawal' end,
        case when c.close_reason='participant_cancelled' then c.invitee_id else c.creator_id end,c.closed_at
        where c.closed_at is not null and c.close_reason<>'account_deleted'
      ) exits order by at,kind,actor_id limit 1),
    'finalResult',(select result from app.duel_lifecycle_results where challenge_id=c.id));
$$;

create function app.duel_lifecycle_load_at_v1(p_challenge_id uuid,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; t timestamptz;
begin
  perform app.duel_require_service_v1();
  c:=app.duel_proof_lock_v1(p_challenge_id,null);
  perform app.duel_lifecycle_admit_v1();
  t:=app.duel_lifecycle_clock_v1(c,p_now);
  if c.status='invited' and t>=c.accept_by then
    perform app.duel_close_v1(c.id,'expired','acceptance_expired',t);
    return null;
  end if;
  if (select count(*) from public.duel_participants where challenge_id=c.id and accepted_at is not null)<>2 then
    return null;
  end if;
  if c.closed_at is null and t>=c.starts_at and not exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
    perform set_config('app.duel_lifecycle_write_v1','on',true);
    insert into app.duel_lifecycle_activations values(c.id,t) on conflict do nothing;
  end if;
  return app.duel_lifecycle_snapshot_v1(c,t);
end; $$;
create function public.load_duel_lifecycle_v1(p_challenge_id uuid) returns jsonb
language sql security definer set search_path='' as $$select app.duel_lifecycle_load_at_v1(p_challenge_id)$$;

-- New source/revision admission stops at persisted finality; exact committed
-- proof retries still recover before INSERT. Existing proof functions unchanged.
create function app.duel_lifecycle_proof_open_v1() returns trigger
language plpgsql set search_path='' as $$
begin
  if exists(select 1 from app.duel_lifecycle_results where challenge_id=new.challenge_id)
    or exists(select 1 from app.duel_lifecycle_closures where challenge_id=new.challenge_id) then
    raise exception 'duel_result_closed_use_support' using errcode='55000';
  end if;
  return new;
end; $$;
create trigger lifecycle_proof_open before insert on app.duel_proof_sources
  for each row execute function app.duel_lifecycle_proof_open_v1();
create trigger lifecycle_proof_open before insert on app.duel_proof_revisions
  for each row execute function app.duel_lifecycle_proof_open_v1();

-- Complete input comparison prevents lost corrections, notices, cases, exits,
-- deletions and double finalization. No transaction crosses the evaluator call.
create function app.duel_lifecycle_commit_at_v1(p_input jsonb,p_decision jsonb,p_now timestamptz default null)
returns text language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; t timestamptz; evaluated timestamptz; current_input jsonb;
  phase text:=p_decision->>'phase'; rev integer; outcome jsonb:=p_decision->'outcome'; boundary timestamptz;
begin
  perform app.duel_require_service_v1();
  c:=app.duel_proof_lock_v1((p_input->'agreement'->>'id')::uuid,null);
  perform app.duel_lifecycle_admit_v1();
  t:=app.duel_lifecycle_clock_v1(c,p_now); evaluated:=(p_input->>'now')::timestamptz;
  if evaluated is null or not isfinite(evaluated) or evaluated>t then
    raise exception 'duel_invalid_clock' using errcode='22023';
  end if;
  current_input:=app.duel_lifecycle_snapshot_v1(c,evaluated);
  if current_input is distinct from p_input then return 'stale'; end if;
  -- Re-evaluate if a clock boundary passed while outside the database.
  for boundary in select unnest(array[c.starts_at,(c.terms->'event'->>'ends_at')::timestamptz,
    (c.terms->>'results_due_at')::timestamptz,(c.terms->>'finality_due_at')::timestamptz])
    union all select recorded_at+interval '168 hours' from app.duel_lifecycle_notices where challenge_id=c.id
    union all select recorded_at+interval '168 hours' from app.duel_lifecycle_cases where challenge_id=c.id loop
    if evaluated<boundary and t>=boundary then return 'stale'; end if;
  end loop;
  if not app.duel_proof_keys_v1(p_decision,array['version','challengeId','termsDigest','proofRevision','phase',
      'outcome','disputeClosesAt','reviewDueAt','supportCorrectionRequired'])
    or p_decision->>'version' is distinct from 'duel-fixture-official-5k-v1'
    or p_decision->>'challengeId' is distinct from c.id::text
    or p_decision->>'termsDigest' is distinct from c.terms_digest
    or phase is null or phase not in ('scheduled','active','awaiting_proof','provisional','ready_to_finalize','final') then
    raise exception 'duel_lifecycle_invalid_decision' using errcode='22023';
  end if;
  rev:=(p_decision->>'proofRevision')::integer;
  if rev is null or rev<0 or rev>(select count(*) from app.duel_proof_revisions where challenge_id=c.id) then
    raise exception 'duel_lifecycle_invalid_decision' using errcode='22023';
  end if;
  if current_input->'finalResult'<>'null'::jsonb then return 'final'; end if;
  if phase in ('provisional','ready_to_finalize') then
    if outcome->>'kind' is null or not (
      (app.duel_proof_keys_v1(outcome,array['kind','reason','winnerId']) and outcome->>'kind'='winner'
        and outcome->>'winnerId' in (c.creator_id::text,c.invitee_id::text) and outcome->>'reason' in ('faster_chip','only_finisher'))
      or (app.duel_proof_keys_v1(outcome,array['kind','reason']) and (
        (outcome->>'kind'='tie' and outcome->>'reason'='equal_chip_seconds') or
        (outcome->>'kind'='withdrawn_no_contest' and outcome->>'reason'='participant_withdrew') or
        (outcome->>'kind'='void' and outcome->>'reason' in ('both_nonfinish','unresolved_proof','prestart_withdrawal',
          'injury','event_cancelled','account_deleted','review_void','review_timeout','finality_timeout'))))) then
      raise exception 'duel_lifecycle_invalid_outcome' using errcode='22023';
    end if;
  end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  if phase='provisional' then
    if t>=(c.terms->>'finality_due_at')::timestamptz then return 'stale'; end if;
    insert into app.duel_lifecycle_notices(challenge_id,proof_revision,actor_id,recorded_at,outcome)
      select c.id,rev,actor_id,t,outcome from public.duel_participants where challenge_id=c.id
      on conflict do nothing;
    return 'provisional';
  elsif phase='ready_to_finalize' then
    insert into app.duel_lifecycle_results values(c.id,jsonb_build_object('version',p_decision->'version',
      'challengeId',c.id,'termsDigest',c.terms_digest,'proofRevision',rev,'finalizedAt',t,'outcome',outcome),
      encode(extensions.digest(p_input::text,'sha256'),'hex'),t);
    perform set_config('app.duel_write_v1','on',true);
    update app.duel_enrollments set released_at=t where challenge_id=c.id and released_at is null;
    return 'final';
  end if;
  return phase;
end; $$;
create function public.commit_duel_lifecycle_v1(p_input jsonb,p_decision jsonb) returns text
language sql security definer set search_path='' as $$ select app.duel_lifecycle_commit_at_v1(p_input,p_decision) $$;

create function app.duel_lifecycle_settle_at_v1(p_challenge_id uuid,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; r app.duel_lifecycle_results; s app.duel_lifecycle_settlements; t timestamptz;
  left_cents integer:=2000; right_cents integer:=2000;
begin
  perform app.duel_require_service_v1();
  c:=app.duel_proof_lock_v1(p_challenge_id,null);
  select * into s from app.duel_lifecycle_settlements where challenge_id=c.id;
  if found then return to_jsonb(s); end if;
  perform app.duel_lifecycle_admit_v1();
  t:=app.duel_lifecycle_clock_v1(c,p_now);
  select * into r from app.duel_lifecycle_results where challenge_id=c.id;
  if not found or t<r.recorded_at then raise exception 'duel_final_result_required' using errcode='55000'; end if;
  if r.result->'outcome'->>'kind'='winner' then
    left_cents:=case when r.result->'outcome'->>'winnerId'=c.creator_id::text then 4000 else 0 end;
    right_cents:=4000-left_cents;
  end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  insert into app.duel_lifecycle_settlements(challenge_id,creator_cents,invitee_cents,recorded_at)
    values(c.id,left_cents,right_cents,t) returning * into s;
  return to_jsonb(s);
end; $$;
create function public.settle_duel_simulation_v1(p_challenge_id uuid) returns jsonb
language sql security definer set search_path='' as $$select app.duel_lifecycle_settle_at_v1(p_challenge_id)$$;

create function app.duel_lifecycle_case_at_v1(p_request_id uuid,p_challenge_id uuid,p_revision integer,
  p_reason text,p_now timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; a uuid; k app.duel_lifecycle_cases; t timestamptz;
  notice_at timestamptz; deadline timestamptz; n integer;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  a:=app.duel_proof_require_session_v1();
  if a not in (c.creator_id,c.invitee_id) then raise exception 'duel_unavailable' using errcode='42501'; end if;
  -- Own receipt and safe review remain available when the pair is blocked/deleted.
  select * into k from app.duel_lifecycle_cases where actor_id=a and request_id=p_request_id;
  if found then
    if (k.challenge_id,k.proof_revision,k.reason) is distinct from (c.id,p_revision,p_reason) then
      raise exception 'duel_lifecycle_request_conflict' using errcode='22023'; end if;
    return k.id;
  end if;
  t:=app.duel_lifecycle_clock_v1(c,p_now);
  if p_request_id is null or p_reason is null or p_reason not in ('wrong_result','wrong_identity','missing_result') then
    raise exception 'duel_lifecycle_invalid_case' using errcode='22023'; end if;
  select recorded_at into notice_at from app.duel_lifecycle_notices
    where challenge_id=c.id and proof_revision=p_revision and actor_id=a;
  select count(*),max(recorded_at)+interval '168 hours' into n,deadline from app.duel_lifecycle_notices
    where challenge_id=c.id and proof_revision=p_revision;
  if notice_at is null or t<notice_at or (n=2 and t>=deadline)
    or t>=(c.terms->>'finality_due_at')::timestamptz
    or exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
    raise exception 'duel_review_window_closed' using errcode='55000'; end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  insert into app.duel_lifecycle_cases(id,challenge_id,proof_revision,actor_id,request_id,reason,recorded_at)
    values(extensions.gen_random_uuid(),c.id,p_revision,a,p_request_id,p_reason,t) returning id into k.id;
  return k.id;
end; $$;
create function public.file_duel_review_v1(p_request_id uuid,p_challenge_id uuid,p_revision integer,p_reason text)
returns uuid language sql security definer set search_path='' as $$
  select app.duel_lifecycle_case_at_v1(p_request_id,p_challenge_id,p_revision,p_reason) $$;

create function app.duel_lifecycle_resolve_at_v1(p_request_id uuid,p_case_id uuid,p_decision text,
  p_now timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; k app.duel_lifecycle_cases; r app.duel_lifecycle_resolutions; g bigint; t timestamptz;
begin
  select * into k from app.duel_lifecycle_cases where id=p_case_id;
  if not found then raise exception 'duel_unavailable' using errcode='42501'; end if;
  c:=app.duel_proof_lock_v1(k.challenge_id,auth.uid());
  g:=app.duel_proof_require_reviewer_v1(c);
  select * into r from app.duel_lifecycle_resolutions where reviewer_id=auth.uid() and request_id=p_request_id;
  if found then
    if (r.case_id,r.decision) is distinct from (p_case_id,p_decision) then
      raise exception 'duel_lifecycle_request_conflict' using errcode='22023'; end if;
    return r.case_id;
  end if;
  perform app.duel_lifecycle_admit_v1();
  perform app.duel_proof_require_session_v1();
  t:=app.duel_lifecycle_clock_v1(c,p_now);
  if p_request_id is null or p_decision is null or p_decision not in ('uphold','void') then
    raise exception 'duel_lifecycle_invalid_resolution' using errcode='22023'; end if;
  if t<k.recorded_at or t>=k.recorded_at+interval '168 hours'
    or t>=(c.terms->>'finality_due_at')::timestamptz
    or exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
    raise exception 'duel_review_resolution_closed' using errcode='55000'; end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  insert into app.duel_lifecycle_resolutions values(k.id,auth.uid(),g,p_request_id,p_decision,t);
  return k.id;
end; $$;
create function public.resolve_duel_review_v1(p_request_id uuid,p_case_id uuid,p_decision text) returns uuid
language sql security definer set search_path='' as $$select app.duel_lifecycle_resolve_at_v1(p_request_id,p_case_id,p_decision)$$;

create function app.duel_lifecycle_exit_at_v1(p_request_id uuid,p_challenge_id uuid,p_kind text,
  p_now timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; a uuid; old app.duel_lifecycle_closures; t timestamptz;
begin
  if p_kind='event_cancelled' then perform app.duel_require_service_v1(); a:=null;
  else a:=auth.uid(); end if;
  c:=app.duel_proof_lock_v1(p_challenge_id,a);
  if p_kind<>'event_cancelled' then
    a:=app.duel_proof_require_session_v1();
    if a not in (c.creator_id,c.invitee_id) then raise exception 'duel_unavailable' using errcode='42501'; end if;
  end if;
  select * into old from app.duel_lifecycle_closures where request_id=p_request_id;
  if found then
    if (old.challenge_id,old.actor_id,old.kind) is distinct from (c.id,a,p_kind) then
      raise exception 'duel_lifecycle_request_conflict' using errcode='22023'; end if;
    return c.id;
  end if;
  if p_request_id is null or p_kind is null or p_kind not in ('withdrawal','injury','event_cancelled') then
    raise exception 'duel_lifecycle_invalid_exit' using errcode='22023'; end if;
  t:=app.duel_lifecycle_clock_v1(c,p_now);
  if (select count(*) from public.duel_participants where challenge_id=c.id and accepted_at is not null)<>2
    or c.closed_at is not null or exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id)
    or t>=(c.terms->>'finality_due_at')::timestamptz then
    raise exception 'duel_exit_closed' using errcode='55000'; end if;
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  insert into app.duel_lifecycle_closures values(c.id,a,p_request_id,p_kind,t);
  return c.id;
end; $$;
create function public.exit_duel_v1(p_request_id uuid,p_challenge_id uuid,p_kind text) returns uuid
language plpgsql security definer set search_path='' as $$
begin
  if p_kind is null or p_kind not in ('withdrawal','injury') then
    raise exception 'duel_lifecycle_invalid_exit' using errcode='22023'; end if;
  return app.duel_lifecycle_exit_at_v1(p_request_id,p_challenge_id,p_kind);
end; $$;
create function public.cancel_duel_event_v1(p_request_id uuid,p_challenge_id uuid) returns uuid
language sql security definer set search_path='' as $$select app.duel_lifecycle_exit_at_v1(p_request_id,p_challenge_id,'event_cancelled')$$;

-- Audited independent operator intake; a separate append after finality.
-- Deliberately never calls proof ingestion, evaluation, settlement or enrollment.
create function public.submit_duel_support_correction_v1(p_request_id uuid,p_challenge_id uuid,p_document jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; g bigint; s app.duel_lifecycle_support;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  g:=app.duel_proof_require_reviewer_v1(c);
  select * into s from app.duel_lifecycle_support where reviewer_id=auth.uid() and request_id=p_request_id;
  if found then
    if (s.challenge_id,s.document) is distinct from (c.id,p_document) then
      raise exception 'duel_lifecycle_request_conflict' using errcode='22023'; end if;
    return s.id;
  end if;
  if p_request_id is null or not exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
    raise exception 'duel_final_result_required' using errcode='55000'; end if;
  perform app.duel_proof_validate_source_v1(c,p_document);
  perform set_config('app.duel_lifecycle_write_v1','on',true);
  insert into app.duel_lifecycle_support values(extensions.gen_random_uuid(),c.id,auth.uid(),g,p_request_id,p_document,clock_timestamp())
    returning id into s.id;
  return s.id;
end; $$;

-- Only allow a released slot for a persisted final result or a historical exit.
-- Preserve the rest of Phase 1's deferred aggregate check verbatim.
create or replace function app.duel_check_aggregate_v1() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.duel_challenges; v_id uuid;
begin
  if tg_table_name = 'duel_challenges' then v_id := new.id;
  else v_id := new.challenge_id; end if;
  select * into strict c from public.duel_challenges where id = v_id;
  if (select count(*) from public.duel_participants where challenge_id = c.id) <> 2
     or exists (select 1 from public.duel_participants p where p.challenge_id = c.id and (
       p.actor_id <> case p.role when 'creator' then c.creator_id else c.invitee_id end
       or (p.accepted_at is not null and (
         p.consent_policy_version <> c.policy_version or p.consent_terms_digest <> c.terms_digest
         or p.accepted_at < c.created_at or p.accepted_at >= c.accept_by))
       or (p.role = 'creator' and p.accepted_at <> c.created_at)
       or (p.role = 'invitee' and ((c.status = 'scheduled' and p.accepted_at is null)
         or (c.status in ('invited','expired','declined') and p.accepted_at is not null)
         or ((c.status = 'declined') <> (p.declined_at is not null))))
       or ((p.accepted_at is not null and c.closed_at is null and not exists (select 1 from app.duel_lifecycle_results where challenge_id=c.id)) <>
         exists (select 1 from app.duel_enrollments e where e.challenge_id = c.id
           and e.actor_id = p.actor_id and e.released_at is null))
     )) then
    raise exception 'duel_aggregate_invariant' using errcode = '23514';
  end if;
  return null;
end;
$$;

-- Gate-off recovery is private to the named active actor. Block/deletion
-- suppresses opponent results and notices, but never one's own case receipt.
create function public.get_duel_lifecycle_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; a uuid; restricted boolean;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  a:=app.duel_proof_require_session_v1();
  if a not in (c.creator_id,c.invitee_id) then raise exception 'duel_unavailable' using errcode='42501'; end if;
  restricted:=not app.is_active_actor(c.creator_id) or not app.is_active_actor(c.invitee_id)
    or app.is_blocked_either_way(c.creator_id,c.invitee_id);
  return jsonb_build_object('challengeId',c.id,'termsDigest',c.terms_digest,'contactSuppressed',restricted,
    'activatedAt',(select recorded_at from app.duel_lifecycle_activations where challenge_id=c.id),
    'notices',case when restricted then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object(
      'proofRevision',proof_revision,'recordedAt',recorded_at,'outcome',outcome,
      'disputeClosesAt',(select max(n.recorded_at)+interval '168 hours' from app.duel_lifecycle_notices n
        where n.challenge_id=c.id and n.proof_revision=x.proof_revision)) order by proof_revision),'[]'::jsonb)
      from app.duel_lifecycle_notices x where challenge_id=c.id and actor_id=a) end,
    'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'proofRevision',k.proof_revision,
      'reason',k.reason,'filedAt',k.recorded_at,'reviewDueAt',k.recorded_at+interval '168 hours',
      'decision',r.decision,'decidedAt',r.recorded_at) order by k.recorded_at,k.id),'[]'::jsonb)
      from app.duel_lifecycle_cases k left join app.duel_lifecycle_resolutions r on r.case_id=k.id
      where k.challenge_id=c.id and k.actor_id=a),
    'finalResult',case when restricted then null else (select result from app.duel_lifecycle_results where challenge_id=c.id) end,
    'simulatedReturnCents',(select case when a=c.creator_id then creator_cents else invitee_cents end
      from app.duel_lifecycle_settlements where challenge_id=c.id));
end; $$;

-- Separate operator projection, fresh independent per-duel grant required.
create function public.get_duel_review_cases_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  perform app.duel_proof_require_reviewer_v1(c);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'proofRevision',k.proof_revision,
    'filedBy',k.actor_id,'reason',k.reason,'filedAt',k.recorded_at,'reviewDueAt',k.recorded_at+interval '168 hours',
    'decision',r.decision) order by k.recorded_at,k.id),'[]'::jsonb)
    from app.duel_lifecycle_cases k left join app.duel_lifecycle_resolutions r on r.case_id=k.id where k.challenge_id=c.id);
end; $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and (p.proname like '%duel_lifecycle%v1' or p.proname in (
      'file_duel_review_v1','resolve_duel_review_v1','exit_duel_v1','cancel_duel_event_v1',
      'submit_duel_support_correction_v1','settle_duel_simulation_v1','get_duel_review_cases_v1')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.set_duel_lifecycle_enabled_v1(boolean),public.load_duel_lifecycle_v1(uuid),
  public.commit_duel_lifecycle_v1(jsonb,jsonb),public.settle_duel_simulation_v1(uuid),public.cancel_duel_event_v1(uuid,uuid)
  to service_role;
grant execute on function public.file_duel_review_v1(uuid,uuid,integer,text),public.resolve_duel_review_v1(uuid,uuid,text),
  public.exit_duel_v1(uuid,uuid,text),public.submit_duel_support_correction_v1(uuid,uuid,jsonb),
  public.get_duel_lifecycle_v1(uuid),public.get_duel_review_cases_v1(uuid) to authenticated;

-- Retried Phase 1 receipts keep their contract; new actions cannot reopen an operational exit or final result.
create or replace function app.respond_duel_at_v1(p_operation text,p_request_id uuid,p_challenge_id uuid,
  p_expected_policy_version text default null,p_expected_terms_digest text default null,
  p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a uuid := auth.uid(); c public.duel_challenges; v_payload jsonb; v_id uuid; v_now timestamptz;
begin
  select * into c from public.duel_challenges where id=p_challenge_id;
  if a is null or not found or a not in (c.creator_id,c.invitee_id) then
    raise exception 'duel_unavailable' using errcode = '42501';
  end if;
  perform app.duel_lock_pair_v1(c.creator_id,c.invitee_id);
  v_payload := jsonb_build_object('operation',p_operation,'challenge_id',p_challenge_id,
    'policy_version',p_expected_policy_version,'terms_digest',p_expected_terms_digest);
  v_id := app.duel_recover_request_v1(a,p_request_id,v_payload);
  if v_id is not null then return v_id; end if;
  if p_operation = 'accept_duel_v1' then perform app.duel_admit_pair_v1(c.creator_id,c.invitee_id); end if;
  select * into strict c from public.duel_challenges where id=p_challenge_id for update;
  v_now := coalesce(p_now,clock_timestamp());
  if not isfinite(v_now) or v_now < c.created_at then
    raise exception 'duel_invalid_clock' using errcode = '22023';
  end if;
  if exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id)
    or exists(select 1 from app.duel_lifecycle_closures where challenge_id=c.id) then
    raise exception 'duel_closed' using errcode='55000';
  end if;
  if c.closed_at is not null then raise exception 'duel_closed' using errcode = '55000'; end if;
  perform set_config('app.duel_write_v1','on',true);
  if p_operation = 'accept_duel_v1' then
    if a <> c.invitee_id then raise exception 'duel_invitee_required' using errcode = '42501'; end if;
    if c.status <> 'invited' then raise exception 'duel_already_accepted' using errcode = '55000'; end if;
    if v_now >= c.accept_by then raise exception 'duel_acceptance_expired' using errcode = '55000'; end if;
    if p_expected_policy_version is distinct from c.policy_version
       or p_expected_terms_digest is distinct from c.terms_digest then
      raise exception 'duel_consent_mismatch' using errcode = '22023';
    end if;
    perform app.duel_release_overdue_v1(a,v_now);
    if exists (select 1 from app.duel_enrollments where actor_id=a and released_at is null) then
      raise exception 'duel_slot_occupied' using errcode = '23505';
    end if;
    update public.duel_participants set accepted_at=v_now,consent_policy_version=c.policy_version,
      consent_terms_digest=c.terms_digest where challenge_id=c.id and actor_id=a;
    insert into app.duel_enrollments values(c.id,a,v_now,null);
    update public.duel_challenges set status='scheduled' where id=c.id;
  elsif p_operation = 'decline_duel_v1' then
    if a <> c.invitee_id then raise exception 'duel_invitee_required' using errcode = '42501'; end if;
    if c.status <> 'invited' or v_now >= c.accept_by then
      raise exception 'duel_invitation_unavailable' using errcode = '55000';
    end if;
    update public.duel_participants set declined_at=v_now where challenge_id=c.id and actor_id=a;
    perform app.duel_close_v1(c.id,'declined','declined',v_now);
  elsif p_operation = 'cancel_duel_v1' then
    if v_now >= c.starts_at then raise exception 'duel_already_started' using errcode = '55000'; end if;
    if a <> c.creator_id and c.status <> 'scheduled' then
      raise exception 'duel_accepted_participant_required' using errcode = '42501';
    end if;
    perform app.duel_close_v1(c.id,'cancelled',case when a=c.creator_id then 'creator_cancelled'
      else 'participant_cancelled' end,v_now);
  else raise exception 'duel_invalid_operation' using errcode = '22023';
  end if;
  insert into app.duel_requests values(a,p_request_id,v_payload,c.id,v_now);
  return c.id;
end;
$$;


-- Deletion must remain possible after an early final result.
create or replace function app.resolve_duels_on_account_deletion_v1() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.duel_challenges;
begin
  if old.deleted_at is not null or new.deleted_at is null then return new; end if;
  if not exists (select 1 from app.account_deletion_transactions where transaction_id=txid_current()
    and backend_pid=pg_backend_pid() and actor_id=new.id) then
    raise exception 'duel_deletion_requires_rpc' using errcode = '42501';
  end if;
  for c in select * from public.duel_challenges where new.id in (creator_id,invitee_id)
      and closed_at is null order by id for update loop
    if new.deleted_at < c.starts_at and not exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
      perform app.duel_close_v1(c.id,'cancelled','account_deleted',new.deleted_at);
    end if;
  end loop;
  perform set_config('app.duel_write_v1','on',true);
  delete from app.duel_beta_allowlist where actor_id=new.id;
  return new;
end;
$$;
