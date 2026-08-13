-- Let an owner end a still-running Personal challenge only when its frozen
-- terms cannot move money: either the internal test-only path has no provider
-- agreement, or the retained Stripe agreement is explicitly sandbox and
-- livemode=false. Scheduled pre-start cancellation remains the ordinary path.

alter table public.contests
  drop constraint contests_activated_at_requires_activation,
  add constraint contests_activated_at_requires_activation check (
    activated_at is null
    or status in ('active', 'finalized')
    or (
      status = 'cancelled'
      and challenge_model = 'personal_accountability'
    )
  );

comment on constraint contests_activated_at_requires_activation
  on public.contests is
  'An activation timestamp is retained after an active sandbox challenge is cancelled; never-started cancellations keep it null.';

create function app.personal_sandbox_active_cancellation_allowed_v1(
  p_challenge_id uuid,
  p_owner_id     uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.personal_challenge_terms terms
    where terms.challenge_id = p_challenge_id
      and terms.user_id = p_owner_id
      and terms.settlement_mode = 'test_only'
  )
  and (
    not exists (
      select 1
      from app.personal_stripe_sandbox_agreements agreement
      where agreement.challenge_id = p_challenge_id
    )
    or exists (
      select 1
      from app.personal_stripe_sandbox_agreements agreement
      where agreement.challenge_id = p_challenge_id
        and agreement.user_id = p_owner_id
        and agreement.provider = 'stripe'
        and agreement.environment = 'sandbox'
        and not agreement.livemode
    )
  )
$$;

comment on function app.personal_sandbox_active_cancellation_allowed_v1(
  uuid, uuid
) is
  'Private fail-closed classifier for active Personal cancellation: internal test_only without an agreement, or an exact Stripe sandbox livemode=false agreement.';

revoke all on function app.personal_sandbox_active_cancellation_allowed_v1(
  uuid, uuid
) from public, anon, authenticated, service_role;

create or replace function app.enforce_contest_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'pending' and new.status in ('active', 'cancelled'))
    or (old.status = 'active' and new.status = 'finalized')
    or (
      old.status = 'active'
      and new.status = 'cancelled'
      and old.challenge_model = 'personal_accountability'
      and new.challenge_model = 'personal_accountability'
      and new.cancellation_reason = 'creator_cancelled'
      and new.cancelled_at is not null
      and coalesce(
        pg_catalog.current_setting(
          'app.personal_sandbox_cancellation_challenge_id',
          true
        ) = old.id::text,
        false
      )
      and app.personal_sandbox_active_cancellation_allowed_v1(
        old.id,
        old.created_by
      )
    )
  ) then
    raise exception 'contest status cannot move from % to %', old.status, new.status
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.enforce_contest_status_transition() is
  'Forward-only lifecycle. A transaction-scoped owner cancellation may end an active internal test-only or Stripe sandbox livemode=false Personal challenge; live-fee and non-Personal challenges remain binding after start.';

-- A cancelled v2 snapshot is retained as history. Final publication still
-- copies the snapshot into the immutable result and removes the mutable row.
create or replace function app.delete_personal_health_snapshot_on_terminal_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.challenge_model = 'personal_accountability'
     and old.status = 'active'
     and new.status = 'finalized'
  then
    delete from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id = new.id;
  end if;
  return new;
end;
$$;

comment on function app.delete_personal_health_snapshot_on_terminal_v2() is
  'Removes the mutable Health snapshot only after result finalization; cancelled challenge snapshots remain retained history.';

create or replace function public.cancel_personal_challenge_v1(
  challenge_id uuid,
  request_id   uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_challenge_id       uuid := $1;
  v_request_id         uuid := $2;
  v_actor_id           uuid;
  v_payload_hash       bytea;
  v_existing           app.personal_challenge_cancellation_requests;
  v_contest            public.contests;
  v_now                timestamptz;
  v_active_sandbox_ok  boolean;
begin
  v_actor_id := app.require_active_caller();

  if v_challenge_id is null or v_request_id is null then
    raise exception 'challenge and request UUID are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'cancel_personal_accountability_v1',
        'challenge_id', v_challenge_id
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select request.* into v_existing
  from app.personal_challenge_cancellation_requests request
  where request.actor_id = v_actor_id
    and request.request_id = v_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash <> v_payload_hash
       or v_existing.challenge_id <> v_challenge_id
    then
      raise exception 'request UUID already used for a different cancellation'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = v_challenge_id
  for update;

  v_now := clock_timestamp();

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from v_actor_id
  then
    raise exception 'personal challenge not found'
      using errcode = 'insufficient_privilege';
  end if;

  v_active_sandbox_ok :=
    app.personal_sandbox_active_cancellation_allowed_v1(
      v_challenge_id,
      v_actor_id
    );

  if not (
    (
      v_contest.status = 'pending'
      and v_now < v_contest.starts_at
    )
    or (
      v_contest.status = 'active'
      and v_now < v_contest.ends_at
      and v_active_sandbox_ok
    )
  ) then
    raise exception 'a personal challenge can be cancelled only while scheduled or active in an approved test sandbox'
      using errcode = 'restrict_violation';
  end if;

  perform pg_catalog.set_config(
    'app.personal_sandbox_cancellation_challenge_id',
    v_challenge_id::text,
    true
  );

  update public.contests contest
  set status = 'cancelled',
      cancellation_reason = 'creator_cancelled',
      cancelled_at = v_now
  where contest.id = v_challenge_id;

  update public.personal_challenge_terms terms
  set closed_at = v_now
  where terms.challenge_id = v_challenge_id
    and terms.user_id = v_actor_id
    and terms.closed_at is null;

  insert into app.personal_challenge_cancellation_requests (
    actor_id,
    request_id,
    payload_hash,
    challenge_id
  )
  values (
    v_actor_id,
    v_request_id,
    v_payload_hash,
    v_challenge_id
  );

  return v_challenge_id;
end;
$$;

comment on function public.cancel_personal_challenge_v1(uuid, uuid) is
  'Owner-only exact-retry cancellation. Scheduled Personal challenges remain pre-start cancellable; active cancellation is limited to internal test_only or retained Stripe sandbox livemode=false agreements before the challenge end.';
