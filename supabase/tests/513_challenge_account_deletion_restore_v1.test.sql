-- Local-only restore proof. These are fictional older-snapshot rows and the
-- whole test rolls back. It exercises the narrow deletion replay, not a backup
-- product or any provider/hosted restore claim.
begin;
select plan(13);

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
  'identity_cleanup_after', accepted_at + interval '7 days',
  'identity_cleaned_at', accepted_at, 'case_content_cleaned_at', null,
  'pseudonymous_retention_completed_at', null,
  'appeal_hold_released_at', accepted_at, 'holds_reviewed_at', accepted_at,
  'receipt_hash', repeat('a', 64), 'apple_subject_hash', repeat('b', 64)
) from pending
union all
select 'closed', actor_id, session_id, jsonb_build_object(
  'actor_id', actor_id, 'request_id', extensions.gen_random_uuid(),
  'accepted_at', accepted_at, 'required_steps_finished_at', accepted_at,
  'provider_cleanup_completed_at', accepted_at, 'account_closed_at', accepted_at,
  'identity_cleanup_after', accepted_at + interval '7 days',
  'identity_cleaned_at', accepted_at, 'case_content_cleaned_at', null,
  'pseudonymous_retention_completed_at', null,
  'appeal_hold_released_at', accepted_at, 'holds_reviewed_at', accepted_at,
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
  exists (select 1 from auth.users where id =
    (select actor_id from restore_fixture where name = 'pending'))
  and exists (select 1 from public.profiles where id =
    (select actor_id from restore_fixture where name = 'pending') and deleted_at is null),
  'pending replay keeps provider/account closure accurately pending without restoring access'
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

select * from finish();
rollback;
