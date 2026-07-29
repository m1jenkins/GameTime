-- M7 / M8.3c: trusted scoring snapshots become a phase-redacted participant
-- read surface, and a frozen winner creates exactly one obligation per loser.

begin;
select plan(45);

-- ---------------------------------------------------------------------------
-- API, privilege, and storage shape
-- ---------------------------------------------------------------------------

select has_function(
  'public',
  'publish_contest_standings_v1',
  array['uuid', 'timestamp with time zone', 'text', 'text', 'jsonb', 'jsonb',
        'timestamp with time zone'],
  'trusted scoring has one versioned publish/finalize boundary'
);

select has_function(
  'public',
  'get_contest_standings_v1',
  array['uuid'],
  'accepted participants have one canonical standings read surface'
);

select ok(
  (select bool_and(routine.prosecdef)
   from pg_proc routine
   where routine.oid in (
     'public.publish_contest_standings_v1(uuid,timestamptz,text,text,jsonb,jsonb,timestamptz)'::regprocedure,
     'public.get_contest_standings_v1(uuid)'::regprocedure
   )),
  'both boundaries intentionally read through private base tables'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.publish_contest_standings_v1(uuid,timestamptz,text,text,jsonb,jsonb,timestamptz)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.publish_contest_standings_v1(uuid,timestamptz,text,text,jsonb,jsonb,timestamptz)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_contest_standings_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_contest_standings_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_contest_standings_v1(uuid)',
    'execute'
  ),
  'trusted writes and authenticated reads are disjoint least-privilege paths'
);

select ok(
  not has_table_privilege('authenticated', 'public.contest_results', 'select')
  and not has_table_privilege(
    'authenticated',
    'public.contest_standing_snapshots',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.contest_standing_entries',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.donation_obligations',
    'select'
  ),
  'clients cannot bypass phase redaction through base tables'
);

select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.contest_results'::regclass,
     'public.contest_standing_snapshots'::regclass,
     'public.contest_standing_entries'::regclass,
     'public.donation_obligations'::regclass
   )),
  'every new public table has RLS enabled as defense in depth'
);

-- ---------------------------------------------------------------------------
-- Five contests: live, winner, all-donate, pre-grace, and integrity winner
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('91111111-1111-1111-1111-111111111111'),
  ('92222222-2222-2222-2222-222222222222'),
  ('93333333-3333-3333-3333-333333333333'),
  ('94444444-4444-4444-4444-444444444444'),
  ('95555555-5555-5555-5555-555555555555');

insert into public.profiles (id, handle, display_name) values
  ('91111111-1111-1111-1111-111111111111', 'm83calice', 'Alice'),
  ('92222222-2222-2222-2222-222222222222', 'm83cbob', 'Bob'),
  ('93333333-3333-3333-3333-333333333333', 'm83ccarol', 'Carol'),
  ('94444444-4444-4444-4444-444444444444', 'm83coutside', 'Outside'),
  ('95555555-5555-5555-5555-555555555555', 'm83cinvited', 'Invited');

insert into public.charities (id, name, ein, slug) values
  (
    '9c000001-0000-0000-0000-000000000001',
    'Alice Trail Fund',
    '91-0000001',
    'alice-trail-fund'
  ),
  (
    '9c000002-0000-0000-0000-000000000002',
    'Bob Food Fund',
    '91-0000002',
    'bob-food-fund'
  ),
  (
    '9c000003-0000-0000-0000-000000000003',
    'Carol Arts Fund',
    '91-0000003',
    'carol-arts-fund'
  );

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id,
  title,
  created_by,
  metric,
  cadence,
  target_value,
  stake_amount_cents,
  tie_break,
  starts_at,
  ends_at,
  max_participants
) values
  (
    '9a000001-0000-0000-0000-000000000001',
    'M8.3c live',
    '91111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    500,
    'earliest_to_target',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) + interval '2 days',
    4
  ),
  (
    '9a000002-0000-0000-0000-000000000002',
    'M8.3c winner',
    '91111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    500,
    'earliest_to_target',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '7 hours',
    3
  ),
  (
    '9a000003-0000-0000-0000-000000000003',
    'M8.3c all donate',
    '91111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    700,
    'both_donate',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '7 hours',
    3
  ),
  (
    '9a000004-0000-0000-0000-000000000004',
    'M8.3c grace gate',
    '91111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    500,
    'earliest_to_target',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '1 hour',
    3
  ),
  (
    '9a000005-0000-0000-0000-000000000005',
    'M8.3c integrity winner',
    '91111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    500,
    'integrity_score',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '7 hours',
    3
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by,
  timezone,
  charity_id
)
select
  contest.id,
  '91111111-1111-1111-1111-111111111111'::uuid,
  'accepted',
  null,
  'UTC',
  '9c000001-0000-0000-0000-000000000001'::uuid
from public.contests contest
where contest.id between
  '9a000001-0000-0000-0000-000000000001'::uuid
  and '9a000005-0000-0000-0000-000000000005'::uuid;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by
)
select
  contest.id,
  participant.user_id,
  'invited',
  '91111111-1111-1111-1111-111111111111'::uuid
from public.contests contest
cross join (
  values
    ('92222222-2222-2222-2222-222222222222'::uuid),
    ('93333333-3333-3333-3333-333333333333'::uuid)
) as participant(user_id)
where contest.id between
  '9a000001-0000-0000-0000-000000000001'::uuid
  and '9a000005-0000-0000-0000-000000000005'::uuid;

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = case user_id
      when '92222222-2222-2222-2222-222222222222'::uuid
        then '9c000002-0000-0000-0000-000000000002'::uuid
      else '9c000003-0000-0000-0000-000000000003'::uuid
    end
where contest_id between
  '9a000001-0000-0000-0000-000000000001'::uuid
  and '9a000005-0000-0000-0000-000000000005'::uuid
  and status = 'invited';

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by
) values (
  '9a000001-0000-0000-0000-000000000001',
  '95555555-5555-5555-5555-555555555555',
  'invited',
  '91111111-1111-1111-1111-111111111111'
);

update public.contests
set status = 'active',
    activated_at = clock_timestamp()
where id between
  '9a000001-0000-0000-0000-000000000001'::uuid
  and '9a000005-0000-0000-0000-000000000005'::uuid;

create or replace function pg_temp.m83c_standings(
  p_alice_total numeric,
  p_bob_total   numeric,
  p_carol_total numeric
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'participant_id', '91111111-1111-1111-1111-111111111111',
      'display_order', 1,
      'rank', 1,
      'qualified', p_alice_total >= 10000,
      'total', p_alice_total,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at',
        case when p_alice_total >= 10000
          then date_trunc('hour', now()) - interval '1 day'
          else null
        end,
      'integrity_score', 98,
      'integrity_flags', jsonb_build_array(),
      'rationale', jsonb_build_array(
        jsonb_build_object(
          'code', 'clean_evidence',
          'summary', 'No scored integrity deductions.',
          'points', 0
        )
      )
    ),
    jsonb_build_object(
      'participant_id', '92222222-2222-2222-2222-222222222222',
      'display_order', 2,
      'rank', 2,
      'qualified', p_bob_total >= 10000,
      'total', p_bob_total,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at',
        case when p_bob_total >= 10000
          then date_trunc('hour', now()) - interval '20 hours'
          else null
        end,
      'integrity_score', 91,
      'integrity_flags', jsonb_build_array('reporting_lag'),
      'rationale', jsonb_build_array(
        jsonb_build_object(
          'code', 'reporting_lag',
          'summary', 'One scored bucket arrived after its ordinary window.',
          'points', -5
        )
      )
    ),
    jsonb_build_object(
      'participant_id', '93333333-3333-3333-3333-333333333333',
      'display_order', 3,
      'rank', 3,
      'qualified', p_carol_total >= 10000,
      'total', p_carol_total,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at',
        case when p_carol_total >= 10000
          then date_trunc('hour', now()) - interval '18 hours'
          else null
        end,
      'integrity_score', 87,
      'integrity_flags', jsonb_build_array('source_reputation'),
      'rationale', jsonb_build_array(
        jsonb_build_object(
          'code', 'source_reputation',
          'summary', 'A third-party source carried a bounded deduction.',
          'points', -8
        )
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Provisional publication and D77 redaction
-- ---------------------------------------------------------------------------

set local role service_role;

select lives_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000001-0000-0000-0000-000000000001',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(5000, 4000, 3000)
     ) $$,
  'trusted service can publish a complete live snapshot'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.get_contest_standings_v1(
    '9a000001-0000-0000-0000-000000000001'
  ) ->> 'phase',
  'provisional',
  'an accepted participant receives an explicit provisional phase'
);

select is(
  public.get_contest_standings_v1(
    '9a000001-0000-0000-0000-000000000001'
  ) ->> 'reason',
  'live',
  'a snapshot inside the contest window is labeled live'
);

select is(
  jsonb_array_length(
    public.get_contest_standings_v1(
      '9a000001-0000-0000-0000-000000000001'
    ) -> 'standings'
  ),
  3,
  'the canonical response contains the complete accepted roster'
);

select is(
  public.get_contest_standings_v1(
    '9a000001-0000-0000-0000-000000000001'
  ) #>> '{standings,0,integrity_score}',
  '98.00',
  'the caller sees their own exact provisional integrity score'
);

select ok(
  not (
    public.get_contest_standings_v1(
      '9a000001-0000-0000-0000-000000000001'
    ) #> '{standings,1}'
  ) ? 'integrity_score'
  and not (
    public.get_contest_standings_v1(
      '9a000001-0000-0000-0000-000000000001'
    ) #> '{standings,1}'
  ) ? 'integrity_flags'
  and not (
    public.get_contest_standings_v1(
      '9a000001-0000-0000-0000-000000000001'
    ) #> '{standings,1}'
  ) ? 'rationale',
  'a rival receives no provisional score, flags, or rationale'
);

select ok(
  not (
    public.get_contest_standings_v1(
      '9a000001-0000-0000-0000-000000000001'
    )
  ) ? 'result',
  'provisional ordering does not predict a result or obligation'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95555555-5555-5555-5555-555555555555"}',
  true
);

select throws_ok(
  $$ select public.get_contest_standings_v1(
       '9a000001-0000-0000-0000-000000000001'
     ) $$,
  '42501',
  null,
  'an invitation is not standings authorization'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"94444444-4444-4444-4444-444444444444"}',
  true
);

select throws_ok(
  $$ select public.get_contest_standings_v1(
       '9a000001-0000-0000-0000-000000000001'
     ) $$,
  '42501',
  null,
  'an unrelated active profile cannot read standings'
);

reset role;

-- ---------------------------------------------------------------------------
-- Frozen winner and exactly one obligation per loser
-- ---------------------------------------------------------------------------

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 8000),
       jsonb_build_object(
         'kind', 'winner',
         'reason', 'earliest_to_target',
         'participant_id', '92222222-2222-2222-2222-222222222222'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'finalization rejects a qualified participant who was not uniquely earliest'
);

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000005-0000-0000-0000-000000000005',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 8000),
       jsonb_build_object(
         'kind', 'winner',
         'reason', 'integrity_score',
         'participant_id', '92222222-2222-2222-2222-222222222222'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'finalization rejects a qualified participant without the top integrity score'
);

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 8000),
       jsonb_build_object(
         'kind', 'inconclusive',
         'reason', 'tie_break_inconclusive'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'finalization rejects inconclusive when one qualifier is uniquely earliest'
);

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000005-0000-0000-0000-000000000005',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 8000),
       jsonb_build_object(
         'kind', 'inconclusive',
         'reason', 'tie_break_inconclusive'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'finalization rejects inconclusive when one qualifier has the top integrity score'
);

select lives_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000005-0000-0000-0000-000000000005',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       jsonb_set(
         pg_temp.m83c_standings(12000, 11000, 8000),
         '{1,integrity_score}',
         '98'::jsonb
       ),
       jsonb_build_object(
         'kind', 'inconclusive',
         'reason', 'tie_break_inconclusive'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  'a genuinely tied top integrity score freezes an inconclusive result'
);

select is(
  (select count(*)
   from public.donation_obligations
   where contest_id = '9a000005-0000-0000-0000-000000000005'),
  0::bigint,
  'an inconclusive result creates no obligations'
);

select lives_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 9000, 8000),
       jsonb_build_object(
         'kind', 'winner',
         'reason', 'sole_qualifier',
         'participant_id', '91111111-1111-1111-1111-111111111111'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  'trusted finalization freezes one winner after grace'
);

reset role;

select is(
  (select status::text
   from public.contests
   where id = '9a000002-0000-0000-0000-000000000002'),
  'finalized',
  'the lifecycle flips to finalized in the result transaction'
);

select is(
  (select kind::text
   from public.contest_results
   where contest_id = '9a000002-0000-0000-0000-000000000002'),
  'winner',
  'the immutable result distinguishes a winner from lifecycle state'
);

select is(
  (select count(*)
   from public.donation_obligations
   where contest_id = '9a000002-0000-0000-0000-000000000002'),
  2::bigint,
  'a three-person winner result creates exactly two loser obligations'
);

select set_eq(
  $$ select debtor_participant_id
     from public.donation_obligations
     where contest_id = '9a000002-0000-0000-0000-000000000002' $$,
  array[
    '92222222-2222-2222-2222-222222222222'::uuid,
    '93333333-3333-3333-3333-333333333333'::uuid
  ],
  'every accepted loser owes once and the winner never owes'
);

select ok(
  (select bool_and(
     destination_owner_id =
       '91111111-1111-1111-1111-111111111111'::uuid
     and amount_cents = 500
     and charity_name = 'Alice Trail Fund'
     and kind = 'loser_to_winner_charity'
     and result_dispute_closes_at = created_at + interval '7 days'
   )
   from public.donation_obligations
   where contest_id = '9a000002-0000-0000-0000-000000000002'),
  'each loser receives the frozen stake, winner charity snapshot, and dispute boundary'
);

select is(
  (select count(*)
   from public.notification_intents
   where event_type = 'contest_finalized'
     and entity_id = '9a000002-0000-0000-0000-000000000002'),
  3::bigint,
  'finalization transaction emits one durable generic intent per participant'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  public.get_contest_standings_v1(
    '9a000002-0000-0000-0000-000000000002'
  ) ->> 'phase',
  'final',
  'an accepted loser receives the immutable final snapshot'
);

select is(
  public.get_contest_standings_v1(
    '9a000002-0000-0000-0000-000000000002'
  ) #>> '{result,kind}',
  'winner',
  'the final response identifies the result kind'
);

select is(
  public.get_contest_standings_v1(
    '9a000002-0000-0000-0000-000000000002'
  ) #>> '{standings,1,obligation,charity_name}',
  'Alice Trail Fund',
  'the losing standing carries its own persisted obligation'
);

select is(
  (
    select count(*)
    from jsonb_array_elements(
      public.get_contest_standings_v1(
        '9a000002-0000-0000-0000-000000000002'
      ) -> 'standings'
    ) standing
    where standing ? 'obligation'
  ),
  1::bigint,
  'the final response never discloses another debtor obligation'
);

select is(
  public.get_contest_standings_v1(
    '9a000002-0000-0000-0000-000000000002'
  ) #>> '{standings,0,integrity_score}',
  '98.00',
  'final disclosure includes a rival exact integrity score'
);

reset role;
set local role service_role;

select is(
  public.publish_contest_standings_v1(
    '9a000002-0000-0000-0000-000000000002',
    now(),
    'm4-v1',
    'm7-integrity-v1',
    pg_temp.m83c_standings(12000, 9000, 8000),
    jsonb_build_object(
      'kind', 'winner',
      'reason', 'sole_qualifier',
      'participant_id', '91111111-1111-1111-1111-111111111111'
    ),
    date_trunc('hour', now()) - interval '1 hour'
  ),
  (
    select snapshot.id
    from public.contest_standing_snapshots snapshot
    where snapshot.contest_id =
      '9a000002-0000-0000-0000-000000000002'
      and snapshot.phase = 'final'
  ),
  'an exact lost-response retry returns the existing final snapshot'
);

select is(
  (select count(*)
   from public.contest_results
   where contest_id = '9a000002-0000-0000-0000-000000000002'),
  1::bigint,
  'an exact retry does not duplicate the result'
);

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000002-0000-0000-0000-000000000002',
       now(),
       'm4-v2',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 9000, 8000),
       jsonb_build_object(
         'kind', 'winner',
         'reason', 'sole_qualifier',
         'participant_id', '91111111-1111-1111-1111-111111111111'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '23505',
  null,
  'a finalized contest rejects a changed result payload'
);

reset role;

-- ---------------------------------------------------------------------------
-- all_donate uses the complete roster, including a nonqualifier
-- ---------------------------------------------------------------------------

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000003-0000-0000-0000-000000000003',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 9000),
       jsonb_build_object(
         'kind', 'all_donate',
         'reason', 'both_donate',
         'participant_ids', jsonb_build_array(
           '91111111-1111-1111-1111-111111111111',
           '92222222-2222-2222-2222-222222222222'
         )
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'all-donate refuses a tied-qualifier subset'
);

select lives_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000003-0000-0000-0000-000000000003',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 11000, 9000),
       jsonb_build_object(
         'kind', 'all_donate',
         'reason', 'both_donate',
         'participant_ids', jsonb_build_array(
           '91111111-1111-1111-1111-111111111111',
           '92222222-2222-2222-2222-222222222222',
           '93333333-3333-3333-3333-333333333333'
         )
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  'all-donate accepts the complete roster'
);

reset role;

select is(
  (select count(*)
   from public.donation_obligations
   where contest_id = '9a000003-0000-0000-0000-000000000003'),
  3::bigint,
  'all-donate creates one self-directed obligation for every accepted participant'
);

select ok(
  (select bool_and(
     debtor_participant_id = destination_owner_id
     and kind = 'self_directed'
     and amount_cents = 700
   )
   from public.donation_obligations
   where contest_id = '9a000003-0000-0000-0000-000000000003'),
  'all-donate preserves each participant nomination and exact accepted exposure'
);

select is(
  (select charity_name
   from public.donation_obligations
   where contest_id = '9a000003-0000-0000-0000-000000000003'
     and debtor_participant_id =
       '93333333-3333-3333-3333-333333333333'),
  'Carol Arts Fund',
  'the nonqualifier still receives their self-directed all-donate obligation'
);

-- ---------------------------------------------------------------------------
-- Gates and immutability
-- ---------------------------------------------------------------------------

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000004-0000-0000-0000-000000000004',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       pg_temp.m83c_standings(12000, 9000, 8000),
       jsonb_build_object(
         'kind', 'winner',
         'reason', 'sole_qualifier',
         'participant_id', '91111111-1111-1111-1111-111111111111'
       ),
       date_trunc('hour', now()) + interval '5 hours'
     ) $$,
  '23001',
  null,
  'finalization refuses to run before ingest grace closes'
);

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       '9a000001-0000-0000-0000-000000000001',
       now(),
       'm4-v1',
       'm7-integrity-v1',
       jsonb_build_array(
         (pg_temp.m83c_standings(5000, 4000, 3000) -> 0),
         (pg_temp.m83c_standings(5000, 4000, 3000) -> 1)
       )
     ) $$,
  '22023',
  null,
  'a snapshot cannot omit one accepted participant'
);

reset role;

select throws_ok(
  $$ update public.contest_results
     set reason = 'earliest_to_target'
     where contest_id = '9a000002-0000-0000-0000-000000000002' $$,
  '23001',
  null,
  'results are append-only'
);

select throws_ok(
  $$ delete from public.donation_obligations
     where contest_id = '9a000002-0000-0000-0000-000000000002' $$,
  '23001',
  null,
  'obligations are append-only'
);

select * from finish();
rollback;
