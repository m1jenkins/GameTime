-- M8.1/M8.3a: bounded friendship reloads and one atomic, idempotent
-- multi-friend challenge request.

begin;
select plan(44);

-- ---------------------------------------------------------------------------
-- API and privilege shape
-- ---------------------------------------------------------------------------

select has_table(
  'app',
  'contest_creation_requests',
  'contest request idempotency is private app state'
);

select has_function(
  'public',
  'list_my_friendship_cards',
  array[]::text[],
  'the caller-bounded friendship card RPC exists'
);

select has_function(
  'public',
  'create_contest_with_invites_v1',
  array[
    'uuid',
    'text',
    'public.contest_metric',
    'public.contest_cadence',
    'numeric',
    'integer',
    'timestamp with time zone',
    'timestamp with time zone',
    'text',
    'uuid',
    'uuid[]',
    'smallint',
    'public.contest_tie_break',
    'uuid'
  ],
  'the versioned atomic contest RPC exists'
);

select ok(
  (
    select bool_and(routine.prosecdef)
    from pg_proc routine
    where routine.oid in (
      'public.list_my_friendship_cards()'::regprocedure,
      'public.create_contest_with_invites_v1(
        uuid,
        text,
        public.contest_metric,
        public.contest_cadence,
        numeric,
        integer,
        timestamptz,
        timestamptz,
        text,
        uuid,
        uuid[],
        smallint,
        public.contest_tie_break,
        uuid
      )'::regprocedure
    )
  ),
  'both M8.1 RPCs use bounded definer access'
);

select ok(
  (
    select bool_and(routine.provolatile = 'v')
    from pg_proc routine
    where routine.oid in (
      'public.list_my_friendship_cards()'::regprocedure,
      'public.create_contest_with_invites_v1(
        uuid,
        text,
        public.contest_metric,
        public.contest_cadence,
        numeric,
        integer,
        timestamptz,
        timestamptz,
        text,
        uuid,
        uuid[],
        smallint,
        public.contest_tie_break,
        uuid
      )'::regprocedure
    )
  ),
  'the active-actor lock makes both functions honestly volatile'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.list_my_friendship_cards()',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.create_contest_with_invites_v1(
      uuid,text,public.contest_metric,public.contest_cadence,numeric,integer,
      timestamptz,timestamptz,text,uuid,uuid[],smallint,
      public.contest_tie_break,uuid
    )',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.list_my_friendship_cards()',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.list_my_friendship_cards()',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.create_contest_with_invites_v1(
      uuid,text,public.contest_metric,public.contest_cadence,numeric,integer,
      timestamptz,timestamptz,text,uuid,uuid[],smallint,
      public.contest_tie_break,uuid
    )',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_contest_with_invites_v1(
      uuid,text,public.contest_metric,public.contest_cadence,numeric,integer,
      timestamptz,timestamptz,text,uuid,uuid[],smallint,
      public.contest_tie_break,uuid
    )',
    'execute'
  ),
  'only authenticated app callers may execute the M8.1 surfaces'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'app.contest_creation_requests',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'app.contest_creation_requests',
    'insert'
  )
  and not has_table_privilege(
    'service_role',
    'app.contest_creation_requests',
    'select'
  ),
  'the request ledger is invisible to every Data API role'
);

-- ---------------------------------------------------------------------------
-- Relationship-card fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('81111111-1111-1111-1111-111111111111'), -- alice
  ('a2222222-2222-2222-2222-222222222222'), -- bob
  ('a3333333-3333-3333-3333-333333333333'), -- carol
  ('a4444444-4444-4444-4444-444444444444'), -- dave
  ('a5555555-5555-5555-5555-555555555555'); -- erin

insert into public.profiles (id, handle, display_name, timezone) values
  ('81111111-1111-1111-1111-111111111111', 'm8alice', 'M8 Alice', 'America/Chicago'),
  ('a2222222-2222-2222-2222-222222222222', 'm8bob',   'M8 Bob',   'UTC'),
  ('a3333333-3333-3333-3333-333333333333', 'm8carol', 'M8 Carol', 'UTC'),
  ('a4444444-4444-4444-4444-444444444444', 'm8dave',  'M8 Dave',  'UTC'),
  ('a5555555-5555-5555-5555-555555555555', 'm8erin',  'M8 Erin',  'UTC');

insert into public.friendships (
  user_a,
  user_b,
  requested_by,
  status
) values
  (
    '81111111-1111-1111-1111-111111111111',
    'a2222222-2222-2222-2222-222222222222',
    '81111111-1111-1111-1111-111111111111',
    'pending'
  ),
  (
    '81111111-1111-1111-1111-111111111111',
    'a3333333-3333-3333-3333-333333333333',
    'a3333333-3333-3333-3333-333333333333',
    'pending'
  ),
  (
    '81111111-1111-1111-1111-111111111111',
    'a4444444-4444-4444-4444-444444444444',
    'a4444444-4444-4444-4444-444444444444',
    'accepted'
  ),
  (
    '81111111-1111-1111-1111-111111111111',
    'a5555555-5555-5555-5555-555555555555',
    'a5555555-5555-5555-5555-555555555555',
    'accepted'
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.list_my_friendship_cards()),
  4::bigint,
  'the caller reloads all of their pending and accepted relationships'
);

select is(
  (
    select requested_by
    from public.list_my_friendship_cards()
    where other_user_id = 'a3333333-3333-3333-3333-333333333333'
      and status = 'pending'
  ),
  'a3333333-3333-3333-3333-333333333333'::uuid,
  'an incoming request retains its requester direction'
);

select is(
  (
    select requested_by
    from public.list_my_friendship_cards()
    where other_user_id = 'a2222222-2222-2222-2222-222222222222'
      and status = 'pending'
  ),
  '81111111-1111-1111-1111-111111111111'::uuid,
  'an outgoing request retains its requester direction'
);

select is(
  (
    select handle::text
    from public.list_my_friendship_cards()
    where other_user_id = 'a4444444-4444-4444-4444-444444444444'
      and status = 'accepted'
  ),
  'm8dave',
  'an accepted relationship includes only the other profile card'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a2222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (select count(*) from public.list_my_friendship_cards()),
  1::bigint,
  'another caller receives only relationships they are party to'
);

select is(
  (
    select count(*)
    from public.list_my_friendship_cards()
    where other_user_id = 'a4444444-4444-4444-4444-444444444444'
  ),
  0::bigint,
  'caller isolation does not leak somebody else''s accepted friend'
);

reset role;
insert into public.blocks (blocker_id, blocked_id) values (
  'a3333333-3333-3333-3333-333333333333',
  '81111111-1111-1111-1111-111111111111'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.list_my_friendship_cards()),
  3::bigint,
  'blocking immediately removes the relationship card'
);

select is(
  (
    select count(*)
    from public.list_my_friendship_cards()
    where other_user_id = 'a3333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'the card RPC does not reveal the blocker or blocked profile'
);

reset role;
set local role service_role;
select public.delete_account(
  'a5555555-5555-5555-5555-555555555555'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.list_my_friendship_cards()),
  2::bigint,
  'account deletion removes the tombstoned relationship from reloads'
);

select is(
  (
    select count(*)
    from public.list_my_friendship_cards()
    where other_user_id = 'a5555555-5555-5555-5555-555555555555'
  ),
  0::bigint,
  'a retained tombstone is never returned as a profile card'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a5555555-5555-5555-5555-555555555555"}',
  true
);

select throws_ok(
  $$ select * from public.list_my_friendship_cards() $$,
  '42501',
  null,
  'a tombstoned stale JWT cannot reload friendship cards'
);

select throws_ok(
  $$ select public.create_contest_with_invites_v1(
       'a5000000-0000-0000-0000-000000000001',
       'Stale actor challenge',
       'steps',
       'cumulative',
       10000,
       500,
       '2098-01-01T00:00:00Z',
       '2098-01-03T00:00:00Z',
       'UTC',
       'c0000001-0000-0000-0000-000000000001',
       array['81111111-1111-1111-1111-111111111111'::uuid]
     ) $$,
  '42501',
  null,
  'a tombstoned stale JWT cannot create a contest'
);

-- ---------------------------------------------------------------------------
-- Atomic create, retry, and changed-payload behavior
-- ---------------------------------------------------------------------------

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);
insert into public.charities (id, name, ein, slug) values (
  'ac000001-0000-0000-0000-000000000001',
  'M8 Test Charity',
  '11-1111111',
  'm8-test-charity'
);
insert into auth.users (id) values
  ('a6666666-6666-6666-6666-666666666666');
insert into public.profiles (id, handle, display_name, timezone) values
  ('a6666666-6666-6666-6666-666666666666', 'm8frank', 'M8 Frank', 'UTC');
insert into public.friendships (
  user_a,
  user_b,
  requested_by,
  status
) values (
  '81111111-1111-1111-1111-111111111111',
  'a6666666-6666-6666-6666-666666666666',
  '81111111-1111-1111-1111-111111111111',
  'accepted'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_m8_contest as
select public.create_contest_with_invites_v1(
  'a1000000-0000-0000-0000-000000000001',
  'M8 challenge',
  'steps',
  'cumulative',
  10000,
  500,
  '2098-01-01T00:00:00Z',
  '2098-01-03T00:00:00Z',
  'America/Chicago',
  'ac000001-0000-0000-0000-000000000001',
  array[
    'a6666666-6666-6666-6666-666666666666'::uuid,
    'a4444444-4444-4444-4444-444444444444'::uuid
  ],
  3::smallint,
  'integrity_score',
  null
) as id;

select isnt(
  (select id from t_m8_contest),
  null,
  'a valid request returns a contest UUID'
);

reset role;
select is(
  (
    select count(*)
    from public.contests
    where id = (select id from t_m8_contest)
  ),
  1::bigint,
  'the atomic request creates one contest'
);

select is(
  (
    select count(*)
    from public.contest_participants
    where contest_id = (select id from t_m8_contest)
  ),
  3::bigint,
  'the contest and complete multi-friend challenge roster commit together'
);

select ok(
  exists (
    select 1
    from public.contest_participants
    where contest_id = (select id from t_m8_contest)
      and user_id = '81111111-1111-1111-1111-111111111111'
      and status = 'accepted'
      and timezone = 'America/Chicago'
      and charity_id = 'ac000001-0000-0000-0000-000000000001'
  ),
  'the author is accepted with their frozen timezone and charity'
);

select is(
  (
    select count(*)
    from public.contest_participants
    where contest_id = (select id from t_m8_contest)
      and user_id in (
        'a4444444-4444-4444-4444-444444444444',
        'a6666666-6666-6666-6666-666666666666'
      )
      and status = 'invited'
      and invited_by = '81111111-1111-1111-1111-111111111111'
  ),
  2::bigint,
  'every selected friend is invited on the same contest'
);

select is(
  (
    select count(*)
    from app.contest_creation_requests
    where actor_id = '81111111-1111-1111-1111-111111111111'
      and request_id = 'a1000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the private request ledger commits with the contest'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.create_contest_with_invites_v1(
    'a1000000-0000-0000-0000-000000000001',
    'M8 challenge',
    'steps',
    'cumulative',
    10000.00,
    500,
    '2098-01-01T00:00:00+00:00',
    '2098-01-03T00:00:00+00:00',
    'America/Chicago',
    'ac000001-0000-0000-0000-000000000001',
    array[
      'a4444444-4444-4444-4444-444444444444'::uuid,
      'a6666666-6666-6666-6666-666666666666'::uuid
    ],
    3::smallint,
    'integrity_score',
    null
  ),
  (select id from t_m8_contest),
  'an equivalent retry returns the original contest UUID'
);

reset role;
select is(
  (
    select count(*)
    from public.contests
    where title = 'M8 challenge'
      and created_by = '81111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'an identical retry does not duplicate the contest'
);

select is(
  (
    select count(*)
    from public.contest_participants
    where contest_id = (select id from t_m8_contest)
  ),
  3::bigint,
  'an identical retry does not duplicate participants'
);

select is(
  (
    select count(*)
    from app.contest_creation_requests
    where actor_id = '81111111-1111-1111-1111-111111111111'
      and request_id = 'a1000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'an identical retry does not duplicate its ledger row'
);

reset role;
set local role service_role;
select public.delete_account(
  'a4444444-4444-4444-4444-444444444444'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.create_contest_with_invites_v1(
    'a1000000-0000-0000-0000-000000000001',
    'M8 challenge',
    'steps',
    'cumulative',
    10000,
    500,
    '2098-01-01T00:00:00Z',
    '2098-01-03T00:00:00Z',
    'America/Chicago',
    'ac000001-0000-0000-0000-000000000001',
    array[
      'a4444444-4444-4444-4444-444444444444'::uuid,
      'a6666666-6666-6666-6666-666666666666'::uuid
    ],
    3::smallint,
    'integrity_score',
    null
  ),
  (select id from t_m8_contest),
  'an identical retry still returns the original after the invitee is tombstoned'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_contest_with_invites_v1(
       'a1000000-0000-0000-0000-000000000001',
       'Changed title',
       'steps',
       'cumulative',
       10000,
       500,
       '2098-01-01T00:00:00Z',
       '2098-01-03T00:00:00Z',
       'America/Chicago',
       'ac000001-0000-0000-0000-000000000001',
       array[
         'a4444444-4444-4444-4444-444444444444'::uuid,
         'a6666666-6666-6666-6666-666666666666'::uuid
       ],
       3::smallint,
       'integrity_score',
       null
     ) $$,
  '22023',
  null,
  'the same request UUID cannot name changed terms'
);

reset role;
select ok(
  (
    select count(*)
    from public.contests
    where created_by = '81111111-1111-1111-1111-111111111111'
  ) = 1
  and (
    select count(*)
    from app.contest_creation_requests
    where actor_id = '81111111-1111-1111-1111-111111111111'
  ) = 1,
  'changed-payload rejection leaves both contest and ledger unchanged'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_contest_with_invites_v1(
       'a1000000-0000-0000-0000-000000000002',
       'Atomic failure',
       'steps',
       'cumulative',
       10000,
       500,
       '2098-02-01T00:00:00Z',
       '2098-02-03T00:00:00Z',
       'America/Chicago',
       'ac000001-0000-0000-0000-000000000001',
       array['a2222222-2222-2222-2222-222222222222'::uuid],
       2::smallint,
       'integrity_score',
       null
     ) $$,
  '42501',
  null,
  'an ineligible invitee rejects the whole creation request'
);

reset role;
select is(
  (
    select count(*)
    from public.contests
    where title = 'Atomic failure'
  ),
  0::bigint,
  'a failed invitation leaves no orphan contest'
);

select is(
  (
    select count(*)
    from app.contest_creation_requests
    where request_id = 'a1000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'a failed invitation leaves no idempotency record'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_contest_with_invites_v1(
       'a1000000-0000-0000-0000-000000000003',
       'Duplicate invitees',
       'steps',
       'cumulative',
       10000,
       500,
       '2098-03-01T00:00:00Z',
       '2098-03-03T00:00:00Z',
       'America/Chicago',
       'ac000001-0000-0000-0000-000000000001',
       array[
         'a4444444-4444-4444-4444-444444444444'::uuid,
         'a4444444-4444-4444-4444-444444444444'::uuid
       ],
       3::smallint,
       'integrity_score',
       null
     ) $$,
  '22023',
  null,
  'duplicate invitee IDs are rejected before mutation'
);

select throws_ok(
  $$ select public.create_contest_with_invites_v1(
       'a1000000-0000-0000-0000-000000000004',
       'Self invite',
       'steps',
       'cumulative',
       10000,
       500,
       '2098-04-01T00:00:00Z',
       '2098-04-03T00:00:00Z',
       'America/Chicago',
       'ac000001-0000-0000-0000-000000000001',
       array['81111111-1111-1111-1111-111111111111'::uuid],
       2::smallint,
       'integrity_score',
       null
     ) $$,
  '22023',
  null,
  'the author cannot appear in the invitation array'
);

-- ---------------------------------------------------------------------------
-- Deterministic concurrent duplicate proof
-- ---------------------------------------------------------------------------
-- dblink is test-only. A held caller-row update queues two authenticated calls
-- on the same active-profile lock, then releases them together. Both must
-- return the one committed contest.

reset role;
select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the test-only concurrency driver'
);

select extensions.dblink_connect(
  'm8_setup',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'm8_setup',
  $setup$
    insert into auth.users (id) values
      ('91111111-1111-1111-1111-111111111111'),
      ('92222222-2222-2222-2222-222222222222');
    insert into public.profiles (id, handle, display_name) values
      ('91111111-1111-1111-1111-111111111111', 'm8raceone', 'M8 Race One'),
      ('92222222-2222-2222-2222-222222222222', 'm8racetwo', 'M8 Race Two');
    insert into public.friendships (
      user_a, user_b, requested_by, status
    ) values (
      '91111111-1111-1111-1111-111111111111',
      '92222222-2222-2222-2222-222222222222',
      '91111111-1111-1111-1111-111111111111',
      'accepted'
    );
    insert into public.charities (id, name, ein, slug) values (
      'bc000001-0000-0000-0000-000000000001',
      'M8 Race Charity',
      '22-2222222',
      'm8-race-charity'
    );
  $setup$
);

select extensions.dblink_connect(
  'm8_gate',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'm8_call_one',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'm8_call_two',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec('m8_gate', 'begin');
select extensions.dblink_exec(
  'm8_gate',
  $gate$
    update public.profiles
    set display_name = display_name
    where id = '91111111-1111-1111-1111-111111111111'
  $gate$
);

select extensions.dblink_exec('m8_call_one', 'set role authenticated');
select extensions.dblink_exec(
  'm8_call_one',
  $claim$set "request.jwt.claims" =
    '{"sub":"91111111-1111-1111-1111-111111111111"}'$claim$
);
select extensions.dblink_exec('m8_call_two', 'set role authenticated');
select extensions.dblink_exec(
  'm8_call_two',
  $claim$set "request.jwt.claims" =
    '{"sub":"91111111-1111-1111-1111-111111111111"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'm8_call_one',
    $request$
      select public.create_contest_with_invites_v1(
        'b1000000-0000-0000-0000-000000000001',
        'Concurrent challenge',
        'distance_meters',
        'cumulative',
        5000,
        700,
        '2099-01-01T00:00:00Z',
        '2099-01-03T00:00:00Z',
        'UTC',
        'bc000001-0000-0000-0000-000000000001',
        array['92222222-2222-2222-2222-222222222222'::uuid],
        2::smallint,
        'integrity_score',
        null
      )
    $request$
  ) = 1,
  'the first duplicate request is queued behind the concurrency gate'
);

select ok(
  extensions.dblink_send_query(
    'm8_call_two',
    $request$
      select public.create_contest_with_invites_v1(
        'b1000000-0000-0000-0000-000000000001',
        'Concurrent challenge',
        'distance_meters',
        'cumulative',
        5000.00,
        700,
        '2099-01-01T00:00:00+00:00',
        '2099-01-03T00:00:00+00:00',
        'UTC',
        'bc000001-0000-0000-0000-000000000001',
        array['92222222-2222-2222-2222-222222222222'::uuid],
        2::smallint,
        'integrity_score',
        null
      )
    $request$
  ) = 1,
  'the second duplicate request is queued independently'
);

select extensions.dblink_exec('m8_gate', 'commit');

create temporary table t_m8_concurrent_one as
select result.id
from extensions.dblink_get_result('m8_call_one') as result(id uuid);

create temporary table t_m8_concurrent_two as
select result.id
from extensions.dblink_get_result('m8_call_two') as result(id uuid);

select is(
  (select id from t_m8_concurrent_one),
  (select id from t_m8_concurrent_two),
  'concurrent identical submissions return the same contest UUID'
);

select is(
  (
    select count(*)
    from public.contests
    where title = 'Concurrent challenge'
      and created_by = '91111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'concurrent duplicate submissions commit one contest'
);

select is(
  (
    select count(*)
    from public.contest_participants
    where contest_id = (select id from t_m8_concurrent_one)
  ),
  2::bigint,
  'the concurrently created contest has one complete challenge roster'
);

select is(
  (
    select count(*)
    from app.contest_creation_requests
    where actor_id = '91111111-1111-1111-1111-111111111111'
      and request_id = 'b1000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'concurrent duplicate submissions commit one request ledger row'
);

select extensions.dblink_disconnect('m8_call_one');
select extensions.dblink_disconnect('m8_call_two');
select extensions.dblink_disconnect('m8_gate');

select extensions.dblink_exec(
  'm8_setup',
  $cleanup$
    set session_replication_role = replica;
    delete from app.contest_creation_requests
      where actor_id in (
        '91111111-1111-1111-1111-111111111111',
        '92222222-2222-2222-2222-222222222222'
      );
    delete from public.contest_participants
      where user_id in (
        '91111111-1111-1111-1111-111111111111',
        '92222222-2222-2222-2222-222222222222'
      );
    delete from public.contests
      where created_by = '91111111-1111-1111-1111-111111111111';
    delete from public.friendships
      where user_a = '91111111-1111-1111-1111-111111111111';
    delete from app.active_profile_auth_bindings
      where actor_id in (
        '91111111-1111-1111-1111-111111111111',
        '92222222-2222-2222-2222-222222222222'
      );
    delete from public.profiles
      where id in (
        '91111111-1111-1111-1111-111111111111',
        '92222222-2222-2222-2222-222222222222'
      );
    delete from auth.users
      where id in (
        '91111111-1111-1111-1111-111111111111',
        '92222222-2222-2222-2222-222222222222'
      );
    delete from public.charities
      where id = 'bc000001-0000-0000-0000-000000000001';
    set session_replication_role = origin;
  $cleanup$
);

select extensions.dblink_disconnect('m8_setup');

select * from finish();
rollback;
