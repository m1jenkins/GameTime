-- Local-only P8 privacy and deletion coverage. Real-source envelopes below
-- are fictional normalized values; no raw Health record, source tuple, route,
-- or attestation assertion is placed in this test. The transaction rolls back.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- An accepted agreement gives the real admission its only durable binding.
-- The direct inserts are service fixtures for retention, after the ordinary
-- consent flow has supplied the immutable agreement and consent rows.
select pg_temp.login_beta(1);
insert into beta_ids values ('real_privacy', pg_temp.beta_group(1, 2));
reset role;
select set_config('app.challenge_write_v1', 'on', true);
update app.challenge_lobbies_v1
set real_source_policy_version = 'apple_watch_steps_v1'
where id = (select id from beta_ids where name = 'real_privacy');

create temp table real_privacy_fixture as
select
  pg_temp.ba(1) as actor_id,
  pg_temp.br(1) as session_id,
  (select id from beta_ids where name = 'real_privacy') as challenge_id,
  'd5210000-0000-4000-8000-000000000001'::uuid as request_id,
  'local_real_privacy_deletion_receipt_012345678901234567890123456789'::text as receipt,
  'fictional-real-privacy-apple-subject'::text as apple_subject;

create temp table real_agreement_before as
select agreement.challenge_id, agreement.digest, agreement.terms
from app.challenge_agreements_v1 agreement
where agreement.challenge_id = (select challenge_id from real_privacy_fixture)
  and agreement.version = 1;

insert into app.challenge_real_health_readiness_v1(
  actor_id, source_policy_version, observed_at, recorded_at
)
select actor_id, 'apple_watch_steps_v1', clock_timestamp() - interval '1 minute', clock_timestamp()
from real_privacy_fixture;

insert into app.challenge_real_health_readiness_requests_v1(
  request_id, actor_id, source_policy_version, observed_at, payload_digest,
  device_key_id, assertion_counter, response, recorded_at
)
select
  'd5210000-0000-4000-8000-000000000002'::uuid, actor_id,
  'apple_watch_steps_v1', clock_timestamp() - interval '1 minute',
  extensions.digest('fictional readiness envelope', 'sha256'),
  extensions.digest('fictional readiness device', 'sha256'), 1,
  '{"version":"challenge_real_health_readiness_receipt_v1"}'::jsonb, clock_timestamp()
from real_privacy_fixture;

insert into app.challenge_real_health_admissions_v1(
  challenge_id, actor_id, agreement_version, terms_digest, source_policy_version,
  metric, window_starts_at, window_ends_at, admitted_at
)
select fixture.challenge_id, fixture.actor_id, 1, agreement.digest,
  'apple_watch_steps_v1', 'steps', lobby.starts_at, lobby.ends_at, clock_timestamp()
from real_privacy_fixture fixture
join app.challenge_lobbies_v1 lobby on lobby.id = fixture.challenge_id
join app.challenge_agreements_v1 agreement
  on agreement.challenge_id = fixture.challenge_id and agreement.version = 1;

insert into app.challenge_real_health_facts_v1(
  challenge_id, actor_id, agreement_version, revision, previous_revision,
  state, value, observed_at, queried_through_at, recorded_at, request_id
)
select challenge_id, actor_id, 1, 1, null, 'value', 42,
  clock_timestamp() - interval '1 minute', clock_timestamp() - interval '2 minutes',
  clock_timestamp(), 'd5210000-0000-4000-8000-000000000003'::uuid
from real_privacy_fixture;

insert into app.challenge_real_health_requests_v1(
  request_id, actor_id, payload, payload_digest, device_key_id,
  assertion_counter, response, recorded_at
)
select
  'd5210000-0000-4000-8000-000000000003'::uuid, actor_id,
  jsonb_build_object('contract_version', 1, 'value', 42, 'request_kind', 'fictional_real_activity'),
  extensions.digest('fictional real activity envelope', 'sha256'),
  extensions.digest('fictional real activity device', 'sha256'), 2,
  '{"version":"challenge_real_health_receipt_v1"}'::jsonb, clock_timestamp()
from real_privacy_fixture;

-- Finality is the retention anchor. This is the same past immutable-final
-- fixture used by the established deletion test; production deletion never
-- writes or replaces an immutable final.
insert into app.challenge_finals_v1(challenge_id, result, recorded_at, revision)
select challenge_id, '{"kind":"void","reason":"fictional_real_privacy"}'::jsonb,
  clock_timestamp() - interval '181 days', 1
from real_privacy_fixture;

-- The existing actor projection is the only readable path. It returns the
-- normalized progress shape, never readiness, admission, or request payload.
select is(
  app.challenge_detail_for_actor_v1(
    (select challenge_id from real_privacy_fixture),
    (select actor_id from real_privacy_fixture)
  ) -> 'members' -> 0 -> 'fact' ->> 'value',
  '42',
  'the existing actor projection exposes the normalized real fact only through membership privacy'
);
select ok(
  not (app.challenge_detail_for_actor_v1(
    (select challenge_id from real_privacy_fixture),
    (select actor_id from real_privacy_fixture)
  )::text like '%fictional_real_activity%'),
  'the actor projection excludes the private real activity request payload'
);
select ok(
  not has_table_privilege('authenticated', 'app.challenge_real_health_requests_v1', 'select')
  and not has_table_privilege('authenticated', 'app.challenge_real_health_readiness_v1', 'select')
  and not has_table_privilege('service_role', 'app.challenge_real_health_admissions_v1', 'select'),
  'real request, readiness, and admission tables remain private under RLS'
);

-- The real-source admission branch observes the same suspension fence as the
-- historic paths. Existing section reads stay permitted for a suspended actor.
select public.challenge_real_health_runtime_v1(true, true, true);
insert into app.challenge_suspensions_v1(actor_id, suspended, operator_id, reason, recorded_at)
values (pg_temp.ba(3), true, pg_temp.ba(4), 'unsafe_behavior', clock_timestamp());
select set_config('app.challenge_real_health_command_v1', 'on', true);
select throws_ok(
  $$select app.challenge_admit_v1(pg_temp.ba(3))$$,
  '42501', 'challenge_admission_paused',
  'a suspended actor cannot enter through the real-source admission branch'
);
select pg_temp.login_beta(3);
select lives_ok(
  $$select public.challenge_section_v1('history')$$,
  'a suspended actor retains the established own history read'
);
reset role;

-- Acceptance immediately removes pre-consent readiness and its replay receipt,
-- while a consent-bound admission plus immutable agreement remain available to
-- the existing 30/180-day state machine.
select lives_ok(
  $$select public.challenge_begin_account_deletion_v1(
    (select actor_id from real_privacy_fixture),
    (select request_id from real_privacy_fixture),
    (select receipt from real_privacy_fixture),
    (select apple_subject from real_privacy_fixture)
  )$$,
  'accepted deletion runs real-source identity cleanup through the established receipt flow'
);
select is(
  (select count(*) from app.challenge_real_health_readiness_v1
   where actor_id = (select actor_id from real_privacy_fixture)),
  0::bigint,
  'identity cleanup removes the pre-consent real readiness record'
);
select is(
  (select count(*) from app.challenge_real_health_readiness_requests_v1
   where actor_id = (select actor_id from real_privacy_fixture)),
  0::bigint,
  'identity cleanup removes the pre-consent readiness replay payload'
);
select ok(
  exists (select 1 from app.challenge_real_health_admissions_v1
          where actor_id = (select actor_id from real_privacy_fixture))
  and exists (select 1 from app.challenge_real_health_facts_v1
              where actor_id = (select actor_id from real_privacy_fixture))
  and exists (select 1 from app.challenge_real_health_requests_v1
              where actor_id = (select actor_id from real_privacy_fixture)),
  'acceptance retains agreement-scoped admission and detailed activity until their established stages'
);
select is(
  (select row(digest, terms)::text from app.challenge_agreements_v1
   where challenge_id = (select challenge_id from real_privacy_fixture) and version = 1),
  (select row(digest, terms)::text from real_agreement_before),
  'real-source deletion preserves the historical agreement digest and terms'
);
select ok(
  app.challenge_actor_unavailable_v1((select actor_id from real_privacy_fixture)),
  'accepted deletion preserves the existing unavailable-actor privacy fence'
);

-- Complete the ordinary provider/account stages, then make only the existing
-- local clock due. This does not change any frozen agreement window or terms.
select public.challenge_account_deletion_provider_complete_v1(
  (select actor_id from real_privacy_fixture),
  (select request_id from real_privacy_fixture),
  (select receipt from real_privacy_fixture),
  (select apple_subject from real_privacy_fixture)
);
select public.challenge_complete_account_deletion_v1(
  (select actor_id from real_privacy_fixture),
  (select request_id from real_privacy_fixture),
  (select receipt from real_privacy_fixture)
);
with elapsed as (select clock_timestamp() - interval '181 days' as value)
update app.challenge_account_deletions_v1 deletion
set accepted_at = elapsed.value,
    required_steps_finished_at = elapsed.value,
    provider_cleanup_completed_at = elapsed.value,
    account_closed_at = elapsed.value,
    identity_cleanup_after = elapsed.value + interval '7 days',
    identity_cleaned_at = elapsed.value
from elapsed
where deletion.actor_id = (select actor_id from real_privacy_fixture);

select lives_ok(
  $$select public.challenge_advance_account_deletion_v1(
    (select receipt from real_privacy_fixture)
  )$$,
  'the first due advance performs the 30-day real detailed-data cleanup'
);
select is(
  (select count(*) from app.challenge_real_health_facts_v1
   where actor_id = (select actor_id from real_privacy_fixture)),
  0::bigint,
  '30-day cleanup removes normalized real facts'
);
select is(
  (select count(*) from app.challenge_real_health_requests_v1
   where actor_id = (select actor_id from real_privacy_fixture)),
  0::bigint,
  '30-day cleanup removes value-bearing real activity request payloads with their facts'
);
select ok(
  exists (select 1 from app.challenge_real_health_admissions_v1
          where actor_id = (select actor_id from real_privacy_fixture)),
  '30-day cleanup keeps the minimal agreement-bound admission for the existing consent window'
);

select lives_ok(
  $$select public.challenge_advance_account_deletion_v1(
    (select receipt from real_privacy_fixture)
  )$$,
  'the second due advance performs the established 180-day agreement cleanup'
);
select is(
  (select count(*) from app.challenge_real_health_admissions_v1
   where actor_id = (select actor_id from real_privacy_fixture)),
  0::bigint,
  'consent expiry cascades the agreement-bound real admission at 180 days'
);
select is(
  (select row(digest, terms)::text from app.challenge_agreements_v1
   where challenge_id = (select challenge_id from real_privacy_fixture) and version = 1),
  (select row(digest, terms)::text from real_agreement_before),
  '180-day actor cleanup does not rewrite the historical real-source agreement'
);

create temp table real_restore_evidence as
select public.challenge_account_deletion_restore_evidence_v1(actor_id) as evidence
from real_privacy_fixture;
select lives_ok(
  $$select public.challenge_replay_account_deletion_restore_v1(
    (select evidence from real_restore_evidence)
  )$$,
  'restore replay reuses the established deletion stages without restoring real activity data'
);
select ok(
  not exists (select 1 from app.challenge_real_health_readiness_v1
              where actor_id = (select actor_id from real_privacy_fixture))
  and not exists (select 1 from app.challenge_real_health_readiness_requests_v1
                  where actor_id = (select actor_id from real_privacy_fixture))
  and not exists (select 1 from app.challenge_real_health_facts_v1
                  where actor_id = (select actor_id from real_privacy_fixture))
  and not exists (select 1 from app.challenge_real_health_requests_v1
                  where actor_id = (select actor_id from real_privacy_fixture))
  and not exists (select 1 from app.challenge_real_health_admissions_v1
                  where actor_id = (select actor_id from real_privacy_fixture)),
  'restore replay cannot resurrect purged real-source data'
);

select * from finish();
rollback;
