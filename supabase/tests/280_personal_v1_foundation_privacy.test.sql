-- Personal V1 foundation: explicit model compatibility, self-only roster
-- privacy, frozen Stage A terms, and the one-open owner boundary.

begin;
select plan(44);

-- ---------------------------------------------------------------------------
-- Schema and privilege shape
-- ---------------------------------------------------------------------------

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid = 'public.challenge_model'::regtype
  ),
  '{legacy_charity_contest,personal_accountability,social_accountability}',
  'the immutable model discriminator preserves legacy and reserves social V2'
);

select has_column(
  'public', 'contests', 'challenge_model',
  'contests carry an explicit challenge model'
);

select col_not_null(
  'public', 'contests', 'challenge_model',
  'a contest can never fall back to an ambiguous model'
);

select ok(
  not exists (
    select 1
    from public.contests contest
    where contest.challenge_model <> 'legacy_charity_contest'
  ),
  'every pre-existing seeded contest was backfilled as legacy charity history'
);

select ok(
  (
    select contest.challenge_model = 'legacy_charity_contest'
       and contest.group_id = 'd4444444-4444-4444-4444-444444444444'
       and contest.created_by = 'a1111111-1111-1111-1111-111111111111'
       and contest.metric = 'steps'
       and contest.cadence = 'daily'
       and contest.target_value = 10000
       and contest.stake_amount_cents = 2500
       and contest.tie_break = 'integrity_score'
       and contest.max_participants = 4
    from public.contests contest
    where contest.id = 'f6666666-6666-6666-6666-666666666666'
  )
  and (
    select count(*) = 3
       and count(*) filter (where status = 'accepted') = 2
       and count(*) filter (where status = 'invited') = 1
       and count(*) filter (where charity_id is not null) = 2
    from public.contest_participants participant
    where participant.contest_id = 'f6666666-6666-6666-6666-666666666666'
  ),
  'the discriminator backfill preserves seeded legacy terms, roster states, and charity selections byte-for-value'
);

select ok(
  not exists (
    select 1
    from public.contest_results result
    join public.contests contest on contest.id = result.contest_id
    where contest.challenge_model <> 'legacy_charity_contest'
  ),
  'pre-existing social results remain attached only to legacy contests'
);

select has_table(
  'public', 'personal_challenge_terms',
  'frozen personal participant terms have a dedicated table'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid = 'public.personal_settlement_mode'::regtype
  ),
  '{test_only}',
  'Stage A has no database vocabulary for a live fee'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_def
    where index_def.schemaname = 'public'
      and index_def.indexname = 'contests_one_open_personal_per_owner_idx'
      and index_def.indexdef like '%WHERE ((challenge_model = %personal_accountability%'
  ),
  'one open personal slot is backed by a partial unique index'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'contest_participants'
      and policy.policyname = 'contest_participants_select_self'
      and policy.cmd = 'SELECT'
  ),
  'direct participant reads use the self-only policy'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'contest_participants'
      and policy.policyname = 'contest_participants_select_roster'
  ),
  'the former peer-roster SELECT policy is absent'
);

select has_function(
  'public', 'list_my_challenge_summaries_v1', array[]::text[],
  'legacy social history has a bounded summary RPC'
);

select has_function(
  'public', 'create_personal_challenge_v1',
  array['uuid', 'public.contest_cadence', 'integer', 'integer', 'text'],
  'personal creation has a dedicated versioned RPC'
);

select has_function(
  'public', 'get_my_accountability_challenge_v1', array['uuid'],
  'personal detail has a dedicated owner RPC'
);

select has_function(
  'public', 'cancel_personal_challenge_v1', array['uuid', 'uuid'],
  'personal cancellation has an idempotent versioned RPC'
);

select ok(
  (
    select strpos(definition, 'v_actor_id := app.require_active_caller();')
             < strpos(definition, 'v_now := clock_timestamp();')
    from (
      select pg_get_functiondef(
        'public.create_personal_challenge_v1(uuid,public.contest_cadence,integer,integer,text)'::regprocedure
      ) as definition
    ) source
  )
  and (
    select strpos(definition, 'for update;')
             < strpos(definition, 'v_now := clock_timestamp();')
    from (
      select pg_get_functiondef(
        'public.cancel_personal_challenge_v1(uuid,uuid)'::regprocedure
      ) as definition
    ) source
  ),
  'creation and cancellation sample authoritative time only after their serialization locks'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_personal_challenge_v1(uuid,public.contest_cadence,integer,integer,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.create_personal_challenge_v1(uuid,public.contest_cadence,integer,integer,text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_personal_challenge_v1(uuid,public.contest_cadence,integer,integer,text)',
    'execute'
  ),
  'only an authenticated owner can use the personal creation surface'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.record_personal_assessment_v1(uuid,uuid,public.personal_evidence_state,text,bytea,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.record_personal_assessment_v1(uuid,uuid,public.personal_evidence_state,text,bytea,text)',
    'execute'
  ),
  'assessment and publication remain service-only'
);

-- ---------------------------------------------------------------------------
-- Two-user legacy and personal fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('d8111111-1111-1111-1111-111111111111'),
  ('d8222222-2222-2222-2222-222222222222');

insert into public.profiles (id, handle, display_name, timezone) values
  ('d8111111-1111-1111-1111-111111111111', 'p1alice', 'P1 Alice', 'UTC'),
  ('d8222222-2222-2222-2222-222222222222', 'p1bob', 'P1 Bob', 'America/Chicago');

insert into public.friendships (user_a, user_b, requested_by, status) values (
  'd8111111-1111-1111-1111-111111111111',
  'd8222222-2222-2222-2222-222222222222',
  'd8111111-1111-1111-1111-111111111111',
  'accepted'
);

insert into public.charities (id, name, ein, slug) values (
  'd8c00001-0000-0000-0000-000000000001',
  'Personal Compatibility Fund',
  '38-0000001',
  'personal-compatibility-fund'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d8111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_legacy as
select public.create_contest(
  'Preserved social history',
  'steps',
  'cumulative',
  10000,
  1000,
  '2098-01-01T00:00:00Z',
  '2098-01-08T00:00:00Z',
  'UTC',
  'd8c00001-0000-0000-0000-000000000001',
  2::smallint
) as id;

insert into public.contest_participants (contest_id, user_id, invited_by)
values (
  (select id from t_legacy),
  'd8222222-2222-2222-2222-222222222222',
  'd8111111-1111-1111-1111-111111111111'
);

select is(
  (select challenge_model::text from public.contests where id = (select id from t_legacy)),
  'legacy_charity_contest',
  'the unchanged social creation path always creates legacy history'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d8222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (select count(*) from public.contest_participants where contest_id = (select id from t_legacy)),
  1::bigint,
  'an invitee can directly read only their own participant row'
);

select ok(
  (
    select accepted_count = 1 and invited_count = 1
    from public.list_my_challenge_summaries_v1()
    where contest_id = (select id from t_legacy)
  ),
  'the bounded legacy summary retains exact aggregate roster counts'
);

create temporary table t_personal as
select public.create_personal_challenge_v1(
  'd8000000-0000-0000-0000-000000000001',
  'daily',
  10000,
  1000,
  'America/Chicago'
) as id;

select is(
  (select challenge_model::text from public.contests where id = (select id from t_personal)),
  'personal_accountability',
  'personal creation stamps the model explicitly'
);

select ok(
  (
    select metric = 'steps'
       and tie_break = 'void'
       and max_participants = 1
       and group_id is null
    from public.contests
    where id = (select id from t_personal)
  ),
  'personal challenge mirror fields cannot carry social or unsupported terms'
);

select ok(
  (
    select count(*) = 1
       and bool_and(user_id = 'd8222222-2222-2222-2222-222222222222')
       and bool_and(status = 'accepted')
       and bool_and(charity_id is null)
    from public.contest_participants
    where contest_id = (select id from t_personal)
  ),
  'creation atomically installs one accepted owner and no charity'
);

select ok(
  (
    select cadence = 'daily'
       and target_steps = 10000
       and commitment_amount_minor = 1000
       and currency = 'USD'
       and settlement_mode = 'test_only'
       and terms_version = 'personal-v1'
       and timezone = 'America/Chicago'
    from public.personal_challenge_terms
    where challenge_id = (select id from t_personal)
  ),
  'the agreed personal terms are frozen with server-enforced test-only settlement'
);

select is(
  (
    select (starts_at at time zone 'America/Chicago')::time
    from public.contests where id = (select id from t_personal)
  ),
  '00:00:00'::time,
  'the challenge starts at local midnight in the frozen zone'
);

select is(
  (
    select (starts_at at time zone 'America/Chicago')::date
    from public.contests where id = (select id from t_personal)
  ),
  (clock_timestamp() at time zone 'America/Chicago')::date + 1,
  'creation selects the next local calendar day'
);

select is(
  (
    select (ends_at at time zone terms.timezone)::date
         - (starts_at at time zone terms.timezone)::date
    from public.contests contest
    join public.personal_challenge_terms terms on terms.challenge_id = contest.id
    where contest.id = (select id from t_personal)
  ),
  7,
  'the window spans seven complete local calendar days'
);

select is(
  (
    select terms.evidence_cutoff - contest.ends_at
    from public.personal_challenge_terms terms
    join public.contests contest on contest.id = terms.challenge_id
    where terms.challenge_id = (select id from t_personal)
  ),
  interval '24 hours',
  'the final trusted sync grace is exactly 24 hours'
);

select is(
  public.create_personal_challenge_v1(
    'd8000000-0000-0000-0000-000000000001',
    'daily', 10000, 1000, 'America/Chicago'
  ),
  (select id from t_personal),
  'an exact creation retry returns the original challenge'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'd8000000-0000-0000-0000-000000000001',
       'daily', 11000, 1000, 'America/Chicago'
     ) $$,
  '22023',
  null,
  'a reused request UUID cannot change frozen terms'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'd8000000-0000-0000-0000-000000000002',
       'cumulative', 70000, 2000, 'America/Chicago'
     ) $$,
  '23505',
  null,
  'a second open personal challenge collides at the database boundary'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'd8000000-0000-0000-0000-000000000003',
       'daily', 0, 1000, 'UTC'
     ) $$,
  '22023',
  null,
  'the creation RPC rejects a zero step target'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'd8000000-0000-0000-0000-000000000004',
       'daily', 1000001, 1000, 'UTC'
     ) $$,
  '22023',
  null,
  'the creation RPC rejects a target above one million steps'
);

select is(
  (
    select count(*)
    from public.list_my_challenge_summaries_v1()
    where contest_id = (select id from t_personal)
  ),
  0::bigint,
  'personal rows never leak through the legacy social summary'
);

select is(
  (select count(*) from public.list_my_accountability_challenges_v1()),
  1::bigint,
  'the personal list returns only the caller personal history'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d8111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.list_my_accountability_challenges_v1()),
  0::bigint,
  'another authenticated account cannot enumerate the owner personal challenge'
);

select is(
  (
    select count(*)
    from public.personal_challenge_terms
    where challenge_id = (select id from t_personal)
  ),
  0::bigint,
  'terms RLS hides another account terms'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d8222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (
    select count(*)
    from public.personal_challenge_terms
    where challenge_id = (select id from t_personal)
  ),
  1::bigint,
  'the owner can read their own frozen terms'
);

reset role;

select throws_ok(
  format(
    'insert into public.contest_participants (contest_id, user_id, status, timezone) values (%L, %L, %L, %L)',
    (select id from t_personal),
    'd8111111-1111-1111-1111-111111111111',
    'accepted',
    'UTC'
  ),
  '23001',
  null,
  'even a privileged path cannot add a peer to a personal challenge'
);

select throws_ok(
  format(
    'update public.contests set challenge_model = %L where id = %L',
    'legacy_charity_contest',
    (select id from t_personal)
  ),
  '23001',
  null,
  'a personal challenge can never be reinterpreted as legacy history'
);

select throws_ok(
  format(
    'insert into public.contest_standing_snapshots (contest_id, phase, reason, as_of, scoring_version, integrity_configuration_version, input_digest) values (%L, %L, %L, clock_timestamp(), %L, %L, extensions.digest(%L, %L))',
    (select id from t_personal),
    'provisional',
    'live',
    'personal-v1',
    'personal-v1',
    'forbidden-personal-standing',
    'sha256'
  ),
  '23001',
  null,
  'personal scoring cannot create a standings artifact'
);

select ok(
  has_table_privilege('authenticated', 'public.personal_challenge_terms', 'select')
  and not has_table_privilege('authenticated', 'public.personal_challenge_terms', 'insert')
  and not has_table_privilege('authenticated', 'public.personal_challenge_terms', 'update')
  and not has_table_privilege('authenticated', 'public.personal_challenge_terms', 'delete'),
  'personal terms are owner-readable and never client-writable'
);

-- Prove the table itself repeats the target cap instead of trusting the RPC.
insert into public.contests (
  id, title, created_by, challenge_model, metric, cadence, target_value,
  stake_amount_cents, tie_break, starts_at, ends_at, max_participants
) values (
  'd8000000-0000-0000-0000-000000000099',
  'Invalid personal terms fixture',
  'd8111111-1111-1111-1111-111111111111',
  'personal_accountability',
  'steps', 'daily', 1000001, 1000, 'void',
  '2098-04-01T00:00:00Z', '2098-04-08T00:00:00Z', 1
);

insert into public.contest_participants (
  contest_id, user_id, status, timezone, charity_id
) values (
  'd8000000-0000-0000-0000-000000000099',
  'd8111111-1111-1111-1111-111111111111',
  'accepted', 'UTC', null
);

select throws_ok(
  $$ insert into public.personal_challenge_terms (
       challenge_id, user_id, cadence, target_steps,
       commitment_amount_minor, timezone, evidence_cutoff
     ) values (
       'd8000000-0000-0000-0000-000000000099',
       'd8111111-1111-1111-1111-111111111111',
       'daily', 1000001, 1000, 'UTC', '2098-04-09T00:00:00Z'
     ) $$,
  '23514',
  null,
  'the authoritative terms table independently rejects targets above one million'
);

select * from finish();
rollback;
