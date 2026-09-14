-- Approved local account-deletion protocol for the separate challenge_*_v1
-- product. This does not reinterpret historical Personal/Solo agreements or
-- turn a local retention period into a hosted operating policy.
begin;

create table app.challenge_account_deletions_v1 (
  actor_id uuid primary key references public.profiles(id) on delete restrict,
  request_id uuid not null unique,
  receipt_hash bytea not null unique,
  apple_subject_hash bytea not null,
  stripe_customer_id text,
  accepted_at timestamptz not null,
  required_steps_finished_at timestamptz not null,
  provider_cleanup_completed_at timestamptz,
  account_closed_at timestamptz,
  identity_cleanup_after timestamptz not null,
  identity_cleaned_at timestamptz,
  -- Local restore evidence retains the original event time separately from the
  -- time an older snapshot was actually scrubbed/revoked.
  identity_replayed_at timestamptz,
  account_replayed_at timestamptz,
  case_content_cleaned_at timestamptz,
  pseudonymous_retention_completed_at timestamptz,
  -- This contains no appeal content or identifier. It is the durable minimum
  -- meaning that an independent appeal decision released this deletion hold,
  -- so deleting the detailed appeal at 180 days cannot recreate a right.
  appeal_hold_released_at timestamptz,
  holds_reviewed_at timestamptz,
  check (octet_length(receipt_hash) = 32),
  check (octet_length(apple_subject_hash) = 32),
  check (stripe_customer_id is null or (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$' and octet_length(stripe_customer_id) <= 255)),
  check (identity_cleanup_after = accepted_at + interval '7 days'),
  check (required_steps_finished_at >= accepted_at),
  check (provider_cleanup_completed_at is null or provider_cleanup_completed_at >= accepted_at),
  check (account_closed_at is null or (
    provider_cleanup_completed_at is not null
    and account_closed_at >= provider_cleanup_completed_at
  )),
  check (identity_cleaned_at is null or (
    identity_replayed_at is not null or (
      identity_cleaned_at >= accepted_at
      and identity_cleaned_at <= identity_cleanup_after
    )
  ))
);

-- Exact retry receipts that contain an opaque invitation bearer are reduced to
-- their immutable request/response digests, not discarded as generic history.
create table app.challenge_deletion_request_redactions_v1 (
  actor_id uuid not null references public.profiles(id) on delete restrict,
  request_id uuid primary key,
  operation text not null,
  payload_digest text not null check (payload_digest ~ '^[0-9a-f]{64}$'),
  response_digest text not null check (response_digest ~ '^[0-9a-f]{64}$'),
  recorded_at timestamptz not null,
  redacted_at timestamptz not null
);
alter table app.challenge_deletion_request_redactions_v1 enable row level security;
revoke all on table app.challenge_deletion_request_redactions_v1
  from public, anon, authenticated, service_role;

create table app.challenge_deletion_rights_requests_v1 (
  receipt_hash bytea not null references app.challenge_account_deletions_v1(receipt_hash) on delete restrict,
  request_id uuid not null,
  payload jsonb not null,
  response jsonb not null,
  recorded_at timestamptz not null,
  primary key (receipt_hash, request_id)
);
alter table app.challenge_deletion_rights_requests_v1 enable row level security;
revoke all on table app.challenge_deletion_rights_requests_v1
  from public, anon, authenticated, service_role;

-- This is the shared-account access fence. It deliberately leaves the private
-- provider recovery binding readable only to service functions while every
-- ordinary product authorization and stale JWT check sees the accepted actor as
-- inactive immediately.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.is_active_actor(uuid)'::regprocedure);
  if position('profile.deleted_at is null' in definition) = 0 then
    raise exception 'Unexpected active actor predicate';
  end if;
  definition := replace(
    definition,
    'profile.deleted_at is null',
    'profile.deleted_at is null and not exists (select 1 from app.challenge_account_deletions_v1 deletion where deletion.actor_id = profile.id)'
  );
  execute definition;
end
$$;

comment on table app.challenge_account_deletions_v1 is
  'Local challenge-v1 deletion tombstones. The opaque receipt is stored only as a SHA-256 digest; historical account deletion remains its own D81 transaction.';

alter table app.challenge_account_deletions_v1 enable row level security;
revoke all on table app.challenge_account_deletions_v1
  from public, anon, authenticated, service_role;

-- Existing Beta entry/read helpers must treat accepted deletion as unavailable
-- immediately. Historical account access is removed by the existing D81
-- transaction only after provider cleanup succeeds; an ambiguous provider call
-- can therefore deny Beta participation without pretending account closure won.
create or replace function app.challenge_actor_unavailable_v1(a uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
 select not app.is_active_actor(a)
     or exists (
       select 1
       from app.challenge_account_deletions_v1 deletion
       where deletion.actor_id = a
     )
     or exists (
       select 1
       from app.challenge_suspensions_v1 suspension
       where suspension.actor_id = a and suspension.suspended
     )
$$;

-- Keep the existing current-session proof, but never let a previously valid
-- Beta session keep ordinary read or mutation access after acceptance.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('app.challenge_session_v1()'::regprocedure);
  if position('not app.is_active_actor(a)' in definition) = 0 then
    raise exception 'Unexpected challenge session authorization guard';
  end if;
  definition := replace(
    definition,
    'not app.is_active_actor(a)',
    'app.challenge_actor_unavailable_v1(a)'
  );
  execute definition;
end
$$;

create function app.challenge_account_deletion_receipt_hash_v1(p_secret text)
returns bytea
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if octet_length(p_secret) not between 32 and 512
     or p_secret !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'challenge_deletion_receipt_invalid'
      using errcode = '22023';
  end if;
  return extensions.digest(pg_catalog.convert_to(p_secret, 'UTF8'), 'sha256');
end
$$;

create function app.challenge_account_deletion_case_finished_at_v1(
  p_actor uuid,
  p_floor timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path = ''
as $$
  select greatest(
    p_floor,
    coalesce((
      select max(final.recorded_at)
      from app.challenge_finals_v1 final
      join app.challenge_members_v1 member on member.challenge_id = final.challenge_id
      where member.actor_id = p_actor
    ), p_floor),
    coalesce((
      select max(resolution.recorded_at)
      from app.challenge_resolutions_v1 resolution
      join app.challenge_reviews_v1 review on review.id = resolution.review_id
      join app.challenge_members_v1 member
        on member.challenge_id = review.challenge_id
      where member.actor_id = p_actor
    ), p_floor),
    coalesce((
      select max(decision.recorded_at)
      from app.challenge_appeal_decisions_v1 decision
      join app.challenge_appeals_v1 appeal on appeal.id = decision.appeal_id
      where appeal.actor_id = p_actor
    ), p_floor)
  )
$$;

create function app.challenge_account_deletion_state_v1(p_actor uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  has_review_hold boolean;
  has_appeal_hold boolean;
  case_finished_at timestamptz;
  case_content_until timestamptz;
  retained_until timestamptz;
  receipt_expires_at timestamptz;
  state text;
begin
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = p_actor;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_unknown'
      using errcode = '42501';
  end if;

  -- A deletion cannot clear facts/cases while a result for any challenge the
  -- actor participated in is still open, or while any participant's review of
  -- that shared result remains unresolved. A filed review remains until its
  -- assigned reviewer resolves it. An available or filed account appeal stays
  -- held until its independent decider resolves it (or its existing suspension
  -- is released); this workflow never invents an appeal expiry.
  select exists (
    select 1
    from app.challenge_members_v1 member
    where member.actor_id = p_actor
      and (
        not exists (
        select 1 from app.challenge_finals_v1 final
        where final.challenge_id = member.challenge_id
        )
        or exists (
          select 1
          from app.challenge_reviews_v1 review
          left join app.challenge_resolutions_v1 resolution
            on resolution.review_id = review.id
          where review.challenge_id = member.challenge_id
            and resolution.review_id is null
        )
      )
  ) into has_review_hold;

  select exists (
    select 1
    from app.challenge_suspensions_v1 suspension
    where suspension.actor_id = p_actor and suspension.suspended
      -- Once the 180-day minimum audit window has completed, this deleted
      -- identity cannot acquire a newly available appeal right. The durable
      -- tombstone remains; this only prevents a cleaned, resolved case from
      -- being made "held" again by the removed minimal appeal record.
      and deletion.appeal_hold_released_at is null
      and (
        not exists (
          select 1 from app.challenge_appeals_v1 appeal
          where appeal.actor_id = p_actor
            and appeal.suspension_at = suspension.recorded_at
        )
        or exists (
          select 1
          from app.challenge_appeals_v1 appeal
          left join app.challenge_appeal_decisions_v1 decision
            on decision.appeal_id = appeal.id
          where appeal.actor_id = p_actor
            and appeal.suspension_at = suspension.recorded_at
            and decision.appeal_id is null
        )
      )
  ) into has_appeal_hold;

  case_finished_at := app.challenge_account_deletion_case_finished_at_v1(
    p_actor,
    deletion.required_steps_finished_at
  );

  case_content_until := case_finished_at + interval '30 days';
  retained_until := case_finished_at + interval '180 days';
  if deletion.account_closed_at is null then
    state := case when deletion.provider_cleanup_completed_at is null
      then 'pending_provider' else 'pending_account_close' end;
  elsif has_review_hold or has_appeal_hold then
    state := 'held';
  else
    state := 'completed';
    receipt_expires_at := greatest(
      deletion.account_closed_at,
      case_finished_at
    ) + interval '90 days';
    if clock_timestamp() > receipt_expires_at then
      state := 'expired';
    end if;
  end if;

  return jsonb_build_object(
    'state', state,
    'request_id', deletion.request_id,
    'accepted_at', deletion.accepted_at,
    'account_closed_at', deletion.account_closed_at,
    'receipt_expires_at', receipt_expires_at,
    'holds', jsonb_build_object(
      'review', has_review_hold,
      'appeal', has_appeal_hold
    ),
    'rights', jsonb_build_object(
      'review_notices', coalesce((
        select jsonb_agg(jsonb_build_object(
          'challenge_id', notice.challenge_id,
          'notice_revision', notice.revision,
          'review_by', notice.review_by
        ) order by notice.review_by, notice.challenge_id)
        from app.challenge_notices_v1 notice
        join app.challenge_members_v1 member on member.challenge_id = notice.challenge_id
        where member.actor_id = p_actor
          and notice.review_by > clock_timestamp()
          and not exists (
            select 1 from app.challenge_finals_v1 final
            where final.challenge_id = notice.challenge_id
          )
      ), '[]'::jsonb),
      'appeal_available', exists (
        select 1 from app.challenge_suspensions_v1 suspension
        where suspension.actor_id = p_actor and suspension.suspended
          and deletion.appeal_hold_released_at is null
          and not exists (
            select 1 from app.challenge_appeals_v1 appeal
            where appeal.actor_id = p_actor
              and appeal.suspension_at = suspension.recorded_at
          )
      ),
      'holds_review_due', (has_review_hold or has_appeal_hold)
        and (deletion.holds_reviewed_at is null
          or deletion.holds_reviewed_at + interval '30 days' <= clock_timestamp())
    ),
    'retained', jsonb_build_array(
      jsonb_build_object(
        'category', 'profile and access cleanup',
        'until', deletion.identity_cleanup_after,
        'completed_at', deletion.identity_cleaned_at
      ),
      jsonb_build_object(
        'category', 'your challenge facts and case records',
        'until', case_content_until,
        'completed_at', deletion.case_content_cleaned_at
      ),
      jsonb_build_object(
        'category', 'your challenge consent, request, and operator records',
        'until', retained_until
        ,'completed_at', deletion.pseudonymous_retention_completed_at
      ),
      jsonb_build_object(
        'category', 'shared challenge agreements and final results',
        'until', retained_until,
        'completed_at', null,
        'depends_on', 'other participant and historical record schedules'
      ),
      jsonb_build_object(
        'category', 'deletion status receipt',
        'until', receipt_expires_at
      )
    )
  );
end
$$;

-- The authenticated caller is verified by the Edge adapter. This service-only
-- operation creates exactly one immutable acceptance record, ends Beta
-- participation/sharing synchronously, and asks the existing safe tick to
-- reconcile every affected simulation without rewriting an immutable final.
create function public.challenge_begin_account_deletion_v1(
  p_actor_id uuid,
  p_request_id uuid,
  p_receipt_secret text,
  p_apple_subject text,
  p_stripe_customer_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior app.challenge_account_deletions_v1;
  receipt_hash bytea;
  n timestamptz;
  challenge_id uuid;
begin
  perform app.duel_require_service_v1();
  if p_actor_id is null or p_request_id is null
     or p_apple_subject is null or octet_length(p_apple_subject) not between 1 and 255
     or p_stripe_customer_id is not null and (
       p_stripe_customer_id !~ '^cus_[A-Za-z0-9]+$'
       or octet_length(p_stripe_customer_id) > 255
     ) then
    raise exception 'challenge_deletion_request_invalid'
      using errcode = '22023';
  end if;
  receipt_hash := app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);

  -- This exclusive fence is deliberately before the profile lock. Existing
  -- challenge mutations hold the shared fence before their actor/profile locks,
  -- so an admission/review/finalization cannot slip between acceptance and the
  -- exit reconciliation or invert the profile-first historical deletion order.
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into prior
  from app.challenge_account_deletions_v1
  where actor_id = p_actor_id
  for update;
  if prior.actor_id is not null then
    if prior.request_id is distinct from p_request_id
       or prior.receipt_hash is distinct from receipt_hash then
      raise exception 'challenge_deletion_request_conflict'
        using errcode = '22023';
    end if;
    return app.challenge_account_deletion_state_v1(p_actor_id);
  end if;

  -- Do not use app.is_active_actor here: this is the one service transition
  -- that must own a still-active actor before making it unavailable to Beta.
  perform 1
  from public.profiles profile
  join app.active_profile_auth_bindings binding on binding.actor_id = profile.id
  join auth.users auth_user on auth_user.id = profile.id
  where profile.id = p_actor_id and profile.deleted_at is null
  for update of profile;
  if not found then
    raise exception 'challenge_deletion_account_unavailable'
      using errcode = '42501';
  end if;

  n := clock_timestamp();
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_account_deletions_v1(
    actor_id, request_id, receipt_hash, apple_subject_hash, stripe_customer_id,
    accepted_at, required_steps_finished_at, identity_cleanup_after
  ) values (
    p_actor_id, p_request_id, receipt_hash,
    extensions.digest(pg_catalog.convert_to(p_apple_subject, 'UTF8'), 'sha256'),
    p_stripe_customer_id, n, n, n + interval '7 days'
  );

  -- The accepted tombstone is consulted by every product authorization and the
  -- strict Edge session check, so a stale JWT cannot retain ordinary access.
  -- Do not mutate auth.sessions directly: that schema is Auth-owned. The
  -- existing D81 close removes the Auth user (and therefore its sessions) only
  -- after verified provider cleanup, while the native client clears its local
  -- session as part of this same accepted deletion flow.

  -- Bearer links issued by this actor stop working now. Their hash/receipt
  -- material is removed by the narrowly scoped seven-day cleanup below.
  update app.challenge_links_v1
  set revoked_at = coalesce(revoked_at, n)
  where issuer = p_actor_id and revoked_at is null;

  update app.challenge_members_v1
  set exited_at = n
  where actor_id = p_actor_id and exited_at is null;

  for challenge_id in
    select distinct member.challenge_id
    from app.challenge_members_v1 member
    where member.actor_id = p_actor_id
    order by member.challenge_id
  loop
    perform app.challenge_lock_v1('challenge', challenge_id);
    perform app.challenge_tick_v1(challenge_id, true);
  end loop;

  -- The approved seven-day period is a maximum, not a waiting period. Finish
  -- the narrow identifying/link/draft cleanup inside the durable acceptance
  -- transaction so a provider ambiguity cannot leave ordinary account material
  -- active or make the schedule depend on a later worker run.
  perform public.challenge_cleanup_account_deletion_v1(p_actor_id);

  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- Read only the provider bindings required by the Edge adapter. Provider IDs
-- never travel to the app. The Apple subject is read before acceptance while
-- the Auth identity still exists, then the provider response is compared to it
-- server-side before any historical deletion transaction can run.
create function public.challenge_account_deletion_provider_identity_v1(
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  apple_subject text;
  stripe_customer_id text;
begin
  if p_actor_id is null then
    raise exception 'challenge_deletion_request_invalid' using errcode = '22023';
  end if;
  select coalesce(identity.identity_data ->> 'sub', identity.provider_id)
  into apple_subject
  from auth.identities identity
  join auth.users auth_user on auth_user.id = identity.user_id
  join public.profiles profile on profile.id = auth_user.id
  where identity.user_id = p_actor_id
    and identity.provider = 'apple'
    and profile.deleted_at is null
  order by identity.created_at desc
  limit 1;
  if apple_subject is null or octet_length(apple_subject) > 255 then
    raise exception 'challenge_deletion_apple_identity_required'
      using errcode = '42501';
  end if;
  select customer.stripe_customer_id into stripe_customer_id
  from app.personal_stripe_sandbox_customers customer
  where customer.user_id = p_actor_id;
  return jsonb_build_object(
    'apple_subject', apple_subject,
    'stripe_customer_id', stripe_customer_id
  );
end
$$;

create function public.challenge_account_deletion_assert_live_session_v1(
  p_actor_id uuid,
  p_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_actor_id is null or p_session_id is null
     or not exists (
       select 1 from auth.sessions session
       join public.profiles profile on profile.id = session.user_id
       where session.id = p_session_id
         and session.user_id = p_actor_id
         and profile.deleted_at is null
         and not exists (
           select 1 from app.challenge_account_deletions_v1 deletion
           where deletion.actor_id = p_actor_id
         )
         and (session.not_after is null or session.not_after > clock_timestamp())
     ) then
    raise exception 'challenge_deletion_session_required' using errcode = '42501';
  end if;
end
$$;

create function public.challenge_account_deletion_recovery_v1(p_receipt_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
begin
  select * into deletion from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  status := app.challenge_account_deletion_state_v1(deletion.actor_id);
  if status->>'state' = 'expired' then
    raise exception 'challenge_deletion_receipt_expired' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'actor_id', deletion.actor_id,
    'request_id', deletion.request_id,
    'state', status->>'state'
  );
end
$$;

create function public.challenge_account_deletion_provider_complete_v1(
  p_actor_id uuid,
  p_request_id uuid,
  p_receipt_secret text,
  p_apple_subject text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
begin
  perform app.duel_require_service_v1();
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = p_actor_id
  for update;
  if deletion.actor_id is null
     or deletion.request_id is distinct from p_request_id
     or deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
     or deletion.apple_subject_hash is distinct from extensions.digest(pg_catalog.convert_to(p_apple_subject, 'UTF8'), 'sha256') then
    raise exception 'challenge_deletion_receipt_unknown'
      using errcode = '42501';
  end if;
  if deletion.provider_cleanup_completed_at is null then
    update app.challenge_account_deletions_v1
    set provider_cleanup_completed_at = clock_timestamp(),
        stripe_customer_id = null
    where actor_id = p_actor_id;
  end if;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- After ordinary Auth access ends, a fresh Apple authorization may be checked
-- against the persisted digest and returns only the strictly necessary local
-- test-provider customer ID. No caller can enumerate actor IDs or providers.
create function public.challenge_account_deletion_provider_recovery_v1(
  p_receipt_secret text,
  p_apple_subject text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
begin
  select * into deletion from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
  for update;
  if deletion.actor_id is null
     or deletion.apple_subject_hash is distinct from extensions.digest(pg_catalog.convert_to(p_apple_subject, 'UTF8'), 'sha256') then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'actor_id', deletion.actor_id,
    'request_id', deletion.request_id,
    'stripe_customer_id', deletion.stripe_customer_id,
    'state', (app.challenge_account_deletion_state_v1(deletion.actor_id)->>'state')
  );
end
$$;

-- D81 returns one-time historical continuation secrets. Capture nothing from
-- that response: the outer receipt reports only status and retention categories.
-- Keeping this nested call in one transaction means response loss after the
-- historical delete still leaves a durable completed marker for exact recovery.
create function public.challenge_complete_account_deletion_v1(
  p_actor_id uuid,
  p_request_id uuid,
  p_receipt_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  ignored_historical_capabilities jsonb;
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = p_actor_id
  for update;
  if deletion.actor_id is null
     or deletion.request_id is distinct from p_request_id
     or deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret) then
    raise exception 'challenge_deletion_receipt_unknown'
      using errcode = '42501';
  end if;
  if deletion.provider_cleanup_completed_at is null then
    raise exception 'challenge_deletion_provider_pending'
      using errcode = '55000';
  end if;
  if deletion.account_closed_at is null then
    select public.delete_account(p_actor_id) into ignored_historical_capabilities;
    update app.challenge_account_deletions_v1
    set account_closed_at = clock_timestamp()
    where actor_id = p_actor_id;
  end if;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- A receipt is the narrow post-auth read path. It does not reveal an actor ID,
-- profile, bearer link, raw historical continuation capability, or case body.
create function public.challenge_account_deletion_status_v1(p_receipt_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor uuid;
declare status jsonb;
begin
  select deletion.actor_id into actor
  from app.challenge_account_deletions_v1 deletion
  where deletion.receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if actor is null then
    raise exception 'challenge_deletion_receipt_unknown'
      using errcode = '42501';
  end if;
  -- The Edge adapter maps this terminal state to 410. Returning it, rather
  -- than a generic auth-shaped error, lets the app remove only this expired
  -- receipt and never start the deletion again.
  return app.challenge_account_deletion_state_v1(actor);
end
$$;

create function public.challenge_account_deletion_file_review_v1(
  p_receipt_secret text,
  p_request_id uuid,
  p_challenge_id uuid,
  p_notice_revision integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  saved app.challenge_deletion_rights_requests_v1;
  notice app.challenge_notices_v1;
  payload jsonb;
  response jsonb;
  n timestamptz;
begin
  if p_request_id is null or p_challenge_id is null or p_notice_revision is null
     or p_reason not in ('wrong_total', 'missing_activity', 'wrong_result') then
    raise exception 'challenge_deletion_review_invalid' using errcode = '22023';
  end if;
  select * into deletion from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
  for update;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  if app.challenge_account_deletion_state_v1(deletion.actor_id)->>'state' = 'expired' then
    raise exception 'challenge_deletion_receipt_expired' using errcode = '42501';
  end if;
  payload := jsonb_build_object(
    'op', 'review', 'id', p_challenge_id,
    'notice_revision', p_notice_revision, 'reason', p_reason
  );
  select * into saved from app.challenge_deletion_rights_requests_v1
  where receipt_hash = deletion.receipt_hash and request_id = p_request_id;
  if saved.request_id is not null then
    if saved.payload is distinct from payload then
      raise exception 'challenge_request_conflict' using errcode = '22023';
    end if;
    return saved.response;
  end if;
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('challenge', p_challenge_id);
  select * into notice from app.challenge_notices_v1
  where challenge_id = p_challenge_id and revision = p_notice_revision
  for update;
  n := app.challenge_now_v1();
  if notice.challenge_id is null or n >= notice.review_by
     or not exists (
       select 1 from app.challenge_members_v1 member
       where member.challenge_id = p_challenge_id and member.actor_id = deletion.actor_id
     ) or exists (
       select 1 from app.challenge_finals_v1 final where final.challenge_id = p_challenge_id
     ) then
    raise exception 'challenge_deletion_review_unavailable' using errcode = '55000';
  end if;
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_reviews_v1(
    id, challenge_id, notice_revision, actor_id, reason, filed_at, resolve_by
  ) values (
    p_request_id, p_challenge_id, p_notice_revision, deletion.actor_id,
    p_reason, n, n + interval '72 hours'
  );
  response := jsonb_build_object('saved', true, 'review_id', p_request_id, 'resolve_by', n + interval '72 hours');
  insert into app.challenge_deletion_rights_requests_v1(
    receipt_hash, request_id, payload, response, recorded_at
  ) values (deletion.receipt_hash, p_request_id, payload, response, n);
  return response;
end
$$;

create function public.challenge_account_deletion_file_appeal_v1(
  p_receipt_secret text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  saved app.challenge_deletion_rights_requests_v1;
  suspension app.challenge_suspensions_v1;
  payload jsonb := jsonb_build_object('op', 'appeal');
  response jsonb;
  n timestamptz;
begin
  if p_request_id is null then
    raise exception 'challenge_deletion_appeal_invalid' using errcode = '22023';
  end if;
  select * into deletion from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
  for update;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  if app.challenge_account_deletion_state_v1(deletion.actor_id)->>'state' = 'expired' then
    raise exception 'challenge_deletion_receipt_expired' using errcode = '42501';
  end if;
  select * into saved from app.challenge_deletion_rights_requests_v1
  where receipt_hash = deletion.receipt_hash and request_id = p_request_id;
  if saved.request_id is not null then
    if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode = '22023'; end if;
    return saved.response;
  end if;
  perform app.challenge_gate_v1(true);
  select * into suspension from app.challenge_suspensions_v1
  where actor_id = deletion.actor_id and suspended
  for update;
  if suspension.actor_id is null then
    raise exception 'challenge_deletion_appeal_unavailable' using errcode = '55000';
  end if;
  n := app.challenge_now_v1();
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_appeals_v1(id, actor_id, suspension_at, filed_at)
  values (p_request_id, deletion.actor_id, suspension.recorded_at, n)
  on conflict (actor_id, suspension_at) do nothing;
  response := jsonb_build_object('saved', true, 'appeal_id', p_request_id);
  insert into app.challenge_deletion_rights_requests_v1(
    receipt_hash, request_id, payload, response, recorded_at
  ) values (deletion.receipt_hash, p_request_id, payload, response, n);
  return response;
end
$$;

-- This is a single-account cleanup, not a project-wide retention worker. It
-- removes only short-lived identifying/access/draft/link material after seven
-- days. Pseudonymous agreements, consents, normalized facts, outcomes, cases,
-- and audit stay untouched for their separately reported 30/180-day windows.
create or replace function app.challenge_guard_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app.challenge_deletion_cleanup_v1', true), '') = 'on'
     and tg_op = 'DELETE'
     and tg_table_name in (
       'challenge_age_v1', 'challenge_access_v1', 'challenge_readiness_v1',
       'challenge_requests_v1', 'challenge_members_v1', 'challenge_lobbies_v1',
       'challenge_quotas_v1', 'challenge_facts_v1', 'challenge_reports_v1',
       'challenge_reviews_v1', 'challenge_resolutions_v1',
       'challenge_appeals_v1', 'challenge_appeal_decisions_v1',
       'challenge_consents_v1', 'challenge_operator_audit_v1',
       'challenge_exits_v1'
     ) then
    return old;
  end if;
  if current_user <> pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid = tg_relid))
     or coalesce(current_setting('app.challenge_write_v1', true), '') <> 'on' then
    raise exception 'challenge_rpc_required' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then return new; end if;
  if tg_table_name in ('challenge_runtime_v1','challenge_lobbies_v1','challenge_members_v1','challenge_slots_v1','challenge_readiness_v1') then
    if tg_op = 'UPDATE' then return new; end if;
    if tg_op = 'DELETE' and tg_table_name = 'challenge_slots_v1' then return old; end if;
  end if;
  raise exception 'challenge_immutable' using errcode = '23001';
end
$$;

create function public.challenge_cleanup_account_deletion_v1(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare n timestamptz := clock_timestamp();
declare removed_links integer := 0;
declare removed_requests integer := 0;
declare removed_drafts integer := 0;
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = p_actor_id for update;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_unknown' using errcode = '42501';
  end if;
  if deletion.identity_cleaned_at is not null
     and coalesce(current_setting('app.challenge_restore_replay_v1', true), '') <> 'on' then
    return app.challenge_account_deletion_state_v1(p_actor_id);
  end if;

  if n > deletion.identity_cleanup_after
     and coalesce(current_setting('app.challenge_restore_replay_v1', true), '') <> 'on' then
    raise exception 'challenge_deletion_identity_cleanup_overdue'
      using errcode = '55000';
  end if;
  perform set_config('app.challenge_deletion_cleanup_v1', 'on', true);
  perform set_config('app.challenge_write_v1', 'on', true);
  delete from app.challenge_redemptions_v1
  where actor_id = p_actor_id
     or link_id in (select id from app.challenge_links_v1 where issuer = p_actor_id);
  delete from app.challenge_links_v1 where issuer = p_actor_id;
  get diagnostics removed_links = row_count;
  -- Unconsented drafts carry no frozen terms/consent/result meaning. Remove
  -- them (and only them) now rather than waiting for the seven-day maximum.
  delete from app.challenge_members_v1 member
  using app.challenge_lobbies_v1 lobby
  where lobby.id = member.challenge_id
    and lobby.creator_id = p_actor_id
    and lobby.agreement_version = 0;
  delete from app.challenge_lobbies_v1
  where creator_id = p_actor_id and agreement_version = 0;
  get diagnostics removed_drafts = row_count;
  delete from app.challenge_age_v1 where actor_id = p_actor_id;
  delete from app.challenge_access_v1 where actor_id = p_actor_id;
  delete from app.challenge_readiness_v1 where actor_id = p_actor_id;
  delete from app.challenge_quotas_v1 where actor_id = p_actor_id;
  insert into app.challenge_deletion_request_redactions_v1(
    actor_id, request_id, operation, payload_digest, response_digest,
    recorded_at, redacted_at
  )
  select request.actor_id, request.request_id, request.payload ->> 'op',
    encode(extensions.digest(pg_catalog.convert_to(request.payload::text, 'UTF8'), 'sha256'), 'hex'),
    encode(extensions.digest(pg_catalog.convert_to(request.response::text, 'UTF8'), 'sha256'), 'hex'),
    request.recorded_at, n
  from app.challenge_requests_v1 request
  where request.actor_id = p_actor_id
    and request.payload ->> 'op' in ('create', 'invite', 'issue_link', 'redeem_link')
  on conflict (request_id) do nothing;
  delete from app.challenge_requests_v1
  where actor_id = p_actor_id
    and payload ->> 'op' in ('create', 'invite', 'issue_link', 'redeem_link');
  get diagnostics removed_requests = row_count;
  update app.challenge_account_deletions_v1
  set identity_cleaned_at = n,
      identity_replayed_at = case
        when coalesce(current_setting('app.challenge_restore_replay_v1', true), '') = 'on'
          then n
        else identity_replayed_at
      end
  where actor_id = p_actor_id;
  return app.challenge_account_deletion_state_v1(p_actor_id)
    || jsonb_build_object(
      'cleanup', jsonb_build_object(
        'removed_link_records', removed_links,
        'removed_request_records', removed_requests,
        'removed_drafts', removed_drafts
      )
    );
end
$$;

-- Review each unresolved deletion record at least every 30 days without
-- cancelling a notice, review, or appeal. This small, account-scoped action is
-- deliberately separate from the normal challenge worker.
create function public.challenge_review_account_deletion_holds_v1(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
begin
  perform app.duel_require_service_v1();
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = p_actor_id
  for update;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_unknown' using errcode = '42501';
  end if;
  status := app.challenge_account_deletion_state_v1(p_actor_id);
  if (status->'holds'->>'review')::boolean
     or (status->'holds'->>'appeal')::boolean then
    update app.challenge_account_deletions_v1
    set holds_reviewed_at = clock_timestamp()
    where actor_id = p_actor_id;
  end if;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- Thirty days after the relevant result and every related case have closed,
-- purge this deleted actor's detailed facts and case content. Immutable final
-- results and agreement meaning remain for the separate 180-day minimum.
create function public.challenge_cleanup_account_deletion_case_content_v1(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
declare finished_at timestamptz;
declare n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = p_actor_id for update;
  if deletion.actor_id is null or deletion.account_closed_at is null then
    raise exception 'challenge_deletion_case_cleanup_unavailable' using errcode = '55000';
  end if;
  if deletion.case_content_cleaned_at is not null then
    return app.challenge_account_deletion_state_v1(p_actor_id);
  end if;
  status := app.challenge_account_deletion_state_v1(p_actor_id);
  if (status->'holds'->>'review')::boolean
     or (status->'holds'->>'appeal')::boolean then
    raise exception 'challenge_deletion_case_hold_active' using errcode = '55000';
  end if;
  finished_at := app.challenge_account_deletion_case_finished_at_v1(
    p_actor_id, deletion.required_steps_finished_at
  );
  if n < finished_at + interval '30 days' then
    raise exception 'challenge_deletion_case_retention_active' using errcode = '55000';
  end if;
  perform set_config('app.challenge_deletion_cleanup_v1', 'on', true);
  perform set_config('app.challenge_write_v1', 'on', true);
  delete from app.challenge_resolutions_v1 resolution
  using app.challenge_reviews_v1 review
  where resolution.review_id = review.id and review.actor_id = p_actor_id;
  delete from app.challenge_reviews_v1 where actor_id = p_actor_id;
  -- A resolved appeal is the minimum pseudonymous audit that proves an
  -- independent decider released the hold. It stays until the approved
  -- 180-day stage so this cleanup cannot accidentally make the same active
  -- suspension look like a newly available appeal.
  delete from app.challenge_report_scopes_v1 scope
  using app.challenge_reports_v1 report
  where scope.report_id = report.id
    and (report.reporter = p_actor_id or report.subject = p_actor_id);
  delete from app.challenge_reports_v1
  where reporter = p_actor_id or subject = p_actor_id;
  delete from app.challenge_facts_v1 where actor_id = p_actor_id;
  update app.challenge_account_deletions_v1
  set required_steps_finished_at = greatest(required_steps_finished_at, finished_at),
      case_content_cleaned_at = n
  where actor_id = p_actor_id;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- At the approved 180-day minimum, remove the deleted actor's remaining
-- pseudonymous Beta consent/request/audit relationships. Shared immutable
-- agreements and results are intentionally not rewritten here because another
-- participant can still need their meaning.
create function public.challenge_expire_account_deletion_retention_v1(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
declare n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = p_actor_id for update;
  if deletion.actor_id is null or deletion.account_closed_at is null then
    raise exception 'challenge_deletion_retention_unavailable' using errcode = '55000';
  end if;
  if deletion.pseudonymous_retention_completed_at is not null then
    return app.challenge_account_deletion_state_v1(p_actor_id);
  end if;
  status := app.challenge_account_deletion_state_v1(p_actor_id);
  if (status->'holds'->>'review')::boolean
     or (status->'holds'->>'appeal')::boolean then
    raise exception 'challenge_deletion_case_hold_active' using errcode = '55000';
  end if;
  if deletion.case_content_cleaned_at is null
     or n < deletion.required_steps_finished_at + interval '180 days' then
    raise exception 'challenge_deletion_pseudonymous_retention_active' using errcode = '55000';
  end if;
  perform set_config('app.challenge_deletion_cleanup_v1', 'on', true);
  perform set_config('app.challenge_write_v1', 'on', true);
  delete from app.challenge_consents_v1 where actor_id = p_actor_id;
  delete from app.challenge_deletion_request_redactions_v1 where actor_id = p_actor_id;
  delete from app.challenge_deletion_rights_requests_v1
  where receipt_hash = deletion.receipt_hash;
  delete from app.challenge_appeal_decisions_v1 decision
  using app.challenge_appeals_v1 appeal
  where decision.appeal_id = appeal.id and appeal.actor_id = p_actor_id;
  delete from app.challenge_appeals_v1 where actor_id = p_actor_id;
  delete from app.challenge_operator_audit_v1 where operator_id = p_actor_id;
  delete from app.challenge_community_members_v1 where actor_id = p_actor_id;
  delete from app.challenge_exits_v1 where actor_id = p_actor_id;
  delete from app.challenge_members_v1 where actor_id = p_actor_id;
  update app.challenge_account_deletions_v1
  set pseudonymous_retention_completed_at = n
  where actor_id = p_actor_id;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- Status/resume drives only this receipt's due stages. It is deliberately
-- account-scoped: no cron, project-wide sweep, or invented retention platform
-- is introduced. Holds are reviewed without cancellation; cleanup runs only
-- once the original result/case dependencies and approved dates permit it.
create function public.challenge_advance_account_deletion_v1(p_receipt_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  status jsonb;
  finished_at timestamptz;
  n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  select * into deletion
  from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
  for update;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', deletion.actor_id);
  -- Preserve only the fact and time of an independent release. The detailed
  -- appeal/decision remains until the 180-day pseudonymous cleanup, then this
  -- marker prevents the still-active suspension from inventing a new appeal.
  if deletion.appeal_hold_released_at is null and exists (
    select 1
    from app.challenge_suspensions_v1 suspension
    join app.challenge_appeals_v1 appeal
      on appeal.actor_id = suspension.actor_id
     and appeal.suspension_at = suspension.recorded_at
    join app.challenge_appeal_decisions_v1 decision
      on decision.appeal_id = appeal.id
    where suspension.actor_id = deletion.actor_id
      and suspension.suspended
  ) then
    update app.challenge_account_deletions_v1
    set appeal_hold_released_at = n
    where actor_id = deletion.actor_id;
    select * into deletion
    from app.challenge_account_deletions_v1
    where actor_id = deletion.actor_id;
  end if;
  status := app.challenge_account_deletion_state_v1(deletion.actor_id);
  if deletion.account_closed_at is not null then
    if (status->'holds'->>'review')::boolean
       or (status->'holds'->>'appeal')::boolean then
      if deletion.holds_reviewed_at is null
         or deletion.holds_reviewed_at + interval '30 days' <= n then
        perform public.challenge_review_account_deletion_holds_v1(deletion.actor_id);
      end if;
    else
      finished_at := app.challenge_account_deletion_case_finished_at_v1(
        deletion.actor_id, deletion.required_steps_finished_at
      );
      if deletion.case_content_cleaned_at is null
         and n >= finished_at + interval '30 days' then
        perform public.challenge_cleanup_account_deletion_case_content_v1(
          deletion.actor_id
        );
      end if;
      select * into deletion
      from app.challenge_account_deletions_v1
      where actor_id = deletion.actor_id;
      if deletion.case_content_cleaned_at is not null
         and deletion.pseudonymous_retention_completed_at is null
         and n >= finished_at + interval '180 days' then
        perform public.challenge_expire_account_deletion_retention_v1(
          deletion.actor_id
        );
      end if;
    end if;
  end if;
  return app.challenge_account_deletion_state_v1(deletion.actor_id);
end
$$;

-- Entry-guarded reports and operator audit rows need the same narrow retention
-- exemption as the challenge tables above. The replacement keeps the existing
-- guard body intact and adds no general deletion privilege.
do $$
declare definition text;
declare marker text := 'begin';
begin
  definition := pg_get_functiondef('app.challenge_entry_guard_v1()'::regprocedure);
  if position(marker in definition) = 0 then
    raise exception 'Unexpected challenge entry guard';
  end if;
  definition := replace(
    definition,
    marker,
    marker || E'\n if coalesce(current_setting(''app.challenge_deletion_cleanup_v1'', true), '''') = ''on''\n'
      || E'    and tg_op = ''DELETE''\n'
      || E'    and tg_table_name in (''challenge_age_v1'', ''challenge_access_v1'', ''challenge_links_v1'', ''challenge_redemptions_v1'', ''challenge_reports_v1'', ''challenge_operator_audit_v1'') then return old; end if;'
  );
  execute definition;
end
$$;

-- A local restore operator must export this minimal immutable evidence and
-- replay/verify it before opening an older snapshot. This is intentionally not
-- a general backup product or an assertion that provider backups were erased.
create function public.challenge_account_deletion_restore_evidence_v1(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
begin
  perform app.duel_require_service_v1();
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = p_actor_id;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_unknown' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'actor_id', deletion.actor_id,
    'request_id', deletion.request_id,
    'accepted_at', deletion.accepted_at,
    'required_steps_finished_at', deletion.required_steps_finished_at,
    'provider_cleanup_completed_at', deletion.provider_cleanup_completed_at,
    'account_closed_at', deletion.account_closed_at,
    'identity_cleanup_after', deletion.identity_cleanup_after,
    'identity_cleaned_at', deletion.identity_cleaned_at,
    'case_content_cleaned_at', deletion.case_content_cleaned_at,
    'pseudonymous_retention_completed_at', deletion.pseudonymous_retention_completed_at,
    'appeal_hold_released_at', deletion.appeal_hold_released_at,
    'holds_reviewed_at', deletion.holds_reviewed_at,
    'receipt_hash', encode(deletion.receipt_hash, 'hex'),
    'apple_subject_hash', encode(deletion.apple_subject_hash, 'hex')
  );
end
$$;

-- A restore must replay verified deletion evidence before it can open an old
-- isolated snapshot. Replaying does not recreate an identity or provider
-- binding: it fences sessions and ordinary authorization immediately.
create function public.challenge_replay_account_deletion_restore_v1(
  p_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid;
  request uuid;
  accepted timestamptz;
  required_finished timestamptz;
  provider_done timestamptz;
  account_closed timestamptz;
  cleanup_after timestamptz;
  cleanup_done timestamptz;
  case_cleaned timestamptz;
  pseudonymous_done timestamptz;
  appeal_released timestamptz;
  holds_reviewed timestamptz;
  receipt_hash bytea;
  apple_hash bytea;
  existing app.challenge_account_deletions_v1;
  profile_deleted_at timestamptz;
  n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  if p_evidence is null
     or p_evidence - array[
       'actor_id', 'request_id', 'accepted_at', 'required_steps_finished_at',
       'provider_cleanup_completed_at', 'account_closed_at',
       'identity_cleanup_after', 'identity_cleaned_at', 'receipt_hash',
       'apple_subject_hash', 'case_content_cleaned_at',
       'pseudonymous_retention_completed_at', 'appeal_hold_released_at',
       'holds_reviewed_at'
     ] <> '{}'::jsonb then
    raise exception 'challenge_deletion_restore_evidence_invalid' using errcode = '22023';
  end if;
  begin
    actor := (p_evidence->>'actor_id')::uuid;
    request := (p_evidence->>'request_id')::uuid;
    accepted := (p_evidence->>'accepted_at')::timestamptz;
    required_finished := (p_evidence->>'required_steps_finished_at')::timestamptz;
    provider_done := (p_evidence->>'provider_cleanup_completed_at')::timestamptz;
    account_closed := (p_evidence->>'account_closed_at')::timestamptz;
    cleanup_after := (p_evidence->>'identity_cleanup_after')::timestamptz;
    cleanup_done := (p_evidence->>'identity_cleaned_at')::timestamptz;
    case_cleaned := (p_evidence->>'case_content_cleaned_at')::timestamptz;
    pseudonymous_done := (p_evidence->>'pseudonymous_retention_completed_at')::timestamptz;
    appeal_released := (p_evidence->>'appeal_hold_released_at')::timestamptz;
    holds_reviewed := (p_evidence->>'holds_reviewed_at')::timestamptz;
    receipt_hash := decode(p_evidence->>'receipt_hash', 'hex');
    apple_hash := decode(p_evidence->>'apple_subject_hash', 'hex');
  exception when others then
    raise exception 'challenge_deletion_restore_evidence_invalid' using errcode = '22023';
  end;
  if actor is null or request is null or accepted is null or required_finished is null
     or cleanup_after is null or octet_length(receipt_hash) <> 32
     or octet_length(apple_hash) <> 32
     or required_finished < accepted
     or (provider_done is not null and provider_done < accepted)
     or (account_closed is not null and (provider_done is null or account_closed < provider_done))
     or cleanup_after <> accepted + interval '7 days'
     or (cleanup_done is not null and (cleanup_done < accepted or cleanup_done > cleanup_after))
     or (case_cleaned is not null and account_closed is null)
     or (pseudonymous_done is not null and case_cleaned is null) then
    raise exception 'challenge_deletion_restore_evidence_invalid' using errcode = '22023';
  end if;
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', actor);
  select * into existing from app.challenge_account_deletions_v1
  where actor_id = actor for update;
  if existing.actor_id is not null then
    if existing.request_id is distinct from request
       or existing.receipt_hash is distinct from receipt_hash
       or existing.apple_subject_hash is distinct from apple_hash then
      raise exception 'challenge_deletion_restore_evidence_conflict' using errcode = '22023';
    end if;
  else
    if not exists (select 1 from public.profiles profile where profile.id = actor) then
      raise exception 'challenge_deletion_restore_evidence_required'
        using errcode = 'restrict_violation';
    end if;
    insert into app.challenge_account_deletions_v1(
      actor_id, request_id, receipt_hash, apple_subject_hash,
      accepted_at, required_steps_finished_at, provider_cleanup_completed_at,
      account_closed_at, identity_cleanup_after, identity_cleaned_at,
      case_content_cleaned_at, pseudonymous_retention_completed_at,
      appeal_hold_released_at, holds_reviewed_at
    ) values (
      actor, request, receipt_hash, apple_hash,
      accepted, required_finished, provider_done, null,
      cleanup_after, null, case_cleaned, pseudonymous_done,
      appeal_released, holds_reviewed
    );
  end if;

  -- Tombstone first; a failed replay therefore leaves the old snapshot fenced
  -- and an exact retry can finish the same one record.
  perform set_config('app.challenge_restore_replay_v1', 'on', true);
  perform public.challenge_cleanup_account_deletion_v1(actor);
  update app.challenge_account_deletions_v1
  set identity_cleaned_at = coalesce(cleanup_done, identity_cleaned_at),
      identity_replayed_at = n
  where actor_id = actor;
  delete from auth.sessions where user_id = actor;

  if account_closed is not null then
    select profile.deleted_at into profile_deleted_at
    from public.profiles profile where profile.id = actor for update;
    if profile_deleted_at is null then
      perform public.delete_account(actor);
    end if;
    if exists (select 1 from auth.users user_row where user_row.id = actor)
       or exists (select 1 from auth.sessions session where session.user_id = actor)
       or not exists (
         select 1 from public.profiles profile
         where profile.id = actor and profile.deleted_at is not null
       ) then
      raise exception 'challenge_deletion_restore_incomplete' using errcode = '55000';
    end if;
    update app.challenge_account_deletions_v1
    set provider_cleanup_completed_at = provider_done,
        account_closed_at = account_closed,
        account_replayed_at = n
    where actor_id = actor;
  elsif exists (
    select 1 from public.profiles profile
    where profile.id = actor and profile.deleted_at is not null
  ) then
    raise exception 'challenge_deletion_restore_evidence_conflict' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'restored', true,
    'ordinary_access_denied', true,
    'sessions_revoked', true,
    'identity_cleanup_replayed', true,
    'account_close_replayed', account_closed is not null
  );
end
$$;

create function app.challenge_account_deletion_restore_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from app.challenge_account_deletions_v1 deletion
    where deletion.actor_id = new.id
  ) then
    raise exception 'challenge_deletion_restore_evidence_required'
      using errcode = 'restrict_violation';
  end if;
  return new;
end
$$;

create trigger challenge_account_deletion_auth_restore_guard
before insert on auth.users
for each row execute function app.challenge_account_deletion_restore_guard_v1();

create function app.challenge_account_deletion_session_restore_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from app.challenge_account_deletions_v1 deletion
    where deletion.actor_id = new.user_id
  ) then
    raise exception 'challenge_deletion_restore_evidence_required'
      using errcode = 'restrict_violation';
  end if;
  return new;
end
$$;

create trigger challenge_account_deletion_session_restore_guard
before insert on auth.sessions
for each row execute function app.challenge_account_deletion_session_restore_guard_v1();

revoke all on function
  app.challenge_account_deletion_receipt_hash_v1(text),
  app.challenge_account_deletion_state_v1(uuid),
  app.challenge_account_deletion_restore_guard_v1(),
  app.challenge_account_deletion_session_restore_guard_v1()
from public, anon, authenticated, service_role;

revoke all on function
  public.challenge_begin_account_deletion_v1(uuid,uuid,text,text,text),
  public.challenge_account_deletion_provider_identity_v1(uuid),
  public.challenge_account_deletion_assert_live_session_v1(uuid,uuid),
  public.challenge_account_deletion_recovery_v1(text),
  public.challenge_account_deletion_provider_recovery_v1(text,text),
  public.challenge_account_deletion_provider_complete_v1(uuid,uuid,text,text),
  public.challenge_complete_account_deletion_v1(uuid,uuid,text),
  public.challenge_account_deletion_status_v1(text),
  public.challenge_account_deletion_file_review_v1(text,uuid,uuid,integer,text),
  public.challenge_account_deletion_file_appeal_v1(text,uuid),
  public.challenge_cleanup_account_deletion_v1(uuid),
  public.challenge_review_account_deletion_holds_v1(uuid),
  public.challenge_cleanup_account_deletion_case_content_v1(uuid),
  public.challenge_expire_account_deletion_retention_v1(uuid),
  public.challenge_advance_account_deletion_v1(text),
  public.challenge_account_deletion_restore_evidence_v1(uuid),
  public.challenge_replay_account_deletion_restore_v1(jsonb)
from public, anon, authenticated, service_role;

grant execute on function
  public.challenge_begin_account_deletion_v1(uuid,uuid,text,text,text),
  public.challenge_account_deletion_provider_identity_v1(uuid),
  public.challenge_account_deletion_assert_live_session_v1(uuid,uuid),
  public.challenge_account_deletion_recovery_v1(text),
  public.challenge_account_deletion_provider_recovery_v1(text,text),
  public.challenge_account_deletion_provider_complete_v1(uuid,uuid,text,text),
  public.challenge_complete_account_deletion_v1(uuid,uuid,text),
  public.challenge_account_deletion_status_v1(text),
  public.challenge_account_deletion_file_review_v1(text,uuid,uuid,integer,text),
  public.challenge_account_deletion_file_appeal_v1(text,uuid),
  public.challenge_cleanup_account_deletion_v1(uuid),
  public.challenge_review_account_deletion_holds_v1(uuid),
  public.challenge_cleanup_account_deletion_case_content_v1(uuid),
  public.challenge_expire_account_deletion_retention_v1(uuid),
  public.challenge_advance_account_deletion_v1(text),
  public.challenge_account_deletion_restore_evidence_v1(uuid),
  public.challenge_replay_account_deletion_restore_v1(jsonb)
to service_role;

commit;
