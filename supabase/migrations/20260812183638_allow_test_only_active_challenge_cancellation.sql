-- Internal Stage A challenges carry no payment-provider agreement. Let their
-- owner end an open fixture at any time so stale local test data does not block
-- the next implementation pass. Provider-backed challenges retain the binding
-- pre-start-only cancellation boundary.

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
          'app.personal_test_cleanup_challenge_id',
          true
        ) = old.id::text,
        false
      )
      and exists (
        select 1
        from public.personal_challenge_terms terms
        where terms.challenge_id = old.id
      )
      and not exists (
        select 1
        from app.personal_stripe_sandbox_agreements agreement
        where agreement.challenge_id = old.id
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
  'Forward-only lifecycle. Active internal test-only Personal challenges may be cancelled for fixture cleanup; provider-backed challenges remain binding after start.';

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
  v_challenge_id    uuid := $1;
  v_request_id      uuid := $2;
  v_actor_id        uuid;
  v_payload_hash    bytea;
  v_existing        app.personal_challenge_cancellation_requests;
  v_contest         public.contests;
  v_now             timestamptz;
  v_is_internal_test boolean;
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

  select
    exists (
      select 1
      from public.personal_challenge_terms terms
      where terms.challenge_id = v_challenge_id
    )
    and not exists (
      select 1
      from app.personal_stripe_sandbox_agreements agreement
      where agreement.challenge_id = v_challenge_id
    )
  into v_is_internal_test;

  if (
    v_is_internal_test
    and v_contest.status not in ('pending', 'active')
  ) or (
    not v_is_internal_test
    and (
      v_contest.status <> 'pending'
      or v_now >= v_contest.starts_at
    )
  ) then
    raise exception 'a personal challenge can be cancelled only before it begins'
      using errcode = 'restrict_violation';
  end if;

  perform pg_catalog.set_config(
    'app.personal_test_cleanup_challenge_id',
    v_challenge_id::text,
    true
  );

  update public.contests contest
  set status = 'cancelled',
      cancellation_reason = 'creator_cancelled',
      cancelled_at = v_now,
      activated_at = null
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
  'Owner-only exact-retry cancellation. Provider-backed challenges are pre-start only; internal test-only challenges may be ended while open for fixture cleanup.';
