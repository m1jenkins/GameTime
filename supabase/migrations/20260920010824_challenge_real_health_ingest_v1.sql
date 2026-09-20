-- P8: a private, separately gated real-source boundary.  It deliberately does
-- not widen the fictional challenge contract or modify a frozen agreement.
create table app.challenge_real_health_runtime_v1 (
  singleton boolean primary key default true check (singleton),
  admission_enabled boolean not null default false,
  ingestion_enabled boolean not null default false,
  processing_enabled boolean not null default false
);
insert into app.challenge_real_health_runtime_v1 default values;

-- This first slice intentionally accepts steps only.  The policy text is
-- frozen here so a caller can name only an adopted version, never a source,
-- route, baseline, or ad-hoc rule.
create table app.challenge_real_health_source_policies_v1 (
  version text primary key,
  metric text not null check (metric = 'steps'),
  terms jsonb not null,
  digest text generated always as (encode(extensions.digest(terms::text, 'sha256'), 'hex')) stored,
  check (version = 'apple_watch_steps_v1')
);
insert into app.challenge_real_health_source_policies_v1(version, metric, terms)
values (
  'apple_watch_steps_v1',
  'steps',
  '{"version":"apple_watch_steps_v1","metric":"steps","unit":"whole_counts","provenance":"automatic_paired_watch_only","reconciliation":"multiple_watches_reconciled","normalization":"floor"}'::jsonb
);

alter table app.challenge_lobbies_v1
  add column real_source_policy_version text
    references app.challenge_real_health_source_policies_v1(version);
alter table app.challenge_lobbies_v1
  add constraint challenge_real_source_policy_steps_v1
    check (real_source_policy_version is null or policy like '%_steps_%');

-- A new immutable admission record carries the real policy binding.  The
-- original agreement stays byte-for-byte as it was when its participants
-- consented; this record is the additional real-source contract.
create table app.challenge_real_health_admissions_v1 (
  challenge_id uuid not null references app.challenge_lobbies_v1(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  agreement_version integer not null,
  terms_digest text not null check (terms_digest ~ '^[0-9a-f]{64}$'),
  source_policy_version text not null references app.challenge_real_health_source_policies_v1(version),
  metric text not null check (metric = 'steps'),
  window_starts_at timestamptz not null,
  window_ends_at timestamptz not null,
  admitted_at timestamptz not null,
  primary key (challenge_id, actor_id, agreement_version),
  foreign key (challenge_id, agreement_version, actor_id)
    references app.challenge_consents_v1(challenge_id, version, actor_id) on delete cascade,
  check (window_starts_at < window_ends_at)
);

-- A positive accepted-policy read is a separate, minimal pre-consent fact. It
-- says only that the source policy produced some eligible activity; it never
-- claims full history, a zero, or qualification.
create table app.challenge_real_health_readiness_v1 (
  actor_id uuid not null references public.profiles(id) on delete cascade,
  source_policy_version text not null references app.challenge_real_health_source_policies_v1(version),
  observed_at timestamptz not null,
  recorded_at timestamptz not null,
  primary key (actor_id, source_policy_version)
);

-- Readiness has its own replay ledger.  A readiness assertion cannot be
-- replayed as a progress assertion (or vice versa), even if a UUID is reused.
create table app.challenge_real_health_readiness_requests_v1 (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  source_policy_version text not null references app.challenge_real_health_source_policies_v1(version),
  observed_at timestamptz not null,
  payload_digest bytea not null check (octet_length(payload_digest) = 32),
  device_key_id bytea not null check (octet_length(device_key_id) = 32),
  assertion_counter bigint not null check (assertion_counter > 0),
  response jsonb not null,
  recorded_at timestamptz not null,
  unique (device_key_id, assertion_counter)
);

create table app.challenge_real_health_facts_v1 (
  challenge_id uuid not null,
  actor_id uuid not null,
  agreement_version integer not null,
  revision integer not null check (revision > 0 and revision <= 2147483647),
  previous_revision integer,
  state text not null check (state in ('value', 'deleted', 'unresolved')),
  value bigint check (value between 1 and 1000000000),
  observed_at timestamptz not null,
  queried_through_at timestamptz not null,
  recorded_at timestamptz not null,
  request_id uuid not null unique,
  primary key (challenge_id, actor_id, agreement_version, revision),
  foreign key (challenge_id, actor_id, agreement_version)
    references app.challenge_real_health_admissions_v1(challenge_id, actor_id, agreement_version) on delete cascade,
  check ((state = 'value') = (value is not null)),
  check ((revision = 1 and previous_revision is null)
    or (revision > 1 and previous_revision is not null and previous_revision = revision - 1)),
  check (queried_through_at <= observed_at)
);

create table app.challenge_real_health_requests_v1 (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  payload jsonb not null,
  payload_digest bytea not null check (octet_length(payload_digest) = 32),
  device_key_id bytea not null check (octet_length(device_key_id) = 32),
  assertion_counter bigint not null check (assertion_counter > 0),
  response jsonb not null,
  recorded_at timestamptz not null,
  unique (device_key_id, assertion_counter)
);

do $$
declare t text;
begin
  foreach t in array array[
    'real_health_runtime', 'real_health_source_policies', 'real_health_admissions', 'real_health_readiness', 'real_health_readiness_requests',
    'real_health_facts', 'real_health_requests'
  ] loop
    execute format('alter table app.challenge_%s_v1 enable row level security', t);
    execute format('revoke all on app.challenge_%s_v1 from public, anon, authenticated, service_role', t);
    execute format('create trigger challenge_%s_guard before insert or update or delete on app.challenge_%s_v1 for each row execute function app.challenge_entry_guard_v1()', t, t);
    execute format('create trigger challenge_%s_no_truncate before truncate on app.challenge_%s_v1 for each statement execute function app.challenge_entry_guard_v1()', t, t);
  end loop;
end;
$$;

-- The private switch is mutable only through its service RPC.  Every other
-- real-source row is append-only.
create function app.challenge_real_health_runtime_guard_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid = tg_relid))
     or coalesce(current_setting('app.challenge_write_v1', true), '') <> 'on'
  then
    raise exception 'challenge_rpc_required' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    return new;
  end if;
  raise exception 'challenge_immutable' using errcode = '23001';
end;
$$;
drop trigger challenge_real_health_runtime_guard on app.challenge_real_health_runtime_v1;
drop trigger challenge_real_health_runtime_no_truncate on app.challenge_real_health_runtime_v1;
create trigger challenge_real_health_runtime_guard
  before insert or update or delete on app.challenge_real_health_runtime_v1
  for each row execute function app.challenge_real_health_runtime_guard_v1();
create trigger challenge_real_health_runtime_no_truncate
  before truncate on app.challenge_real_health_runtime_v1
  for each statement execute function app.challenge_real_health_runtime_guard_v1();

-- Readiness is the one real-source record that may advance to a fresher
-- observation.  The generic entry guard remains append-only for facts and
-- receipts.
drop trigger challenge_real_health_readiness_guard on app.challenge_real_health_readiness_v1;
create trigger challenge_real_health_readiness_guard
  before insert or update or delete on app.challenge_real_health_readiness_v1
  for each row execute function app.challenge_real_health_runtime_guard_v1();

-- Production uses wall time.  The disposable SQL harness may transactionally
-- replace this definition to exercise 24/48/72-hour boundaries; token and
-- session validation below always continues to use clock_timestamp().
create function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path = '' as $$
  select clock_timestamp()
$$;

create function app.challenge_real_health_payload_v1(p jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  required text[] := array[
    'contract_version', 'actor_id', 'challenge_id', 'agreement_version',
    'terms_digest', 'source_policy_version', 'metric', 'window_starts_at',
    'window_ends_at', 'request_id', 'revision', 'previous_revision', 'state',
    'observed_at', 'queried_through_at'
  ];
  expected text[];
  state_value text;
begin
  if jsonb_typeof(p) is distinct from 'object'
     or octet_length(p::text) > 8192
     or not (p ?& required)
     or not (p ? 'value')
  then
    raise exception 'challenge_invalid_real_health_request' using errcode = '22023';
  end if;

  state_value := p ->> 'state';
  expected := required || array['value'];
  if p - expected <> '{}'::jsonb
     or p ->> 'contract_version' <> '1'
     or jsonb_typeof(p -> 'actor_id') <> 'string'
     or jsonb_typeof(p -> 'challenge_id') <> 'string'
     or jsonb_typeof(p -> 'agreement_version') <> 'number'
     or jsonb_typeof(p -> 'terms_digest') <> 'string'
     or jsonb_typeof(p -> 'source_policy_version') <> 'string'
     or jsonb_typeof(p -> 'metric') <> 'string'
     or jsonb_typeof(p -> 'window_starts_at') <> 'string'
     or jsonb_typeof(p -> 'window_ends_at') <> 'string'
     or jsonb_typeof(p -> 'request_id') <> 'string'
     or jsonb_typeof(p -> 'revision') <> 'number'
     or (p -> 'previous_revision') <> 'null'::jsonb and jsonb_typeof(p -> 'previous_revision') <> 'number'
     or jsonb_typeof(p -> 'state') <> 'string'
     or (state_value = 'value' and jsonb_typeof(p -> 'value') <> 'number')
     or (state_value in ('deleted', 'unresolved') and p -> 'value' <> 'null'::jsonb)
     or jsonb_typeof(p -> 'observed_at') <> 'string'
     or jsonb_typeof(p -> 'queried_through_at') <> 'string'
     or p ->> 'actor_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p ->> 'challenge_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p ->> 'request_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p ->> 'agreement_version' !~ '^[1-9][0-9]*$'
     or p ->> 'revision' !~ '^[1-9][0-9]*$'
     or (p -> 'previous_revision' <> 'null'::jsonb and p ->> 'previous_revision' !~ '^[1-9][0-9]*$')
     or p ->> 'terms_digest' !~ '^[0-9a-f]{64}$'
     or (p ->> 'revision')::numeric > 2147483647
     or (p -> 'previous_revision' <> 'null'::jsonb and (p ->> 'previous_revision')::numeric > 2147483647)
     or p ->> 'source_policy_version' <> 'apple_watch_steps_v1'
     or p ->> 'metric' <> 'steps'
     or state_value not in ('value', 'deleted', 'unresolved')
     or (state_value = 'value' and (
       p ->> 'value' !~ '^[1-9][0-9]*$'
       or (p ->> 'value')::numeric > 1000000000
     ))
  then
    raise exception 'challenge_invalid_real_health_request' using errcode = '22023';
  end if;
end;
$$;

create function app.challenge_real_health_evaluate_v1(p_challenge_id uuid,p_force_void boolean default false)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  challenge app.challenge_lobbies_v1;
  people jsonb;
begin
  select * into challenge from app.challenge_lobbies_v1 where id = p_challenge_id;
  if challenge.id is null then
    raise exception 'challenge_unavailable' using errcode = '22023';
  end if;

  -- A value is a lower bound.  It can satisfy a goal, but it cannot prove that
  -- a leaderboard is complete, so all leaderboard results remain unresolved.
  select coalesce(jsonb_agg(jsonb_build_object(
    'actor_id', slot.actor_id,
    'target', member.target,
    'excluded', member.exited_at is not null
      or app.challenge_actor_unavailable_v1(slot.actor_id)
      or exists (
        select 1
        from app.challenge_reviews_v1 review
        left join app.challenge_resolutions_v1 resolution on resolution.review_id = review.id
        where review.challenge_id = challenge.id
          and review.actor_id = slot.actor_id
          and (resolution.decision = 'exclude'
            or (resolution.review_id is null and app.challenge_real_health_now_v1() >= review.resolve_by))
      ),
    'state', case
      when app.challenge_policy_v1(challenge.policy) ->> 'competition' = 'leaderboard' then 'unresolved'
      when fact.state = 'value' and fact.value >= member.target then 'complete'
      else 'unresolved'
    end,
    'value', case
      when app.challenge_policy_v1(challenge.policy) ->> 'competition' <> 'leaderboard'
       and fact.state = 'value' and fact.value >= member.target then fact.value
      else null
    end
  ) order by slot.actor_id), '[]'::jsonb)
  into people
  from app.challenge_slots_v1 slot
  join app.challenge_members_v1 member
    on member.challenge_id = slot.challenge_id and member.actor_id = slot.actor_id
  left join lateral (
    select f.*
    from app.challenge_real_health_admissions_v1 admission
    join app.challenge_real_health_facts_v1 f
      on f.challenge_id = admission.challenge_id
     and f.actor_id = admission.actor_id
     and f.agreement_version = admission.agreement_version
    where admission.challenge_id = challenge.id
      and admission.actor_id = slot.actor_id
      and admission.agreement_version = challenge.agreement_version
    order by f.revision desc
    limit 1
  ) fact on true
  where slot.challenge_id = challenge.id;

  return app.challenge_evaluate_policy_v1(
    challenge.policy,
    people,
    (challenge.config ->> 'amount_cents')::integer,
    challenge.minimum,
    p_force_void
  );
end;
$$;

create function public.challenge_real_health_runtime_v1(
  p_admission_enabled boolean,
  p_ingestion_enabled boolean,
  p_processing_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.duel_require_service_v1();
  if p_admission_enabled is null or p_ingestion_enabled is null or p_processing_enabled is null then
    raise exception 'challenge_invalid_real_health_runtime' using errcode = '22023';
  end if;
  perform set_config('app.challenge_write_v1', 'on', true);
  update app.challenge_real_health_runtime_v1
  set admission_enabled = p_admission_enabled,
      ingestion_enabled = p_ingestion_enabled,
      processing_enabled = p_processing_enabled
  where singleton;
end;
$$;

create function public.challenge_real_health_readiness_v1(
  p_request_id uuid,
  p_actor_id uuid,
  p_source_policy_version text,
  p_observed_at timestamptz,
  p_session_id uuid,
  p_token_expires_at timestamptz,
  p_device_key_id bytea,
  p_assertion_counter bigint,
  p_payload_digest bytea,
  p_recovery_only boolean default false
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  wall_at timestamptz;
  now_at timestamptz;
  device public.device_attestations;
  saved app.challenge_real_health_readiness_requests_v1;
  response jsonb;
begin
  perform app.duel_require_service_v1();
  if p_request_id is null or p_actor_id is null or p_session_id is null
     or p_token_expires_at is null or p_device_key_id is null or octet_length(p_device_key_id) <> 32
     or p_assertion_counter is null or p_assertion_counter <= 0
     or p_payload_digest is null or octet_length(p_payload_digest) <> 32
     or p_recovery_only is null
     or p_source_policy_version <> 'apple_watch_steps_v1'
     or p_observed_at is null or not isfinite(p_observed_at)
  then
    raise exception 'challenge_real_health_readiness_invalid' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('challenge_real_health_readiness_v1:' || p_request_id::text, 0)
  );
  perform app.lock_active_actors(array[p_actor_id]);
  select * into device from public.device_attestations where key_id = p_device_key_id for update;
  perform id from auth.sessions
    where id = p_session_id and user_id = p_actor_id
    for share;
  wall_at := clock_timestamp();
  now_at := app.challenge_real_health_now_v1();
  if p_token_expires_at <= wall_at
     or p_observed_at > now_at
     or not app.is_active_actor(p_actor_id)
     or app.challenge_actor_unavailable_v1(p_actor_id)
     or device.key_id is null or device.user_id <> p_actor_id or device.revoked_at is not null
     or not exists (
       select 1 from auth.sessions session
       where session.id = p_session_id and session.user_id = p_actor_id
         and (session.not_after is null or session.not_after > wall_at)
     )
     or not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id and receipt.current_receipt_verified_at is not null
     )
  then
    raise exception 'challenge_real_health_session_required' using errcode = '42501';
  end if;
  select * into saved from app.challenge_real_health_readiness_requests_v1
    where request_id = p_request_id;
  if found then
    if saved.actor_id is distinct from p_actor_id
       or (saved.source_policy_version, saved.observed_at, saved.payload_digest,
        saved.device_key_id, saved.assertion_counter)
       is distinct from
       (p_source_policy_version, p_observed_at, p_payload_digest,
        p_device_key_id, p_assertion_counter)
    then
      raise exception 'challenge_request_conflict' using errcode = '22023';
    end if;
    return saved.response;
  end if;
  if p_recovery_only
     or not exists (select 1 from app.challenge_real_health_runtime_v1 where singleton and admission_enabled)
  then
    raise exception 'challenge_real_health_paused' using errcode = '42501';
  end if;
  if p_assertion_counter <= device.sign_count then
    raise exception 'challenge_real_health_assertion_replayed' using errcode = '23001';
  end if;

  -- Recheck time-sensitive authorization after lock waits before consuming the
  -- counter.  `clock_timestamp` is deliberately not the test clock.
  wall_at := clock_timestamp();
  perform id from auth.sessions
    where id = p_session_id and user_id = p_actor_id
    for share;
  if p_token_expires_at <= wall_at
     or not app.is_active_actor(p_actor_id)
     or app.challenge_actor_unavailable_v1(p_actor_id)
     or device.revoked_at is not null
     or not exists (
       select 1 from auth.sessions session
       where session.id = p_session_id and session.user_id = p_actor_id
         and (session.not_after is null or session.not_after > wall_at)
     )
  then
    raise exception 'challenge_real_health_session_required' using errcode = '42501';
  end if;
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_real_health_readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)
  values(p_actor_id,p_source_policy_version,p_observed_at,now_at)
  on conflict(actor_id,source_policy_version) do update
    set observed_at = greatest(app.challenge_real_health_readiness_v1.observed_at,excluded.observed_at),
        recorded_at = excluded.recorded_at;
  update public.device_attestations
    set sign_count = p_assertion_counter, last_asserted_at = now_at
    where key_id = p_device_key_id;
  response := jsonb_build_object(
    'version', 'challenge_real_health_readiness_receipt_v1',
    'request_id', p_request_id,
    'accepted_at', now_at
  );
  insert into app.challenge_real_health_readiness_requests_v1(
    request_id, actor_id, source_policy_version, observed_at, payload_digest,
    device_key_id, assertion_counter, response, recorded_at
  ) values (
    p_request_id, p_actor_id, p_source_policy_version, p_observed_at, p_payload_digest,
    p_device_key_id, p_assertion_counter, response, now_at
  );
  return response;
end;
$$;

create function public.challenge_real_health_ingest_v1(
  p_request_id uuid,
  p_payload jsonb,
  p_session_id uuid,
  p_token_expires_at timestamptz,
  p_device_key_id bytea,
  p_assertion_counter bigint,
  p_payload_digest bytea,
  p_recovery_only boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  actor uuid;
  v_challenge_id uuid;
  v_agreement_version integer;
  v_revision integer;
  v_previous_revision integer;
  state_value text;
  value_value bigint;
  v_observed_at timestamptz;
  v_queried_through_at timestamptz;
  now_at timestamptz;
  wall_at timestamptz;
  saved app.challenge_real_health_requests_v1;
  device public.device_attestations;
  lobby app.challenge_lobbies_v1;
  agreement app.challenge_agreements_v1;
  admission app.challenge_real_health_admissions_v1;
  latest app.challenge_real_health_facts_v1;
  response jsonb;
begin
  perform app.duel_require_service_v1();
  if p_request_id is null
     or p_session_id is null
     or p_token_expires_at is null
     or p_device_key_id is null or octet_length(p_device_key_id) <> 32
     or p_assertion_counter is null or p_assertion_counter <= 0
     or p_payload_digest is null or octet_length(p_payload_digest) <> 32
     or p_recovery_only is null
  then
    raise exception 'challenge_invalid_real_health_request' using errcode = '22023';
  end if;

  perform app.challenge_real_health_payload_v1(p_payload);
  if (p_payload ->> 'request_id')::uuid is distinct from p_request_id then
    raise exception 'challenge_invalid_real_health_request' using errcode = '22023';
  end if;
  actor := (p_payload ->> 'actor_id')::uuid;
  v_challenge_id := (p_payload ->> 'challenge_id')::uuid;
  v_agreement_version := (p_payload ->> 'agreement_version')::integer;
  v_revision := (p_payload ->> 'revision')::integer;
  v_previous_revision := case when p_payload -> 'previous_revision' = 'null'::jsonb then null else (p_payload ->> 'previous_revision')::integer end;
  state_value := p_payload ->> 'state';
  value_value := case when state_value = 'value' then (p_payload ->> 'value')::bigint else null end;
  v_observed_at := (p_payload ->> 'observed_at')::timestamptz;
  v_queried_through_at := (p_payload ->> 'queried_through_at')::timestamptz;

  -- The request lock precedes all security checks and receipt recovery.  A
  -- request cannot race itself into consuming a device counter twice.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('challenge_real_health_request_v1:' || p_request_id::text, 0)
  );
  perform app.lock_active_actors(array[actor]);
  select * into device
  from public.device_attestations
  where key_id = p_device_key_id
  for update;
  perform id from auth.sessions
    where id = p_session_id and user_id = actor
    for share;

  wall_at := clock_timestamp();
  now_at := app.challenge_real_health_now_v1();
  if p_token_expires_at <= wall_at
     or not app.is_active_actor(actor)
     or app.challenge_actor_unavailable_v1(actor)
     or not exists (
       select 1 from auth.sessions session
       where session.id = p_session_id
         and session.user_id = actor
         and (session.not_after is null or session.not_after > wall_at)
     )
     or device.key_id is null
     or device.user_id <> actor
     or device.revoked_at is not null
     or not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id
         and receipt.current_receipt_verified_at is not null
     )
  then
    raise exception 'challenge_real_health_session_required' using errcode = '42501';
  end if;

  select * into saved
  from app.challenge_real_health_requests_v1
  where request_id = p_request_id;
  if found then
    if saved.actor_id is distinct from actor
       or saved.payload is distinct from p_payload
       or saved.payload_digest is distinct from p_payload_digest
       or saved.device_key_id is distinct from p_device_key_id
       or saved.assertion_counter is distinct from p_assertion_counter
    then
      raise exception 'challenge_request_conflict' using errcode = '22023';
    end if;
    return saved.response;
  end if;

  if p_recovery_only
     or not exists (select 1 from app.challenge_real_health_runtime_v1 where singleton and ingestion_enabled)
  then
    raise exception 'challenge_real_health_paused' using errcode = '42501';
  end if;
  if p_assertion_counter <= device.sign_count then
    raise exception 'challenge_real_health_assertion_replayed' using errcode = '23001';
  end if;

  select * into lobby from app.challenge_lobbies_v1 where id = v_challenge_id for update;
  wall_at := clock_timestamp();
  now_at := app.challenge_real_health_now_v1();
  perform id from auth.sessions
    where id = p_session_id and user_id = actor
    for share;
  if p_token_expires_at <= wall_at
     or not app.is_active_actor(actor)
     or app.challenge_actor_unavailable_v1(actor)
     or not exists (select 1 from auth.sessions session where session.id = p_session_id and session.user_id = actor and (session.not_after is null or session.not_after > wall_at))
     or device.revoked_at is not null
  then
    raise exception 'challenge_real_health_session_required' using errcode = '42501';
  end if;
  select ag.* into agreement
  from app.challenge_agreements_v1 ag
  where ag.challenge_id = v_challenge_id and ag.version = v_agreement_version;
  if lobby.id is null
     or lobby.policy not like '%_steps_%'
     or lobby.real_source_policy_version is distinct from (p_payload ->> 'source_policy_version')
     or lobby.agreement_version <> v_agreement_version
     or lobby.status not in ('scheduled', 'active', 'syncing')
     or agreement.digest <> (p_payload ->> 'terms_digest')
     or (agreement.terms ->> 'source_policy_version') is distinct from (p_payload ->> 'source_policy_version')
     or lobby.starts_at <> (p_payload ->> 'window_starts_at')::timestamptz
     or lobby.ends_at <> (p_payload ->> 'window_ends_at')::timestamptz
     or (agreement.terms->'config'->>'starts_at')::timestamptz is distinct from lobby.starts_at
     or (agreement.terms->'config'->>'ends_at')::timestamptz is distinct from lobby.ends_at
     or not exists (
       select 1 from app.challenge_consents_v1 consent
       join app.challenge_slots_v1 slot
         on slot.challenge_id = consent.challenge_id and slot.actor_id = consent.actor_id
       join app.challenge_members_v1 member
         on member.challenge_id = consent.challenge_id and member.actor_id = consent.actor_id
       where consent.challenge_id = v_challenge_id
         and consent.version = v_agreement_version
         and consent.actor_id = actor
         and consent.digest = agreement.digest
         and member.exited_at is null
     )
  then
    raise exception 'challenge_real_health_binding_invalid' using errcode = '22023';
  end if;
  if not isfinite(v_observed_at) or not isfinite(v_queried_through_at)
     or v_observed_at > now_at or v_queried_through_at > now_at
     or v_queried_through_at < lobby.starts_at
     or v_queried_through_at > v_observed_at
     or v_queried_through_at > lobby.ends_at
  then
    raise exception 'challenge_invalid_real_health_request' using errcode = '22023';
  end if;

  select * into admission
  from app.challenge_real_health_admissions_v1 a
  where a.challenge_id = v_challenge_id
    and a.actor_id = actor
    and a.agreement_version = v_agreement_version;
  if found then
    if (admission.terms_digest, admission.source_policy_version, admission.metric,
        admission.window_starts_at, admission.window_ends_at)
       is distinct from
       (p_payload ->> 'terms_digest', p_payload ->> 'source_policy_version', p_payload ->> 'metric',
        lobby.starts_at, lobby.ends_at)
    then
      raise exception 'challenge_real_health_binding_invalid' using errcode = '22023';
    end if;
  else
    perform set_config('app.challenge_write_v1', 'on', true);
    insert into app.challenge_real_health_admissions_v1(
      challenge_id, actor_id, agreement_version, terms_digest, source_policy_version,
      metric, window_starts_at, window_ends_at, admitted_at
    ) values (
      v_challenge_id, actor, v_agreement_version, p_payload ->> 'terms_digest',
      p_payload ->> 'source_policy_version', 'steps', lobby.starts_at, lobby.ends_at, now_at
    );
  end if;

  select * into latest
  from app.challenge_real_health_facts_v1 f
  where f.challenge_id = v_challenge_id
    and f.actor_id = actor
    and f.agreement_version = v_agreement_version
  order by f.revision desc
  limit 1;
  if (latest.revision is null and (v_revision <> 1 or v_previous_revision is not null))
     or (latest.revision is not null and (v_revision <> latest.revision + 1 or v_previous_revision is distinct from latest.revision))
     or (latest.revision is not null and (v_observed_at < latest.observed_at or v_queried_through_at < latest.queried_through_at))
     or now_at < lobby.starts_at
     or now_at > lobby.ends_at + (case when v_revision = 1 then interval '24 hours' else interval '48 hours' end)
  then
    raise exception 'challenge_invalid_real_health_revision' using errcode = '22023';
  end if;

  perform set_config('app.challenge_write_v1', 'on', true);
  update public.device_attestations
  set sign_count = p_assertion_counter,
      last_asserted_at = now_at
  where key_id = p_device_key_id;
  insert into app.challenge_real_health_facts_v1(
    challenge_id, actor_id, agreement_version, revision, previous_revision,
    state, value, observed_at, queried_through_at, recorded_at, request_id
  ) values (
    v_challenge_id, actor, v_agreement_version, v_revision, v_previous_revision,
    state_value, value_value, v_observed_at, v_queried_through_at, now_at, p_request_id
  );
  response := jsonb_build_object(
    'version', 'challenge_real_health_receipt_v1',
    'request_id', p_request_id,
    'challenge_id', v_challenge_id,
    'revision', v_revision,
    'accepted_at', now_at
  );
  insert into app.challenge_real_health_requests_v1(
    request_id, actor_id, payload, payload_digest, device_key_id,
    assertion_counter, response, recorded_at
  ) values (
    p_request_id, actor, p_payload, p_payload_digest, p_device_key_id,
    p_assertion_counter, response, now_at
  );
  return response;
end;
$$;

-- Real source identity is selected only on a new draft, then enters the
-- canonical frozen agreement at `freeze`.  Existing null-source agreements
-- continue through the old fixture-only admission path unchanged.
create or replace function app.challenge_admit_v1(a uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if current_setting('app.challenge_real_health_command_v1', true) = 'on'
     and exists (select 1 from app.challenge_real_health_runtime_v1 where singleton and admission_enabled)
  then
    if not exists (select 1 from app.challenge_age_v1 where actor_id = a) then
      raise exception 'challenge_age_required' using errcode = '42501';
    end if;
    if app.challenge_actor_unavailable_v1(a) then
      raise exception 'challenge_admission_paused' using errcode = '42501';
    end if;
    return;
  end if;
  if not exists (
    select 1 from app.challenge_runtime_v1
    where singleton and admission and fixtures
      and (a = any(actors) or exists (select 1 from app.challenge_access_v1 where actor_id = a))
  ) or exists (select 1 from app.challenge_suspensions_v1 where actor_id = a and suspended) then
    raise exception 'challenge_admission_paused' using errcode = '42501';
  end if;
end;
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
  if position('policy_name text;' in definition) = 0
     or position('when ''create'' then array[''op'',''config'',''policy'']' in definition) = 0
     or position('''source'',pol->>''source'',''mode''' in definition) = 0
     or position('a:=app.challenge_mutation_session_v1(); op:=p_payload->>''op'';' in definition) = 0
  then
    raise exception 'Unexpected challenge mutation source';
  end if;
  definition := replace(definition, 'policy_name text;', 'policy_name text; real_source text;');
  definition := replace(definition,
    'when ''create'' then array[''op'',''config'',''policy'']',
    'when ''create'' then array[''op'',''config'',''policy'',''source_policy_version'']');
  definition := replace(definition,
    'a:=app.challenge_mutation_session_v1(); op:=p_payload->>''op'';',
    'perform set_config(''app.challenge_real_health_command_v1'',case when p_payload->>''source_policy_version''=''apple_watch_steps_v1'' then ''on'' else ''off'' end,true); a:=app.challenge_mutation_session_v1(); op:=p_payload->>''op'';');
  definition := replace(definition,
    'select * into c from app.challenge_lobbies_v1 where id=cid for update;',
    'select * into c from app.challenge_lobbies_v1 where id=cid for update; perform set_config(''app.challenge_real_health_command_v1'',case when c.real_source_policy_version is null then ''off'' else ''on'' end,true); n:=case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end;');
  definition := replace(definition,
    'n:=app.challenge_now_v1();',
    'n:=case when coalesce(current_setting(''app.challenge_real_health_command_v1'',true),'''')=''on'' then app.challenge_real_health_now_v1() else app.challenge_now_v1() end;');
  definition := replace(definition,
    'policy_name:=coalesce(p_payload->>''policy'',''friend_steps_goal_v1''); pol:=app.challenge_policy_v1(policy_name);',
    'real_source:=p_payload->>''source_policy_version''; if real_source is not null and (jsonb_typeof(p_payload->''source_policy_version'')<>''string'' or real_source<>''apple_watch_steps_v1'') then raise exception ''challenge_invalid_real_health_source'' using errcode=''22023''; end if; policy_name:=coalesce(p_payload->>''policy'',''friend_steps_goal_v1''); pol:=app.challenge_policy_v1(policy_name); if real_source is not null and pol->>''metric''<>''steps'' then raise exception ''challenge_invalid_real_health_source'' using errcode=''22023''; end if;');
  definition := replace(definition,
    'insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity)\n   values(cid,a,policy_name,cfg,(cfg->>''starts_at'')::timestamptz,(cfg->>''ends_at'')::timestamptz,''lobby_open'',n,case when pol->>''mode''=''personal'' then 1 else 2 end,case when pol->>''mode''=''personal'' then 1 else 6 end);',
    'insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,real_source_policy_version)\n   values(cid,a,policy_name,cfg,(cfg->>''starts_at'')::timestamptz,(cfg->>''ends_at'')::timestamptz,''lobby_open'',n,case when pol->>''mode''=''personal'' then 1 else 2 end,case when pol->>''mode''=''personal'' then 1 else 6 end,real_source);');
  definition := replace(definition,
    'insert into app.challenge_members_v1(challenge_id,actor_id,selected) values(cid,a,true);',
    'if real_source is not null then update app.challenge_lobbies_v1 set real_source_policy_version=real_source where id=cid; end if; insert into app.challenge_members_v1(challenge_id,actor_id,selected) values(cid,a,true);');
  if position(E'end) into terms\n    from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster);' in definition) = 0 then
    raise exception 'Unexpected challenge agreement source';
  end if;
  definition := replace(definition,
    E'end) into terms\n    from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster);',
    E'end) || case when c.real_source_policy_version is null then ''{}''::jsonb else jsonb_build_object(''source'',c.real_source_policy_version,''source_policy_version'',c.real_source_policy_version) end into terms\n    from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster);');
  execute definition;
end;
$$;

-- A real agreement requires a positive source-policy read.  The older
-- fictional readiness fixture remains exactly where it was for null-source
-- agreements.  This patch operates on the deployed command body so later
-- privacy and quota changes are retained.
do $$
declare definition text;
  legacy_readiness text := 'if not exists(select 1 from app.challenge_readiness_v1 where actor_id=a and metric=pol->>''metric'' and recorded_at between n-(case when pol->>''metric''=''timed'' then interval ''90 days'' else interval ''30 days'' end) and n) then raise exception ''challenge_readiness_required'' using errcode=''42501''; end if;';
begin
  definition := pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
  if position(legacy_readiness in definition) = 0 then
    raise exception 'Unexpected challenge readiness source';
  end if;
  definition := replace(definition, legacy_readiness,
    'if c.real_source_policy_version is null then ' || legacy_readiness ||
    ' elsif not exists(select 1 from app.challenge_real_health_readiness_v1 readiness where readiness.actor_id=a and readiness.source_policy_version=c.real_source_policy_version and readiness.observed_at between n-interval ''30 days'' and n) then raise exception ''challenge_readiness_required'' using errcode=''42501''; end if;');
  execute definition;
end;
$$;

-- Source-aware projection lets the existing detail, Home and history readers
-- keep their membership and hidden-member checks while choosing the immutable
-- real fact ledger only for a frozen real agreement.
create function app.challenge_fact_projection_v1(p_challenge_id uuid,p_actor_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare source_version text;
begin
  select real_source_policy_version into source_version
  from app.challenge_lobbies_v1 where id = p_challenge_id;
  if source_version is null then
    return (
      select jsonb_build_object('value',value,'state',state,'recorded_at',recorded_at,'revision',revision)
      from app.challenge_facts_v1
      where challenge_id=p_challenge_id and actor_id=p_actor_id
      order by revision desc limit 1
    );
  end if;
  return (
    select jsonb_build_object('value',fact.value,'state',fact.state,'recorded_at',fact.recorded_at,'revision',fact.revision)
    from app.challenge_real_health_facts_v1 fact
    join app.challenge_lobbies_v1 lobby on lobby.id=fact.challenge_id
    where fact.challenge_id=p_challenge_id
      and fact.actor_id=p_actor_id
      and fact.agreement_version=lobby.agreement_version
    order by fact.revision desc limit 1
  );
end;
$$;

create function app.challenge_real_health_deadline_now_v1(p_challenge_id uuid)
returns timestamptz language sql stable set search_path = '' as $$
  select case when real_source_policy_version is null then app.challenge_now_v1()
              else app.challenge_real_health_now_v1() end
  from app.challenge_lobbies_v1 where id=p_challenge_id
$$;

-- The retained work inventory is also the scheduler boundary.  Real rows are
-- eligible only while their own processing switch is on; fictional rows keep
-- the fixture actor gate and its fixture clock.
create or replace function app.challenge_work_v1()
returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean)
language sql stable set search_path='' as $$
 with runtime as materialized (
  select c.id,case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end now
  from app.challenge_lobbies_v1 c
  left join app.challenge_runtime_v1 legacy on legacy.singleton
  left join app.challenge_real_health_runtime_v1 real on real.singleton
  where (c.real_source_policy_version is null and legacy.fixtures and c.creator_id=any(legacy.actors))
     or (c.real_source_policy_version is not null and real.processing_enabled)
 ), live as materialized (
  select c.id,c.status,c.starts_at,c.ends_at,r.now from app.challenge_lobbies_v1 c join runtime r on r.id=c.id
  where c.status not in ('final','void','cancelled') and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=c.id)
 ), members as materialized (
  select m.challenge_id,m.actor_id from live c join app.challenge_members_v1 m on m.challenge_id=c.id where m.selected and m.exited_at is null
 ), unavailable as materialized (select m.actor_id from members m where app.challenge_actor_unavailable_v1(m.actor_id)),
 unsafe as materialized (
  select m.challenge_id from members m join unavailable u using(actor_id)
  union select m.challenge_id from public.blocks b join members m on m.actor_id=b.blocker_id join members other on other.actor_id=b.blocked_id and other.challenge_id=m.challenge_id
 )
 select c.id,c.status,
  case when u.challenge_id is not null then c.now
   when c.status in ('lobby_open','published_open','consent_pending','scheduled') then c.starts_at
   when c.status='active' then c.ends_at
   when c.status='syncing' then c.ends_at+interval '48 hours 1 microsecond'
   when c.status='review' then case when exists(select 1 from app.challenge_reviews_v1 rv join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.decision='exclude' and s.recorded_at>n.recorded_at) then c.now else greatest(n.review_by,(select max(rv.resolve_by) from app.challenge_reviews_v1 rv left join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.review_id is null)) end
   else c.now end,
  n.challenge_id is null and c.now>c.ends_at+interval '72 hours',
  exists(select 1 from app.challenge_reviews_v1 rv left join app.challenge_resolutions_v1 s on s.review_id=rv.id where rv.challenge_id=c.id and s.review_id is null and c.now>=rv.resolve_by)
 from live c left join unsafe u on u.challenge_id=c.id left join lateral(select challenge_id,recorded_at,review_by from app.challenge_notices_v1 where challenge_id=c.id order by revision desc limit 1)n on true
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_claim_scoped_v1(jsonb,integer)'::regprocedure);
  if position('if (select processing from app.challenge_runtime_v1 where singleton) then' in definition) = 0
     or position('where due_at<=app.challenge_now_v1()' in definition) = 0 then
    raise exception 'Unexpected scoped worker source';
  end if;
  definition := replace(definition,
    'if (select processing from app.challenge_runtime_v1 where singleton) then',
    'if exists(select 1 from app.challenge_runtime_v1 where singleton and processing) or exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and processing_enabled) then');
  definition := replace(definition, 'where due_at<=app.challenge_now_v1()', 'where due_at<=app.challenge_real_health_deadline_now_v1(id)');
  execute definition;
end;
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.challenge_resolve_v1(uuid,uuid,text)'::regprocedure);
  if position('app.challenge_now_v1()>=r.resolve_by' in definition) = 0 then
    raise exception 'Unexpected challenge resolution clock';
  end if;
  definition := replace(definition, 'app.challenge_now_v1()', 'app.challenge_real_health_deadline_now_v1(r.challenge_id)');
  execute definition;
end;
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.challenge_operator_action_v1(uuid,jsonb)'::regprocedure);
  if position('app.challenge_now_v1()' in definition) = 0 then
    raise exception 'Unexpected challenge operator clock';
  end if;
  definition := replace(definition, 'app.challenge_now_v1()', 'app.challenge_real_health_deadline_now_v1(cid)');
  execute definition;
end;
$$;

do $$
declare definition text;
  legacy_fact text := '(select jsonb_build_object(''value'',value,''state'',state,''recorded_at'',recorded_at,''revision'',revision) from app.challenge_facts_v1 where challenge_id=p_id and actor_id=m.actor_id and (m.exited_at is null or m.actor_id=a) order by revision desc limit 1)';
begin
  definition := pg_get_functiondef('app.challenge_detail_for_actor_v1(uuid,uuid)'::regprocedure);
  if position(legacy_fact in definition) = 0 then
    raise exception 'Unexpected challenge detail fact projection';
  end if;
  definition := replace(definition, legacy_fact,
    'case when m.exited_at is null or m.actor_id=a then app.challenge_fact_projection_v1(p_id,m.actor_id) end');
  definition := replace(definition, '''server_time'',app.challenge_now_v1()',
    '''server_time'',app.challenge_real_health_deadline_now_v1(p_id)');
  execute definition;
end;
$$;

-- Community publication has no raw fact disclosure, but a source fact must
-- still advance the same member revision that feeds its delayed aggregate.
create trigger challenge_real_health_community_fact_state
  after insert on app.challenge_real_health_facts_v1
  for each row execute function app.challenge_community_member_state_v1();

do $$
declare definition text;
  legacy_fact text := '(select jsonb_build_object(''value'',f.value,''state'',f.state,''revision'',f.revision,''recorded_at'',f.recorded_at) from app.challenge_facts_v1 f where f.challenge_id=p_id and f.actor_id=r.actor_id order by f.revision desc limit 1)';
begin
  definition := pg_get_functiondef('public.challenge_operator_cases_v1(uuid)'::regprocedure);
  if position(legacy_fact in definition) = 0 then
    raise exception 'Unexpected challenge review fact projection';
  end if;
  definition := replace(definition, legacy_fact, 'app.challenge_fact_projection_v1(p_id,r.actor_id)');
  execute definition;
end;
$$;

-- Preserve the deployed fictional evaluator byte-for-byte, then dispatch only
-- newly source-bearing agreements to the real lower-bound evaluator.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_evaluate_v1(uuid,boolean)'::regprocedure);
  if position('create or replace function app.challenge_evaluate_v1' in lower(definition)) = 0 then
    raise exception 'Unexpected challenge evaluator source';
  end if;
  definition := replace(definition, 'app.challenge_evaluate_v1', 'app.challenge_fictional_evaluate_v1');
  execute definition;
end;
$$;

create or replace function app.challenge_evaluate_v1(p_id uuid,p_force_void boolean default false)
returns jsonb language plpgsql set search_path = '' as $$
declare challenge app.challenge_lobbies_v1;
begin
  select * into challenge from app.challenge_lobbies_v1 where id = p_id;
  if challenge.real_source_policy_version is not null then
    return app.challenge_real_health_evaluate_v1(p_id,p_force_void);
  end if;
  return app.challenge_fictional_evaluate_v1(p_id,p_force_void);
end;
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_tick_v1(uuid,boolean)'::regprocedure);
  if position('if not exists(select 1 from app.challenge_runtime_v1 where singleton and processing and fixtures) then raise exception ''challenge_processing_paused'' using errcode=''42501''; end if;' in definition) = 0 then
    raise exception 'Unexpected challenge processing source';
  end if;
  definition := replace(definition,
    'if not exists(select 1 from app.challenge_runtime_v1 where singleton and processing and fixtures) then raise exception ''challenge_processing_paused'' using errcode=''42501''; end if;',
    'if c.real_source_policy_version is null and not exists(select 1 from app.challenge_runtime_v1 where singleton and processing and fixtures) then raise exception ''challenge_processing_paused'' using errcode=''42501''; end if; if c.real_source_policy_version is not null and not exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and processing_enabled) then raise exception ''challenge_processing_paused'' using errcode=''42501''; end if;');
  definition := replace(definition,
    'select * into c from app.challenge_lobbies_v1 where id=p_id for update; n:=app.challenge_now_v1();',
    'select * into c from app.challenge_lobbies_v1 where id=p_id for update; n:=case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end;');
  execute definition;
end;
$$;

revoke all on function app.challenge_real_health_payload_v1(jsonb),
  app.challenge_real_health_evaluate_v1(uuid,boolean),
  app.challenge_fact_projection_v1(uuid,uuid),
  app.challenge_real_health_deadline_now_v1(uuid),
  app.challenge_real_health_now_v1(),
  app.challenge_real_health_runtime_guard_v1(),
  app.challenge_fictional_evaluate_v1(uuid,boolean),
  public.challenge_real_health_runtime_v1(boolean,boolean,boolean),
  public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean),
  public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)
from public, anon, authenticated, service_role;
grant execute on function public.challenge_real_health_runtime_v1(boolean,boolean,boolean) to service_role;
grant execute on function public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean) to service_role;
grant execute on function public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean) to service_role;

comment on table app.challenge_real_health_facts_v1 is
  'Private normalized lower-bound steps replacements. Empty, deleted, and unresolved reads are never scores of zero.';
comment on function public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean) is
  'Service-only P8 ingress after Edge-side exact-body App Attest verification; consumes the bound device counter atomically.';
