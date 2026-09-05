-- Phase 3(a): owner-only, nonredeemable performance agreements. No attempts,
-- scoring, follower access, payment objects, worker or automatic expiry.
create table app.performance_commitment_policy_versions (
  version text primary key,
  specification jsonb not null check (jsonb_typeof(specification)='object')
);
insert into app.performance_commitment_policy_versions values ('performance-commitment-fixture-5k-v1','{
  "source":"fixture_official_5k_v1", "sport":"outdoor_running",
  "distance_meters":5000, "timing_basis":"organizer_chip",
  "precision_ms":1000, "comparator":"lt", "target_min_seconds":1,
  "target_max_seconds":86400, "duration_basis":"elapsed_utc",
  "minimum_duration_hours":672, "maximum_duration_hours":2160,
  "start_within_hours":720, "attempt_window":"start_inclusive_finish_exclusive",
  "attempts":"multiple_nominated_events", "success":"any_qualifying_attempt",
  "slower_later_attempt":"does_not_undo_success", "milestones":"not_qualifying_proof",
  "results_after_deadline_hours":72, "dispute_after_durable_notice_hours":168,
  "review_after_filing_hours":168, "finality_after_deadline_hours":720,
  "miss":"complete_confirmed_attempt_set_or_explicit_no_attempt_acknowledgement_after_review",
  "missing_or_ambiguous_proof":"review_then_inconclusive_zero_consequence",
  "review_timeout":"inconclusive_zero_consequence",
  "corrections":"append_only_no_automatic_new_consequence",
  "prestart_cancellation":"zero_consequence", "withdrawal_or_injury":"zero_consequence",
  "account_deletion":"close_unfinalized_zero_consequence_retain_agreement",
  "mode":"simulated", "currency":"USD", "commitment_cents":2000,
  "fee_cents":0, "forfeiture_recipient":"unselected", "payee":null,
  "confirmed_miss_disposition":"simulated_loss_no_payee_no_transfer",
  "redeemable":false, "consent_version":"performance-commitment-simulated-consent-v1"
}');
create table app.performance_commitment_runtime (
  singleton boolean primary key default true check(singleton),
  admission_enabled boolean not null default false
);
insert into app.performance_commitment_runtime(singleton) values(true);
create table app.performance_commitment_beta_allowlist (
  actor_id uuid primary key references public.profiles(id)
);
create table app.performance_commitment_agreements (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid not null references public.profiles(id),
  policy_version text not null references app.performance_commitment_policy_versions(version),
  created_at timestamptz not null check(isfinite(created_at)),
  starts_at timestamptz not null check(isfinite(starts_at)),
  deadline_at timestamptz not null check(isfinite(deadline_at)),
  display_timezone text not null,
  target_seconds integer not null check(target_seconds between 1 and 86400),
  terms jsonb not null check(jsonb_typeof(terms)='object'),
  terms_digest text generated always as (encode(extensions.digest(terms::text,'sha256'),'hex')) stored,
  status text not null default 'open' check(status in ('open','cancelled','withdrawn')),
  closed_at timestamptz check(isfinite(closed_at)),
  close_reason text check(close_reason in ('cancel','withdrawal','injury','account_deleted')),
  unique(id,actor_id),
  check(starts_at>created_at and starts_at<=created_at+interval '720 hours'),
  check(extract(epoch from deadline_at-starts_at) between 2419200 and 7776000),
  check((status='open')=(closed_at is null)),
  check((closed_at is null)=(close_reason is null)),
  check(closed_at is null or closed_at>=created_at),
  check(status<>'cancelled' or closed_at<starts_at),
  check(status<>'withdrawn' or closed_at>=starts_at)
);
create index performance_commitment_history_idx on app.performance_commitment_agreements(actor_id,created_at desc,id desc);
create index performance_commitment_policy_idx on app.performance_commitment_agreements(policy_version);
create table app.performance_commitment_consents (
  commitment_id uuid primary key,
  actor_id uuid not null,
  accepted_at timestamptz not null,
  policy_version text not null references app.performance_commitment_policy_versions(version),
  terms_digest text not null,
  foreign key(commitment_id,actor_id) references app.performance_commitment_agreements(id,actor_id)
);
create index performance_commitment_consent_policy_idx on app.performance_commitment_consents(policy_version);
create table app.performance_commitment_enrollments (
  commitment_id uuid primary key,
  actor_id uuid not null,
  reserved_at timestamptz not null,
  released_at timestamptz,
  foreign key(commitment_id,actor_id) references app.performance_commitment_agreements(id,actor_id),
  check(released_at is null or released_at>=reserved_at)
);
create unique index performance_commitment_one_open_per_actor on app.performance_commitment_enrollments(actor_id)
  where released_at is null;
create table app.performance_commitment_requests (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  payload jsonb not null,
  commitment_id uuid not null,
  committed_at timestamptz not null,
  primary key(actor_id,request_id),
  foreign key(commitment_id,actor_id) references app.performance_commitment_agreements(id,actor_id)
);
create index performance_commitment_request_agreement_idx on app.performance_commitment_requests(commitment_id,actor_id);

create function app.performance_commitment_guard_v1() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
    or coalesce(current_setting('app.performance_commitment_write_v1',true),'')<>'on' then
    raise exception 'performance_commitment_write_requires_rpc' using errcode='42501';
  end if;
  if tg_op in ('DELETE','TRUNCATE') and tg_table_name<>'performance_commitment_beta_allowlist' then
    raise exception 'performance_commitment_history_is_retained' using errcode='23001';
  end if;
  if tg_op='UPDATE' then
    if tg_table_name='performance_commitment_agreements' then
      if (to_jsonb(new)-array['status','closed_at','close_reason','terms_digest']) is distinct from
         (to_jsonb(old)-array['status','closed_at','close_reason','terms_digest'])
        or old.status<>'open' or new.status not in ('cancelled','withdrawn') then
        raise exception 'performance_commitment_terms_or_transition_immutable' using errcode='23001';
      end if;
    elsif tg_table_name='performance_commitment_enrollments' then
      if old.released_at is not null or new.released_at is null
        or (new.commitment_id,new.actor_id,new.reserved_at) is distinct from
           (old.commitment_id,old.actor_id,old.reserved_at) then
        raise exception 'performance_commitment_enrollment_is_retained' using errcode='23001';
      end if;
    elsif tg_table_name<>'performance_commitment_runtime' then
      raise exception 'performance_commitment_history_is_immutable' using errcode='23001';
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end; $$;

-- Only typed UTC instants are accepted. A future UI must resolve local-time
-- ambiguity before calling; changing device/session timezone cannot move terms.
create function app.performance_commitment_terms_v1(p_actor uuid,p_target_seconds integer,
  p_starts_at timestamptz,p_deadline_at timestamptz,p_display_timezone text,p_policy_version text)
returns jsonb language plpgsql stable set search_path='' set timezone='UTC' as $$
declare policy jsonb;
begin
  if p_actor is null or p_target_seconds is null or p_target_seconds not between 1 and 86400
    or p_starts_at is null or p_deadline_at is null or not isfinite(p_starts_at) or not isfinite(p_deadline_at)
    or extract(epoch from p_deadline_at-p_starts_at) not between 2419200 and 7776000
    or p_policy_version is distinct from 'performance-commitment-fixture-5k-v1'
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_display_timezone) then
    raise exception 'performance_commitment_invalid_terms' using errcode='22023';
  end if;
  select specification into strict policy from app.performance_commitment_policy_versions where version=p_policy_version;
  return jsonb_build_object('agreement_version',1,'actor_id',p_actor,'policy_version',p_policy_version,'policy',policy,
    'target_ms',p_target_seconds::bigint*1000,'starts_at',p_starts_at,'deadline_at',p_deadline_at,
    'display_timezone',p_display_timezone,'results_due_at',p_deadline_at+interval '72 hours',
    'finality_due_at',p_deadline_at+interval '720 hours');
end; $$;

create function app.performance_commitment_check_v1() returns trigger
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
      and e.actor_id=c.actor_id and e.reserved_at=c.created_at and e.released_at is not distinct from c.closed_at) then
    raise exception 'performance_commitment_aggregate_invariant' using errcode='23514';
  end if;
  return null;
end; $$;
do $$ declare t text; begin
  foreach t in array array['performance_commitment_policy_versions','performance_commitment_runtime',
    'performance_commitment_beta_allowlist','performance_commitment_agreements','performance_commitment_consents',
    'performance_commitment_enrollments','performance_commitment_requests'] loop
    execute format('alter table app.%I enable row level security',t);
    execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
    execute format('create trigger performance_commitment_guard before insert or update or delete on app.%I
      for each row execute function app.performance_commitment_guard_v1()',t);
    execute format('create trigger performance_commitment_truncate before truncate on app.%I
      for each statement execute function app.performance_commitment_guard_v1()',t);
    if t in ('performance_commitment_agreements','performance_commitment_consents','performance_commitment_enrollments') then
      execute format('create constraint trigger performance_commitment_aggregate after insert or update on app.%I
        deferrable initially deferred for each row execute function app.performance_commitment_check_v1()',t);
    end if;
  end loop;
end; $$;

-- Profile -> session -> runtime -> agreement. Session share lock serializes
-- session deletion/revocation as well as the existing profile deletion lock.
create function app.performance_commitment_lock_actor_v1() returns uuid
language plpgsql set search_path='' as $$
declare a uuid:=auth.uid();
begin
  if current_setting('role')<>'authenticated' or a is null then
    raise exception 'performance_commitment_session_required' using errcode='42501';
  end if;
  perform app.lock_active_actors(array[a]);
  perform 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=a
    and (not_after is null or not_after>clock_timestamp()) for share;
  if not found then raise exception 'performance_commitment_session_required' using errcode='42501'; end if;
  return a;
end; $$;
create function app.performance_commitment_admit_v1(p_actor uuid) returns void
language plpgsql set search_path='' as $$
begin
  perform 1 from app.performance_commitment_runtime where singleton and admission_enabled for share;
  if not found or not exists(select 1 from app.performance_commitment_beta_allowlist where actor_id=p_actor) then
    raise exception 'performance_commitment_admission_denied' using errcode='42501';
  end if;
end; $$;
create function public.set_performance_commitment_admission_v1(p_enabled boolean,p_actor_ids uuid[])
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not(current_setting('role')='service_role' or (current_setting('role')='none' and session_user='postgres')) then
    raise exception 'performance_commitment_service_required' using errcode='42501';
  end if;
  if p_enabled is null or p_actor_ids is null or cardinality(p_actor_ids)>100 or array_position(p_actor_ids,null) is not null then
    raise exception 'performance_commitment_invalid_admission' using errcode='22023';
  end if;
  perform app.lock_active_actors(p_actor_ids);
  perform 1 from app.performance_commitment_runtime where singleton for update;
  perform set_config('app.performance_commitment_write_v1','on',true);
  update app.performance_commitment_runtime set admission_enabled=p_enabled where singleton;
  delete from app.performance_commitment_beta_allowlist;
  insert into app.performance_commitment_beta_allowlist select distinct unnest(p_actor_ids);
  return p_enabled;
end; $$;
create function app.performance_commitment_recover_v1(p_actor uuid,p_request uuid,p_payload jsonb)
returns uuid language plpgsql set search_path='' as $$
declare r app.performance_commitment_requests;
begin
  if p_request is null then raise exception 'performance_commitment_request_required' using errcode='22023'; end if;
  select * into r from app.performance_commitment_requests where actor_id=p_actor and request_id=p_request;
  if found and r.payload is distinct from p_payload then
    raise exception 'performance_commitment_request_payload_conflict' using errcode='22023';
  end if;
  return r.commitment_id;
end; $$;
create function public.preview_performance_commitment_v1(p_target_seconds integer,p_starts_at timestamptz,
  p_deadline_at timestamptz,p_display_timezone text,p_expected_policy_version text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; t jsonb; n timestamptz;
begin
  a:=app.performance_commitment_lock_actor_v1();
  perform app.performance_commitment_admit_v1(a);
  -- Admission may have waited while the session's natural expiry passed.
  perform app.performance_commitment_lock_actor_v1();
  n:=clock_timestamp();
  t:=app.performance_commitment_terms_v1(a,p_target_seconds,p_starts_at,p_deadline_at,p_display_timezone,p_expected_policy_version);
  if p_starts_at<=n or p_starts_at>n+interval '720 hours' then
    raise exception 'performance_commitment_start_unavailable' using errcode='22023';
  end if;
  return jsonb_build_object('terms',t,'terms_digest',encode(extensions.digest(t::text,'sha256'),'hex'),'server_now',n);
end; $$;
create function app.create_performance_commitment_at_v1(p_request_id uuid,p_target_seconds integer,p_starts_at timestamptz,
  p_deadline_at timestamptz,p_display_timezone text,p_expected_policy_version text,p_expected_terms_digest text,
  p_consent boolean,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare a uuid; payload jsonb; v_id uuid; n timestamptz; t jsonb; digest text;
begin
  a:=app.performance_commitment_lock_actor_v1();
  payload:=jsonb_build_object('operation','create_performance_commitment_v1','target_seconds',p_target_seconds,
    'starts_at',p_starts_at,'deadline_at',p_deadline_at,'display_timezone',p_display_timezone,
    'policy_version',p_expected_policy_version,'terms_digest',p_expected_terms_digest,'consent',p_consent);
  v_id:=app.performance_commitment_recover_v1(a,p_request_id,payload);
  if v_id is not null then return v_id; end if;
  perform app.performance_commitment_admit_v1(a);
  perform app.performance_commitment_lock_actor_v1();
  t:=app.performance_commitment_terms_v1(a,p_target_seconds,p_starts_at,p_deadline_at,p_display_timezone,p_expected_policy_version);
  digest:=encode(extensions.digest(t::text,'sha256'),'hex');
  if p_consent is distinct from true or p_expected_terms_digest is distinct from digest then
    raise exception 'performance_commitment_consent_mismatch' using errcode='22023';
  end if;
  n:=coalesce(p_now,clock_timestamp());
  if not isfinite(n) or p_starts_at<=n or p_starts_at>n+interval '720 hours' then
    raise exception 'performance_commitment_start_unavailable' using errcode='22023';
  end if;
  if exists(select 1 from app.performance_commitment_enrollments where actor_id=a and released_at is null) then
    raise exception 'performance_commitment_slot_occupied' using errcode='23505';
  end if;
  perform set_config('app.performance_commitment_write_v1','on',true);
  insert into app.performance_commitment_agreements(actor_id,policy_version,created_at,starts_at,deadline_at,display_timezone,target_seconds,terms)
    values(a,p_expected_policy_version,n,p_starts_at,p_deadline_at,p_display_timezone,p_target_seconds,t) returning id into v_id;
  insert into app.performance_commitment_consents values(v_id,a,n,p_expected_policy_version,digest);
  insert into app.performance_commitment_enrollments values(v_id,a,n,null);
  insert into app.performance_commitment_requests values(a,p_request_id,payload,v_id,n);
  return v_id;
end; $$;
create function public.create_performance_commitment_v1(p_request_id uuid,p_target_seconds integer,p_starts_at timestamptz,
  p_deadline_at timestamptz,p_display_timezone text,p_expected_policy_version text,p_expected_terms_digest text,p_consent boolean)
returns uuid language sql security definer set search_path='' as $$
  select app.create_performance_commitment_at_v1(p_request_id,p_target_seconds,p_starts_at,p_deadline_at,
    p_display_timezone,p_expected_policy_version,p_expected_terms_digest,p_consent)
$$;
create function app.performance_commitment_close_v1(p_id uuid,p_reason text,p_now timestamptz)
returns void language plpgsql set search_path='' as $$
begin
  perform set_config('app.performance_commitment_write_v1','on',true);
  update app.performance_commitment_agreements set status=case when p_now<starts_at then 'cancelled' else 'withdrawn' end,
    closed_at=p_now,close_reason=p_reason where id=p_id;
  update app.performance_commitment_enrollments set released_at=p_now where commitment_id=p_id and released_at is null;
end; $$;
create function app.close_performance_commitment_at_v1(p_request_id uuid,p_commitment_id uuid,p_reason text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; payload jsonb; v_id uuid; n timestamptz; c app.performance_commitment_agreements;
begin
  a:=app.performance_commitment_lock_actor_v1();
  payload:=jsonb_build_object('operation','close_performance_commitment_v1','commitment_id',p_commitment_id,'reason',p_reason);
  v_id:=app.performance_commitment_recover_v1(a,p_request_id,payload);
  if v_id is not null then return v_id; end if;
  select * into c from app.performance_commitment_agreements where id=p_commitment_id and actor_id=a for update;
  if not found then raise exception 'performance_commitment_unavailable' using errcode='42501'; end if;
  n:=coalesce(p_now,clock_timestamp());
  if not isfinite(n) or n<c.created_at or p_reason is null or p_reason not in ('cancel','withdrawal','injury') then
    raise exception 'performance_commitment_invalid_close' using errcode='22023';
  end if;
  if c.closed_at is not null or (p_reason='cancel' and n>=c.starts_at) or (p_reason='withdrawal' and n<c.starts_at) then
    raise exception 'performance_commitment_close_unavailable' using errcode='55000';
  end if;
  perform app.performance_commitment_close_v1(c.id,p_reason,n);
  insert into app.performance_commitment_requests values(a,p_request_id,payload,c.id,n);
  return c.id;
end; $$;
create function public.close_performance_commitment_v1(p_request_id uuid,p_commitment_id uuid,p_reason text)
returns uuid language sql security definer set search_path='' as $$
  select app.close_performance_commitment_at_v1(p_request_id,p_commitment_id,p_reason)
$$;
create function app.performance_commitment_projection_v1(p_id uuid,p_now timestamptz)
returns jsonb language sql stable set search_path='' set timezone='UTC' as $$
  select to_jsonb(c)||jsonb_build_object('consent',to_jsonb(s),'server_now',p_now,
    'phase',case when c.closed_at is not null then c.status when p_now<c.starts_at then 'scheduled'
      when p_now<c.deadline_at then 'active' else 'awaiting_proof' end)
  from app.performance_commitment_agreements c join app.performance_commitment_consents s on s.commitment_id=c.id where c.id=p_id
$$;
create function public.get_performance_commitment_v1(p_commitment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;
begin
  a:=app.performance_commitment_lock_actor_v1();
  if not exists(select 1 from app.performance_commitment_agreements where id=p_commitment_id and actor_id=a) then
    raise exception 'performance_commitment_unavailable' using errcode='42501';
  end if;
  return app.performance_commitment_projection_v1(p_commitment_id,clock_timestamp());
end; $$;
create function public.list_my_performance_commitments_v1(p_limit integer default 50,
  p_before timestamptz default null,p_before_id uuid default null)
returns setof jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; n timestamptz;
begin
  a:=app.performance_commitment_lock_actor_v1();
  if p_limit is null or p_limit not between 1 and 100 or ((p_before is null)<>(p_before_id is null))
    or (p_before is not null and not isfinite(p_before)) then
    raise exception 'performance_commitment_invalid_page' using errcode='22023';
  end if;
  n:=clock_timestamp();
  return query select app.performance_commitment_projection_v1(c.id,n) from app.performance_commitment_agreements c
    where c.actor_id=a and (p_before is null or (c.created_at,c.id)<(p_before,p_before_id))
    order by c.created_at desc,c.id desc limit p_limit;
end; $$;
create function app.resolve_performance_commitments_on_deletion_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements;
begin
  if old.deleted_at is not null or new.deleted_at is null then return new; end if;
  if not exists(select 1 from app.account_deletion_transactions where transaction_id=txid_current()
    and backend_pid=pg_backend_pid() and actor_id=new.id) then
    raise exception 'performance_commitment_deletion_requires_rpc' using errcode='42501';
  end if;
  for c in select * from app.performance_commitment_agreements where actor_id=new.id and closed_at is null order by id for update loop
    perform app.performance_commitment_close_v1(c.id,'account_deleted',new.deleted_at);
  end loop;
  perform set_config('app.performance_commitment_write_v1','on',true);
  delete from app.performance_commitment_beta_allowlist where actor_id=new.id;
  return new;
end; $$;
create trigger profiles_resolve_performance_commitments_on_deletion after update of deleted_at on public.profiles
  for each row execute function app.resolve_performance_commitments_on_deletion_v1();

-- Private RPC-only storage: RLS has no client policies or table grants. Explicit
-- function allowlist includes no clock seam, arbitrary actor or service write.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and p.proname like '%performance_commitment%v1' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.preview_performance_commitment_v1(integer,timestamptz,timestamptz,text,text),
  public.create_performance_commitment_v1(uuid,integer,timestamptz,timestamptz,text,text,text,boolean),
  public.close_performance_commitment_v1(uuid,uuid,text),public.get_performance_commitment_v1(uuid),
  public.list_my_performance_commitments_v1(integer,timestamptz,uuid) to authenticated;
grant execute on function public.set_performance_commitment_admission_v1(boolean,uuid[]) to service_role;
