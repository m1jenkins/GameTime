-- Local-only account-deletion regression coverage. Every actor, Apple subject,
-- receipt, and result below is fictional and the transaction always rolls back.
begin;
select plan(27);
\ir fixtures/challenge-fixture.inc

select pg_temp.login_beta(1);
insert into beta_ids values ('deletion_pair', pg_temp.beta_group(1, 2));
reset role;

-- A separate closed fictional result lets the retention boundary exercise the
-- post-final path. It is inserted only in this rollback-only service fixture;
-- production deletion never writes or replaces an immutable final.
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_finals_v1(challenge_id, result, recorded_at, revision)
values (
  (select id from beta_ids where name = 'deletion_pair'),
  '{"kind":"void","reason":"fictional_fixture"}'::jsonb,
  clock_timestamp() - interval '181 days',
  1
);

create temp table deletion_fixture as
select
  pg_temp.ba(1) as actor_id,
  pg_temp.br(1) as session_id,
  (select id from beta_ids where name = 'deletion_pair') as challenge_id,
  'local_deletion_receipt_012345678901234567890123456789'::text as receipt,
  'd1000000-0000-4000-8000-000000000001'::uuid as request_id,
  'fictional-apple-subject-1'::text as apple_subject;

select lives_ok(
  $$select public.challenge_begin_account_deletion_v1(
    (select actor_id from deletion_fixture),
    (select request_id from deletion_fixture),
    (select receipt from deletion_fixture),
    (select apple_subject from deletion_fixture)
  )$$,
  'service acceptance writes the one deletion request'
);
select ok(
  not app.is_active_actor((select actor_id from deletion_fixture)),
  'accepted deletion immediately denies all ordinary active-actor access'
);
select is(
  (select count(*) from app.challenge_members_v1
   where actor_id = (select actor_id from deletion_fixture) and exited_at is null),
  0::bigint,
  'accepted deletion exits every active Beta membership without rewriting a final'
);
select ok(
  (select identity_cleaned_at is not null
   from app.challenge_account_deletions_v1
   where actor_id = (select actor_id from deletion_fixture)),
  'the truthful identity-cleanup marker is written only after local deletion at acceptance'
);
select is(
  (select count(*) from auth.users where id = (select actor_id from deletion_fixture)),
  0::bigint,
  'a pending provider receipt does not retain the fictional Auth identifier'
);
select is(
  (select count(*) from auth.sessions where user_id = (select actor_id from deletion_fixture)),
  0::bigint,
  'a pending provider receipt revokes every ordinary session at acceptance'
);
select ok(
  exists (
    select 1 from public.profiles
    where id = (select actor_id from deletion_fixture) and deleted_at is not null
  ),
  'a pending provider receipt applies the historical profile tombstone at acceptance'
);
select is(
  (select app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))->>'state'),
  'pending_provider',
  'a durable accepted request remains accurately pending while provider cleanup is unresolved'
);
with elapsed as (
  select clock_timestamp() - interval '8 days' as accepted_at
)
update app.challenge_account_deletions_v1 deletion
set accepted_at = elapsed.accepted_at,
    required_steps_finished_at = elapsed.accepted_at,
    identity_cleanup_after = elapsed.accepted_at + interval '7 days',
    identity_cleaned_at = elapsed.accepted_at
from elapsed
where deletion.actor_id = (select actor_id from deletion_fixture);
select lives_ok(
  $$select public.challenge_advance_account_deletion_v1(
    (select receipt from deletion_fixture)
  )$$,
  'an interrupted pending-provider receipt remains recoverable after the seven-day maximum'
);
select ok(
  (select app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))->>'state') = 'pending_provider'
  and not exists (select 1 from auth.users where id = (select actor_id from deletion_fixture))
  and exists (
    select 1 from public.profiles
    where id = (select actor_id from deletion_fixture) and deleted_at is not null
  ),
  'after seven days a pending provider receipt still denies identifiers and does not claim completion'
);
select lives_ok(
  $$select public.challenge_account_deletion_provider_recovery_v1(
    (select receipt from deletion_fixture),
    (select apple_subject from deletion_fixture)
  )$$,
  'the persisted receipt and matching fictional Apple subject recover pending provider work after local identity deletion'
);
select throws_ok(
  $$select public.challenge_begin_account_deletion_v1(
    (select actor_id from deletion_fixture),
    'd1000000-0000-4000-8000-000000000002'::uuid,
    'local_deletion_receipt_012345678901234567890123456789',
    'fictional-apple-subject-1'
  )$$,
  '22023', 'challenge_deletion_request_conflict',
  'a different duplicate cannot repeat account effects'
);

select lives_ok(
  $$select public.challenge_account_deletion_provider_complete_v1(
    (select actor_id from deletion_fixture),
    (select request_id from deletion_fixture),
    (select receipt from deletion_fixture),
    (select apple_subject from deletion_fixture)
  )$$,
  'the fictional provider completion is bound to its saved Apple subject'
);
select throws_ok(
  $$select public.challenge_account_deletion_provider_complete_v1(
    (select actor_id from deletion_fixture),
    (select request_id from deletion_fixture),
    (select receipt from deletion_fixture),
    'fictional-apple-subject-other'
  )$$,
  '42501', 'challenge_deletion_receipt_unknown',
  'a different Apple subject cannot complete the accepted request'
);
select lives_ok(
  $$select public.challenge_complete_account_deletion_v1(
    (select actor_id from deletion_fixture),
    (select request_id from deletion_fixture),
    (select receipt from deletion_fixture)
  )$$,
  'provider completion records closure without replaying the accepted historical deletion'
);
select is(
  (select app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))->>'state'),
  'completed',
  'a completed request has a recoverable receipt state'
);
select lives_ok(
  $$select public.challenge_complete_account_deletion_v1(
    (select actor_id from deletion_fixture),
    (select request_id from deletion_fixture),
    (select receipt from deletion_fixture)
  )$$,
  'completion exact retry never reruns historical effects'
);
select is(
  (select public.challenge_account_deletion_status_v1((select receipt from deletion_fixture))->>'state'),
  'completed',
  'the receipt reads status without restoring ordinary account access'
);

-- The stored receipt is the restricted post-Auth path for a still-open appeal;
-- this uses an ordinary fixture suspension, not a real person or provider.
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_suspensions_v1(actor_id, suspended, operator_id, reason, recorded_at)
values (
  (select actor_id from deletion_fixture), true, pg_temp.ba(3),
  'unsafe_behavior', clock_timestamp()
)
on conflict (actor_id) do update set suspended = excluded.suspended,
  recorded_at = excluded.recorded_at;
select lives_ok(
  $$select public.challenge_account_deletion_file_appeal_v1(
    (select receipt from deletion_fixture),
    'd1000000-0000-4000-8000-000000000003'::uuid
  )$$,
  'the restricted receipt can preserve an appeal after ordinary Auth is closed'
);
select ok(
  (select app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))
    ->'holds'->>'appeal')::boolean,
  'an unresolved appeal holds only the necessary retained case records'
);
select throws_ok(
  $$select public.challenge_cleanup_account_deletion_case_content_v1(
    (select actor_id from deletion_fixture)
  )$$,
  '55000', 'challenge_deletion_case_hold_active',
  'case cleanup does not silently cancel an appeal hold'
);

delete from app.challenge_appeal_decisions_v1;
insert into app.challenge_appeal_decisions_v1(appeal_id, operator_id, decision, recorded_at)
select appeal.id, pg_temp.ba(3), 'upheld', clock_timestamp() - interval '181 days'
from app.challenge_appeals_v1 appeal
where appeal.actor_id = (select actor_id from deletion_fixture);
with retention_time as (
  select clock_timestamp() - interval '181 days' as value
)
update app.challenge_account_deletions_v1 deletion
set accepted_at = retention_time.value,
    required_steps_finished_at = retention_time.value,
    provider_cleanup_completed_at = retention_time.value,
    account_closed_at = retention_time.value,
    identity_cleanup_after = retention_time.value + interval '7 days',
    identity_cleaned_at = retention_time.value
from retention_time
where deletion.actor_id = (select actor_id from deletion_fixture);
select lives_ok(
  $$select public.challenge_advance_account_deletion_v1(
    (select receipt from deletion_fixture)
  )$$,
  'receipt progress drives the due thirty-day case cleanup after results and cases close'
);
select ok(
  (select case_content_cleaned_at is not null
   from app.challenge_account_deletions_v1
   where actor_id = (select actor_id from deletion_fixture)),
  'the thirty-day action is recorded separately from account closure'
);
select lives_ok(
  $$select public.challenge_advance_account_deletion_v1(
    (select receipt from deletion_fixture)
  )$$,
  'the same receipt progress drives the due 180-day pseudonymous cleanup exactly once'
);
select ok(
  (select pseudonymous_retention_completed_at is not null
   from app.challenge_account_deletions_v1
   where actor_id = (select actor_id from deletion_fixture)),
  'the 180-day action retains its tombstone but records completion'
);
select ok(
  (select app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))
    ->>'state') = 'expired'
  and not (select (app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))
    ->'holds'->>'appeal')::boolean)
  and not (select (app.challenge_account_deletion_state_v1((select actor_id from deletion_fixture))
    ->'rights'->>'appeal_available')::boolean),
  '180-day cleanup keeps only the release marker and cannot recreate an appeal or a hold'
);
select is(
  (select public.challenge_account_deletion_status_v1((select receipt from deletion_fixture))->>'state'),
  'expired',
  'the 90-day receipt becomes terminal without reactivating or repeating deletion'
);

select * from finish();
rollback;
