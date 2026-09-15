-- Local-only restore proof. These are fictional older-snapshot rows and the
-- whole test rolls back. It exercises the narrow deletion replay, not a backup
-- product or any provider/hosted restore claim.
begin;
select plan(21);

create temp table restore_fixture(
  name text primary key,
  actor_id uuid not null,
  session_id uuid not null,
  evidence jsonb not null
);

with pending as (
  select extensions.gen_random_uuid() as actor_id,
         extensions.gen_random_uuid() as session_id,
         clock_timestamp() as accepted_at
), closed as (
  select extensions.gen_random_uuid() as actor_id,
         extensions.gen_random_uuid() as session_id,
         clock_timestamp() as accepted_at
)
insert into restore_fixture(name, actor_id, session_id, evidence)
select 'pending', actor_id, session_id, jsonb_build_object(
  'actor_id', actor_id, 'request_id', extensions.gen_random_uuid(),
  'accepted_at', accepted_at, 'required_steps_finished_at', accepted_at,
  'provider_cleanup_completed_at', null, 'account_closed_at', null,
  'stripe_customer_id', 'cus_restorepending',
  'identity_cleanup_after', accepted_at + interval '7 days',
  'identity_cleaned_at', accepted_at, 'case_content_cleaned_at', null,
  'pseudonymous_retention_completed_at', null,
  'appeal_hold_released_at', accepted_at, 'holds_reviewed_at', accepted_at,
  'case_state', jsonb_build_object('review_hold', false, 'appeal_hold', false),
  'receipt_hash', encode(extensions.digest(pg_catalog.convert_to(
    'local_restore_pending_receipt_012345678901234567890123456789', 'UTF8'
  ), 'sha256'), 'hex'),
  'apple_subject_hash', encode(extensions.digest(pg_catalog.convert_to(
    'fictional-restore-pending-apple', 'UTF8'
  ), 'sha256'), 'hex')
) from pending
union all
select 'closed', actor_id, session_id, jsonb_build_object(
  'actor_id', actor_id, 'request_id', extensions.gen_random_uuid(),
  'accepted_at', accepted_at, 'required_steps_finished_at', accepted_at,
  'provider_cleanup_completed_at', accepted_at, 'account_closed_at', accepted_at,
  'stripe_customer_id', null,
  'identity_cleanup_after', accepted_at + interval '7 days',
  'identity_cleaned_at', accepted_at, 'case_content_cleaned_at', null,
  'pseudonymous_retention_completed_at', null,
  'appeal_hold_released_at', accepted_at, 'holds_reviewed_at', accepted_at,
  'case_state', jsonb_build_object('review_hold', false, 'appeal_hold', false),
  'receipt_hash', repeat('c', 64), 'apple_subject_hash', repeat('d', 64)
) from closed;

insert into auth.users(id) select actor_id from restore_fixture;
insert into public.profiles(id, handle, display_name, timezone)
select actor_id, 'restore' || right(replace(actor_id::text, '-', ''), 12),
  'Fictional restore', 'UTC'
from restore_fixture;
insert into auth.sessions(id, user_id)
select session_id, actor_id from restore_fixture;

select throws_ok(
  $$select public.challenge_replay_account_deletion_restore_v1('{}'::jsonb)$$,
  '22023', 'challenge_deletion_restore_evidence_invalid',
  'partial restore evidence cannot open an older snapshot'
);
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_fixture where name = 'pending')
  )$$,
  'accepted pending deletion replays before any older snapshot can become active'
);
select is(
  (select count(*) from auth.sessions where user_id =
    (select actor_id from restore_fixture where name = 'pending')),
  0::bigint,
  'pending replay actually revokes restored sessions'
);
select ok(
  not exists (select 1 from auth.users where id =
    (select actor_id from restore_fixture where name = 'pending'))
  and exists (select 1 from public.profiles where id =
    (select actor_id from restore_fixture where name = 'pending') and deleted_at is not null),
  'pending replay restores the local identity tombstone while leaving provider completion accurately pending'
);
select ok(
  (select identity_replayed_at is not null
   and appeal_hold_released_at is not null
   and holds_reviewed_at is not null
   from app.challenge_account_deletions_v1
   where actor_id = (select actor_id from restore_fixture where name = 'pending')),
  'pending replay records actual cleanup while preserving minimal hold-release meaning'
);
select throws_ok(
  $$insert into auth.sessions(id, user_id) values (
    extensions.gen_random_uuid(),
    (select actor_id from restore_fixture where name = 'pending')
  )$$,
  '23001', 'challenge_deletion_restore_evidence_required',
  'a pending deletion cannot mint a replacement ordinary session after restore'
);
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_fixture where name = 'pending')
  )$$,
  'pending restore replay is idempotent after interruption'
);
select is(
  (select public.challenge_account_deletion_provider_recovery_v1(
    'local_restore_pending_receipt_012345678901234567890123456789',
    'fictional-restore-pending-apple'
  )->>'stripe_customer_id'),
  'cus_restorepending',
  'pending restore preserves the exact fictional provider binding needed for later local recovery'
);
select lives_ok(
  $$select public.challenge_account_deletion_provider_complete_v1(
    (select actor_id from restore_fixture where name = 'pending'),
    ((select evidence from restore_fixture where name = 'pending')->>'request_id')::uuid,
    'local_restore_pending_receipt_012345678901234567890123456789',
    'fictional-restore-pending-apple'
  )$$,
  'only an explicit matching provider completion clears the restored pending binding'
);
select lives_ok(
  $$select public.challenge_complete_account_deletion_v1(
    (select actor_id from restore_fixture where name = 'pending'),
    ((select evidence from restore_fixture where name = 'pending')->>'request_id')::uuid,
    'local_restore_pending_receipt_012345678901234567890123456789'
  )$$,
  'the restored request completes only after the explicit fictional provider step'
);
select is(
  (select app.challenge_account_deletion_state_v1(
    (select actor_id from restore_fixture where name = 'pending')
  )->>'state'),
  'completed',
  'provider recovery never falsely reports a pending restored receipt as completed'
);
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_fixture where name = 'closed')
  )$$,
  'closed deletion replays historical account closure against the restored snapshot'
);
select is(
  (select count(*) from auth.users where id =
    (select actor_id from restore_fixture where name = 'closed')),
  0::bigint,
  'closed replay actually removes the restored Auth identity'
);
select is(
  (select count(*) from auth.sessions where user_id =
    (select actor_id from restore_fixture where name = 'closed')),
  0::bigint,
  'closed replay leaves no restored session'
);
select ok(
  exists (select 1 from public.profiles where id =
    (select actor_id from restore_fixture where name = 'closed') and deleted_at is not null),
  'closed replay applies the historical profile tombstone instead of copying a completion time'
);
select is(
  (select account_replayed_at is not null
   and account_closed_at is not null
   from app.challenge_account_deletions_v1
   where actor_id = (select actor_id from restore_fixture where name = 'closed'))::text,
  'true',
  'closed replay records the actual account-close reconciliation'
);
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_fixture where name = 'closed')
  )$$,
  'closed restore replay is idempotent and cannot resurrect identity or access'
);

-- Completion markers from a newer authority cannot be copied over stale old
-- facts. The replay must perform the same bounded purges before recording its
-- own completion time.
create temp table restore_purge_fixture(
  actor_id uuid primary key,
  session_id uuid not null,
  challenge_id uuid not null,
  evidence jsonb not null
);
with fixture as (
  select extensions.gen_random_uuid() as actor_id,
         extensions.gen_random_uuid() as session_id,
         extensions.gen_random_uuid() as challenge_id,
         clock_timestamp() - interval '200 days' as accepted_at
)
insert into restore_purge_fixture(actor_id, session_id, challenge_id, evidence)
select actor_id, session_id, challenge_id, jsonb_build_object(
    'actor_id', actor_id, 'request_id', extensions.gen_random_uuid(),
    'accepted_at', accepted_at, 'required_steps_finished_at', accepted_at,
    'provider_cleanup_completed_at', accepted_at, 'account_closed_at', accepted_at,
    'stripe_customer_id', null,
    'identity_cleanup_after', accepted_at + interval '7 days',
    'identity_cleaned_at', accepted_at + interval '7 days',
    'case_content_cleaned_at', accepted_at + interval '31 days',
    'pseudonymous_retention_completed_at', accepted_at + interval '181 days',
    'appeal_hold_released_at', null, 'holds_reviewed_at', null,
    'case_state', jsonb_build_object('review_hold', false, 'appeal_hold', false),
    'receipt_hash', repeat('e', 64), 'apple_subject_hash', repeat('f', 64)
  ) from fixture;

insert into auth.users(id) select actor_id from restore_purge_fixture;
insert into public.profiles(id, handle, display_name, timezone)
select actor_id, 'purge' || right(replace(actor_id::text, '-', ''), 12),
  'Fictional purge restore', 'UTC'
from restore_purge_fixture;
insert into auth.sessions(id, user_id)
select session_id, actor_id from restore_purge_fixture;

select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_lobbies_v1(
  id, creator_id, policy, config, starts_at, ends_at, status, revision,
  agreement_version, created_at
)
select challenge_id, actor_id, 'friend_steps_goal_v1', '{}'::jsonb,
  accepted_at - interval '2 days', accepted_at - interval '1 day', 'final',
  1, 1, accepted_at - interval '3 days'
from (
  select actor_id, challenge_id, (evidence->>'accepted_at')::timestamptz as accepted_at
  from restore_purge_fixture
) created;
insert into app.challenge_agreements_v1(challenge_id, version, terms, created_at)
select challenge_id, 1, '{"kind":"fictional"}'::jsonb,
  (evidence->>'accepted_at')::timestamptz
from restore_purge_fixture;
insert into app.challenge_members_v1(challenge_id, actor_id, selected)
select challenge_id, actor_id, true from restore_purge_fixture;
insert into app.challenge_finals_v1(challenge_id, result, recorded_at, revision)
select challenge_id, '{"kind":"fictional"}'::jsonb,
  (evidence->>'accepted_at')::timestamptz, 1
from restore_purge_fixture;
insert into app.challenge_facts_v1(
  challenge_id, actor_id, revision, value, state, recorded_at, request_id
)
select challenge_id, actor_id, 1, 42, 'complete',
  (evidence->>'accepted_at')::timestamptz, extensions.gen_random_uuid()
from restore_purge_fixture;
insert into app.challenge_deletion_request_redactions_v1(
  actor_id, request_id, operation, payload_digest, response_digest, recorded_at, redacted_at
)
select actor_id, extensions.gen_random_uuid(), 'fictional', repeat('a', 64),
  repeat('b', 64), (evidence->>'accepted_at')::timestamptz,
  (evidence->>'accepted_at')::timestamptz
from restore_purge_fixture;
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_purge_fixture)
  )$$,
  'replay reapplies completed case and pseudonymous purges to older facts'
);
select ok(
  not exists (
    select 1 from app.challenge_facts_v1 fact
    join restore_purge_fixture fixture on fixture.actor_id = fact.actor_id
  ) and not exists (
    select 1 from app.challenge_deletion_request_redactions_v1 redaction
    join restore_purge_fixture fixture on fixture.actor_id = redaction.actor_id
  ),
  'older case facts and pseudonymous request records are actually removed'
);
select ok(
  (select deletion.case_content_cleaned_at is distinct from
      (fixture.evidence->>'case_content_cleaned_at')::timestamptz
    and deletion.pseudonymous_retention_completed_at is distinct from
      (fixture.evidence->>'pseudonymous_retention_completed_at')::timestamptz
   from app.challenge_account_deletions_v1 deletion
   join restore_purge_fixture fixture on fixture.actor_id = deletion.actor_id),
  'replay records fresh purge completion rather than copying evidence times'
);

-- A review opened after an old snapshot must not disappear just because the
-- snapshot has no row for it. The authoritative open-case state is a required
-- dependency, not a cue to invent a result or release a hold.
with missing_hold as (
  select extensions.gen_random_uuid() as actor_id,
         extensions.gen_random_uuid() as session_id,
         clock_timestamp() as accepted_at
)
insert into restore_fixture(name, actor_id, session_id, evidence)
select 'missing-hold', actor_id, session_id, jsonb_build_object(
  'actor_id', actor_id, 'request_id', extensions.gen_random_uuid(),
  'accepted_at', accepted_at, 'required_steps_finished_at', accepted_at,
  'provider_cleanup_completed_at', accepted_at, 'account_closed_at', null,
  'stripe_customer_id', null,
  'identity_cleanup_after', accepted_at + interval '7 days',
  'identity_cleaned_at', null, 'case_content_cleaned_at', null,
  'pseudonymous_retention_completed_at', null,
  'appeal_hold_released_at', null, 'holds_reviewed_at', accepted_at,
  'case_state', jsonb_build_object('review_hold', true, 'appeal_hold', false),
  'receipt_hash', repeat('1', 64), 'apple_subject_hash', repeat('2', 64)
) from missing_hold;
insert into auth.users(id)
select actor_id from restore_fixture where name = 'missing-hold';
insert into public.profiles(id, handle, display_name, timezone)
select actor_id, 'hold' || right(replace(actor_id::text, '-', ''), 12),
  'Fictional missing hold', 'UTC'
from restore_fixture where name = 'missing-hold';
insert into auth.sessions(id, user_id)
select session_id, actor_id from restore_fixture where name = 'missing-hold';
select throws_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from restore_fixture where name = 'missing-hold')
  )$$,
  '23001', 'challenge_deletion_restore_case_dependency_missing',
  'replay fails closed when an authoritative open review is absent from the older snapshot'
);

select * from finish();
rollback;
