-- Focused follow-up to the approved challenge-v1 account-deletion flow. This
-- repairs only local deletion dependencies, restore bindings, retention, and
-- receipt concurrency; it neither creates a general retention worker nor
-- changes the separate historical Personal rules.
begin;

-- A draft creator is first marked exited during durable acceptance, which
-- correctly lets the normal history trigger record an exit. A draft has no
-- accepted agreement, however, so that new projection must be removed before
-- the unconsented lobby itself is removed. Otherwise its restrict FK rolls the
-- whole deletion transaction back.
create or replace function public.challenge_cleanup_account_deletion_v1(p_actor_id uuid)
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
declare profile_deleted_at timestamptz;
declare ignored_historical_capabilities jsonb;
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

  perform set_config('app.challenge_deletion_cleanup_v1', 'on', true);
  perform set_config('app.challenge_write_v1', 'on', true);
  delete from app.challenge_redemptions_v1
  where actor_id = p_actor_id
     or link_id in (select id from app.challenge_links_v1 where issuer = p_actor_id);
  delete from app.challenge_links_v1 where issuer = p_actor_id;
  get diagnostics removed_links = row_count;

  -- Unconsented drafts have neither frozen terms nor a result. Remove their
  -- derived history rows first; agreed lobbies and every historical row stay.
  delete from app.challenge_history_v1 history
  using app.challenge_lobbies_v1 lobby
  where history.challenge_id = lobby.id
    and lobby.creator_id = p_actor_id
    and lobby.agreement_version = 0;
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

  select profile.deleted_at into profile_deleted_at
  from public.profiles profile
  where profile.id = p_actor_id
  for update;
  if profile_deleted_at is null then
    select public.delete_account(p_actor_id) into ignored_historical_capabilities;
  end if;
  if exists (select 1 from auth.users user_row where user_row.id = p_actor_id)
     or exists (select 1 from auth.sessions session where session.user_id = p_actor_id)
     or not exists (
       select 1 from public.profiles profile
       where profile.id = p_actor_id and profile.deleted_at is not null
     ) then
    raise exception 'challenge_deletion_identity_cleanup_incomplete' using errcode = '55000';
  end if;
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

-- A saved review is itself the reason that another review for the same notice
-- is no longer an available right. Do not invite a signed-out person to submit
-- a duplicate that the unique case rule will reject.
do $$
declare definition text;
declare expected text := 'and notice.review_by > clock_timestamp()';
begin
  definition := pg_get_functiondef('app.challenge_account_deletion_state_v1(uuid)'::regprocedure);
  if position(expected in definition) = 0 then
    raise exception 'Unexpected account deletion state definition';
  end if;
  definition := replace(
    definition,
    expected,
    expected || E'\n          and not exists (\n'
      || E'            select 1 from app.challenge_reviews_v1 review\n'
      || E'            where review.challenge_id = notice.challenge_id\n'
      || E'              and review.notice_revision = notice.revision\n'
      || E'              and review.actor_id = p_actor\n'
      || E'          )'
  );
  execute definition;
end
$$;

-- The 30-day hold review may be invoked directly by the restricted operator
-- path or from receipt advancement. Take the same locks in the same order as
-- every other deletion transition so a direct review cannot invert a receipt
-- operation that is already waiting on the actor.
create or replace function public.challenge_review_account_deletion_holds_v1(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
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

-- Provider confirmation and recovery are durable transitions too. Discovering
-- an actor by the receipt is deliberately unlocked; once known, use the same
-- gate/actor/deletion-row order as account completion and rights filing.
create or replace function public.challenge_account_deletion_provider_complete_v1(
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
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', p_actor_id);
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = p_actor_id
  for update;
  if deletion.actor_id is null
     or deletion.request_id is distinct from p_request_id
     or deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
     or deletion.apple_subject_hash is distinct from extensions.digest(pg_catalog.convert_to(p_apple_subject, 'UTF8'), 'sha256') then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
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

create or replace function public.challenge_account_deletion_provider_recovery_v1(
  p_receipt_secret text,
  p_apple_subject text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare actor uuid;
begin
  select actor_id into actor
  from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if actor is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', actor);
  select * into deletion
  from app.challenge_account_deletions_v1
  where actor_id = actor
  for update;
  if deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret)
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

-- Every receipt operation takes the exclusive challenge gate first, then the
-- actor lock, then its deletion row. The initial lookup is not locked; it only
-- supplies the actor key needed for the common order.
create or replace function public.challenge_account_deletion_file_review_v1(
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
  actor uuid;
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
  perform app.challenge_gate_v1(true);
  select actor_id into actor from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if actor is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  perform app.challenge_lock_v1('actor', actor);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = actor for update;
  if deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret) then
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
     ) or exists (
       select 1 from app.challenge_reviews_v1 review
       where review.challenge_id = p_challenge_id
         and review.notice_revision = p_notice_revision
         and review.actor_id = deletion.actor_id
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

create or replace function public.challenge_account_deletion_file_appeal_v1(
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
  actor uuid;
  saved app.challenge_deletion_rights_requests_v1;
  suspension app.challenge_suspensions_v1;
  payload jsonb := jsonb_build_object('op', 'appeal');
  response jsonb;
  n timestamptz;
begin
  if p_request_id is null then
    raise exception 'challenge_deletion_appeal_invalid' using errcode = '22023';
  end if;
  perform app.challenge_gate_v1(true);
  select actor_id into actor from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if actor is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  perform app.challenge_lock_v1('actor', actor);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = actor for update;
  if deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret) then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  if app.challenge_account_deletion_state_v1(deletion.actor_id)->>'state' = 'expired' then
    raise exception 'challenge_deletion_receipt_expired' using errcode = '42501';
  end if;
  select * into saved from app.challenge_deletion_rights_requests_v1
  where receipt_hash = deletion.receipt_hash and request_id = p_request_id;
  if saved.request_id is not null then
    if saved.payload is distinct from payload then
      raise exception 'challenge_request_conflict' using errcode = '22023';
    end if;
    return saved.response;
  end if;
  select * into suspension from app.challenge_suspensions_v1
  where actor_id = deletion.actor_id and suspended
  for update;
  if suspension.actor_id is null or exists (
    select 1 from app.challenge_appeals_v1 appeal
    where appeal.actor_id = deletion.actor_id
      and appeal.suspension_at = suspension.recorded_at
  ) then
    raise exception 'challenge_deletion_appeal_unavailable' using errcode = '55000';
  end if;
  n := app.challenge_now_v1();
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_appeals_v1(id, actor_id, suspension_at, filed_at)
  values (p_request_id, deletion.actor_id, suspension.recorded_at, n);
  response := jsonb_build_object('saved', true, 'appeal_id', p_request_id);
  insert into app.challenge_deletion_rights_requests_v1(
    receipt_hash, request_id, payload, response, recorded_at
  ) values (deletion.receipt_hash, p_request_id, payload, response, n);
  return response;
end
$$;

create or replace function public.challenge_advance_account_deletion_v1(p_receipt_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion app.challenge_account_deletions_v1;
  actor uuid;
  status jsonb;
  finished_at timestamptz;
  n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  perform app.challenge_gate_v1(true);
  select actor_id into actor from app.challenge_account_deletions_v1
  where receipt_hash = app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret);
  if actor is null then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
  perform app.challenge_lock_v1('actor', actor);
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = actor for update;
  if deletion.receipt_hash is distinct from app.challenge_account_deletion_receipt_hash_v1(p_receipt_secret) then
    raise exception 'challenge_deletion_receipt_unknown' using errcode = '42501';
  end if;
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

-- Detailed review/report material belongs to the thirty-day case window. The
-- remaining actor request records are removed at the separate 180-day minimum.
create or replace function public.challenge_cleanup_account_deletion_case_content_v1(
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
  delete from app.challenge_deletion_rights_requests_v1
  where receipt_hash = deletion.receipt_hash;
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

create or replace function public.challenge_expire_account_deletion_retention_v1(
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
  delete from app.challenge_requests_v1 where actor_id = p_actor_id;
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

create or replace function public.challenge_account_deletion_restore_evidence_v1(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare deletion app.challenge_account_deletions_v1;
declare status jsonb;
begin
  perform app.duel_require_service_v1();
  select * into deletion from app.challenge_account_deletions_v1
  where actor_id = p_actor_id;
  if deletion.actor_id is null then
    raise exception 'challenge_deletion_unknown' using errcode = '42501';
  end if;
  status := app.challenge_account_deletion_state_v1(p_actor_id);
  return jsonb_build_object(
    'actor_id', deletion.actor_id,
    'request_id', deletion.request_id,
    'accepted_at', deletion.accepted_at,
    'required_steps_finished_at', deletion.required_steps_finished_at,
    'provider_cleanup_completed_at', deletion.provider_cleanup_completed_at,
    'account_closed_at', deletion.account_closed_at,
    -- This is included only in the restricted local operator evidence while
    -- provider cleanup is pending. It is never returned in receipt status.
    'stripe_customer_id', deletion.stripe_customer_id,
    'identity_cleanup_after', deletion.identity_cleanup_after,
    'identity_cleaned_at', deletion.identity_cleaned_at,
    'case_content_cleaned_at', deletion.case_content_cleaned_at,
    'pseudonymous_retention_completed_at', deletion.pseudonymous_retention_completed_at,
    'appeal_hold_released_at', deletion.appeal_hold_released_at,
    'holds_reviewed_at', deletion.holds_reviewed_at,
    'case_state', jsonb_build_object(
      'review_hold', (status->'holds'->>'review')::boolean,
      'appeal_hold', (status->'holds'->>'appeal')::boolean
    ),
    'receipt_hash', encode(deletion.receipt_hash, 'hex'),
    'apple_subject_hash', encode(deletion.apple_subject_hash, 'hex')
  );
end
$$;

create or replace function public.challenge_replay_account_deletion_restore_v1(
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
  stripe_customer text;
  cleanup_after timestamptz;
  cleanup_done timestamptz;
  case_cleaned timestamptz;
  pseudonymous_done timestamptz;
  appeal_released timestamptz;
  holds_reviewed timestamptz;
  authoritative_case_state jsonb;
  snapshot_status jsonb;
  authoritative_review_hold boolean;
  authoritative_appeal_hold boolean;
  receipt_hash bytea;
  apple_hash bytea;
  existing app.challenge_account_deletions_v1;
  n timestamptz := clock_timestamp();
begin
  perform app.duel_require_service_v1();
  if p_evidence is null
     or p_evidence - array[
       'actor_id', 'request_id', 'accepted_at', 'required_steps_finished_at',
       'provider_cleanup_completed_at', 'account_closed_at', 'stripe_customer_id',
       'identity_cleanup_after', 'identity_cleaned_at', 'receipt_hash',
       'apple_subject_hash', 'case_content_cleaned_at',
       'pseudonymous_retention_completed_at', 'appeal_hold_released_at',
       'holds_reviewed_at', 'case_state'
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
    stripe_customer := p_evidence->>'stripe_customer_id';
    cleanup_after := (p_evidence->>'identity_cleanup_after')::timestamptz;
    cleanup_done := (p_evidence->>'identity_cleaned_at')::timestamptz;
    case_cleaned := (p_evidence->>'case_content_cleaned_at')::timestamptz;
    pseudonymous_done := (p_evidence->>'pseudonymous_retention_completed_at')::timestamptz;
    appeal_released := (p_evidence->>'appeal_hold_released_at')::timestamptz;
    holds_reviewed := (p_evidence->>'holds_reviewed_at')::timestamptz;
    authoritative_case_state := p_evidence->'case_state';
    authoritative_review_hold := (authoritative_case_state->>'review_hold')::boolean;
    authoritative_appeal_hold := (authoritative_case_state->>'appeal_hold')::boolean;
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
     or (stripe_customer is not null and (
       stripe_customer !~ '^cus_[A-Za-z0-9]+$' or octet_length(stripe_customer) > 255
     ))
     or ((provider_done is not null or account_closed is not null) and stripe_customer is not null)
     or cleanup_after <> accepted + interval '7 days'
     or (cleanup_done is not null and (cleanup_done < accepted or cleanup_done > cleanup_after))
     or (case_cleaned is not null and account_closed is null)
     or (pseudonymous_done is not null and case_cleaned is null)
     or jsonb_typeof(authoritative_case_state) <> 'object'
     or authoritative_case_state - array['review_hold', 'appeal_hold'] <> '{}'::jsonb
     or jsonb_typeof(authoritative_case_state->'review_hold') <> 'boolean'
     or jsonb_typeof(authoritative_case_state->'appeal_hold') <> 'boolean' then
    raise exception 'challenge_deletion_restore_evidence_invalid' using errcode = '22023';
  end if;
  perform app.challenge_gate_v1(true);
  perform app.challenge_lock_v1('actor', actor);
  select * into existing from app.challenge_account_deletions_v1
  where actor_id = actor for update;
  if existing.actor_id is not null then
    if existing.request_id is distinct from request
       or existing.receipt_hash is distinct from receipt_hash
       or existing.apple_subject_hash is distinct from apple_hash
       or existing.provider_cleanup_completed_at is distinct from provider_done
       or existing.account_closed_at is distinct from account_closed
       or existing.stripe_customer_id is distinct from stripe_customer then
      raise exception 'challenge_deletion_restore_evidence_conflict' using errcode = '22023';
    end if;
  else
    if not exists (select 1 from public.profiles profile where profile.id = actor) then
      raise exception 'challenge_deletion_restore_evidence_required'
        using errcode = 'restrict_violation';
    end if;
    insert into app.challenge_account_deletions_v1(
      actor_id, request_id, receipt_hash, apple_subject_hash, stripe_customer_id,
      accepted_at, required_steps_finished_at, provider_cleanup_completed_at,
      account_closed_at, identity_cleanup_after, identity_cleaned_at,
      case_content_cleaned_at, pseudonymous_retention_completed_at,
      appeal_hold_released_at, holds_reviewed_at
    ) values (
      actor, request, receipt_hash, apple_hash, stripe_customer,
      accepted, required_finished, provider_done, null,
      cleanup_after, null, null, null,
      appeal_released, holds_reviewed
    );
  end if;

  perform set_config('app.challenge_restore_replay_v1', 'on', true);
  perform public.challenge_cleanup_account_deletion_v1(actor);
  update app.challenge_account_deletions_v1
  set identity_replayed_at = n
  where actor_id = actor;

  if exists (select 1 from auth.users user_row where user_row.id = actor)
     or exists (select 1 from auth.sessions session where session.user_id = actor)
     or not exists (
       select 1 from public.profiles profile
       where profile.id = actor and profile.deleted_at is not null
     ) then
    raise exception 'challenge_deletion_restore_incomplete' using errcode = '55000';
  end if;

  snapshot_status := app.challenge_account_deletion_state_v1(actor);
  if (snapshot_status->'holds'->>'review')::boolean is distinct from authoritative_review_hold
     or (snapshot_status->'holds'->>'appeal')::boolean is distinct from authoritative_appeal_hold then
    raise exception 'challenge_deletion_restore_case_dependency_missing'
      using errcode = 'restrict_violation',
      detail = 'The older snapshot does not match the authoritative open review or appeal state.';
  end if;
  if account_closed is not null then
    update app.challenge_account_deletions_v1
    set provider_cleanup_completed_at = provider_done,
        account_closed_at = account_closed,
        stripe_customer_id = null,
        account_replayed_at = n
    where actor_id = actor;
  end if;
  if case_cleaned is not null then
    begin
      perform public.challenge_cleanup_account_deletion_case_content_v1(actor);
    exception when sqlstate '55000' then
      raise exception 'challenge_deletion_restore_purge_dependency_missing'
        using errcode = 'restrict_violation';
    end;
    if not exists (
      select 1 from app.challenge_account_deletions_v1 deletion
      where deletion.actor_id = actor and deletion.case_content_cleaned_at is not null
    ) then
      raise exception 'challenge_deletion_restore_purge_dependency_missing'
        using errcode = 'restrict_violation';
    end if;
  end if;
  if pseudonymous_done is not null then
    begin
      perform public.challenge_expire_account_deletion_retention_v1(actor);
    exception when sqlstate '55000' then
      raise exception 'challenge_deletion_restore_purge_dependency_missing'
        using errcode = 'restrict_violation';
    end;
    if not exists (
      select 1 from app.challenge_account_deletions_v1 deletion
      where deletion.actor_id = actor
        and deletion.pseudonymous_retention_completed_at is not null
    ) then
      raise exception 'challenge_deletion_restore_purge_dependency_missing'
        using errcode = 'restrict_violation';
    end if;
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

comment on function public.challenge_replay_account_deletion_restore_v1(jsonb) is
  'Local restore replay requires the authoritative pending provider binding, if any, before it can fence an older snapshot; this is not a general backup framework.';

commit;
