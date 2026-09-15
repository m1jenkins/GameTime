-- The September 14 account-deletion approval sets seven days as the maximum
-- for identifying profile/contact/access data. Provider ambiguity must not
-- stretch that maximum or turn a pending receipt into a fake completion. The
-- accepted local transaction therefore removes that identity immediately,
-- after the Edge adapter has captured the minimal provider binding it needs
-- for a later retry. This remains a one-account workflow, not a scheduler or
-- generalized retention framework.
begin;

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

  -- D81 owns the profile/Auth ordering and creates the retained historical
  -- continuation records without exposing their one-time secrets here. It is
  -- intentionally independent of Apple/Stripe acknowledgement: pending
  -- provider work is recoverable only through this request's receipt.
  select profile.deleted_at into profile_deleted_at
  from public.profiles profile
  where profile.id = p_actor_id
  for update;
  if profile_deleted_at is null then
    select public.delete_account(p_actor_id) into ignored_historical_capabilities;
  end if;

  -- A restore replay may find the tombstone installed by its first attempt.
  -- In either case, do not stamp this field until the identifying profile and
  -- Auth/session access are actually gone.
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

-- Completion is still provider-gated for an accurate receipt, but its local
-- identity work was already performed at acceptance. A response loss or exact
-- provider retry must therefore finish this one record without replaying D81.
create or replace function public.challenge_complete_account_deletion_v1(
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
  profile_deleted_at timestamptz;
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
    set account_closed_at = clock_timestamp()
    where actor_id = p_actor_id;
  end if;
  return app.challenge_account_deletion_state_v1(p_actor_id);
end
$$;

-- Restore evidence is replayed before an older isolated snapshot can open.
-- A pending provider receipt already represents an accepted local identity
-- deletion, so replay must reinstall that tombstone rather than leaving the
-- snapshot's profile/Auth identity active until a provider eventually replies.
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
       'provider_cleanup_completed_at', 'account_closed_at',
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
      cleanup_after, null, null, null,
      appeal_released, holds_reviewed
    );
  end if;

  -- The outer restore environment remains isolated until this RPC commits: an
  -- exception rolls this insert back with the rest of the transaction. Once it
  -- commits, D81's tombstone fences ordinary access and exact retry can finish
  -- the same one record without recreating the identity.
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
        account_replayed_at = n
    where actor_id = actor;
  end if;

  -- Completion timestamps are never copied into an older snapshot. Reapply
  -- each due, bounded purge and let that operation record its actual replay
  -- time. If old data or a now-missing dependency makes a purge impossible,
  -- leave the restore transaction uncommitted and require the operator to
  -- reconcile it while the snapshot remains isolated.
  if case_cleaned is not null then
    begin
      perform public.challenge_cleanup_account_deletion_case_content_v1(actor);
    exception when sqlstate '55000' then
      raise exception 'challenge_deletion_restore_purge_dependency_missing'
        using errcode = 'restrict_violation';
    end;
    if not exists (
      select 1 from app.challenge_account_deletions_v1 deletion
      where deletion.actor_id = actor
        and deletion.case_content_cleaned_at is not null
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

comment on function public.challenge_cleanup_account_deletion_v1(uuid) is
  'September 14 scoped deletion: remove Beta draft/link/access material and apply D81 profile/Auth deletion at durable acceptance; provider completion remains a separate recoverable receipt stage.';

commit;
