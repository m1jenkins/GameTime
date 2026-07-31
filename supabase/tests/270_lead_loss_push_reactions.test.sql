-- M8: a complete provisional ranking transition emits one generic lead-loss
-- intent, the trailing participant can react once, and delivery is leased to a
-- service-only APNs worker.

begin;
select plan(38);

select ok(
  'contest_lead_lost' = any(enum_range(null::public.notification_event_type)::text[]),
  'lead loss has a closed notification event type'
);
select has_table(
  'public',
  'contest_standings_reactions',
  'standings reactions are durable'
);
select has_table(
  'public',
  'push_device_tokens',
  'APNs device addresses have a dedicated table'
);
select has_table(
  'public',
  'push_notification_deliveries',
  'best-effort delivery state is separate from business intents'
);
select ok(
  (select bool_and(relrowsecurity)
   from pg_catalog.pg_class
   where oid in (
     'public.contest_standings_reactions'::regclass,
     'public.push_device_tokens'::regclass,
     'public.push_notification_deliveries'::regclass
   )),
  'all new public tables have RLS enabled'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.register_push_device_v1(text,public.push_token_environment,text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.send_comeback_reaction_v1(uuid,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.unregister_push_device_v1(text,public.push_token_environment,text)',
    'execute'
  ),
  'authenticated users receive only the narrow device and reaction RPCs'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.push_device_tokens', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.contest_standings_reactions', 'select'
  ),
  'clients cannot read device addresses or bypass the reaction RPC'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.claim_push_deliveries_v1(uuid,integer)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.record_push_delivery_v1(uuid,uuid,text,integer,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_push_deliveries_v1(uuid,integer)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.record_push_delivery_v1(uuid,uuid,text,integer,text)',
    'execute'
  ),
  'only the delivery worker can claim and record APNs work'
);

insert into auth.users (id) values
  ('e7111111-1111-1111-1111-111111111111'),
  ('e7222222-2222-2222-2222-222222222222');

insert into public.profiles (id, handle, display_name) values
  ('e7111111-1111-1111-1111-111111111111', 'leadalice', 'Alice'),
  ('e7222222-2222-2222-2222-222222222222', 'leadbob', 'Bob');

insert into public.charities (id, name, ein, slug) values (
  'ac000001-0000-0000-0000-000000000001',
  'Comeback Fund',
  '91-7000001',
  'comeback-fund'
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
  max_participants,
  status,
  activated_at
) values (
  'aa000001-0000-0000-0000-000000000001',
  'Lead change',
  'e7111111-1111-1111-1111-111111111111',
  'steps',
  'cumulative',
  10000,
  500,
  'integrity_score',
  now() - interval '1 day',
  now() + interval '1 day',
  2,
  'pending',
  null
);
alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by,
  timezone,
  charity_id,
  accepted_at
) values
  (
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    'accepted',
    null,
    'UTC',
    'ac000001-0000-0000-0000-000000000001',
    now() - interval '2 days'
  ),
  (
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    'invited',
    'e7111111-1111-1111-1111-111111111111',
    null,
    null,
    null
  );

update public.contest_participants
set
  status = 'accepted',
  timezone = 'UTC',
  charity_id = 'ac000001-0000-0000-0000-000000000001'
where contest_id = 'aa000001-0000-0000-0000-000000000001'
  and user_id = 'e7222222-2222-2222-2222-222222222222';

update public.contests
set
  status = 'active',
  activated_at = clock_timestamp()
where id = 'aa000001-0000-0000-0000-000000000001';

insert into public.contest_standing_snapshots (
  id,
  contest_id,
  phase,
  reason,
  as_of,
  scoring_version,
  integrity_configuration_version,
  input_digest
) values (
  'ab000001-0000-0000-0000-000000000001',
  'aa000001-0000-0000-0000-000000000001',
  'provisional',
  'live',
  now() - interval '2 hours',
  'lead-test-v1',
  'integrity-test-v1',
  decode(repeat('11', 32), 'hex')
);

insert into public.contest_standing_entries (
  snapshot_id,
  contest_id,
  participant_id,
  display_order,
  rank,
  qualified,
  total,
  qualifying_days,
  scoreable_days,
  day_rate,
  integrity_score
) values
  (
    'ab000001-0000-0000-0000-000000000001',
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    1, 1, false, 8000, 0, 1, 0, 100
  ),
  (
    'ab000001-0000-0000-0000-000000000001',
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    2, 2, false, 7000, 0, 1, 0, 100
  );

select is(
  (select count(*) from public.notification_intents
   where event_type = 'contest_lead_lost')::bigint,
  0::bigint,
  'an initial ranking does not manufacture a lead-loss event'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e7111111-1111-1111-1111-111111111111"}',
  true
);
select lives_ok(
  $$ select public.register_push_device_v1(
       repeat('ab', 32),
       'development',
       'com.mjenkins.gametime.staging'
     ) $$,
  'the signed-in actor can register an address before the lead-loss event'
);
reset role;

insert into public.contest_standing_snapshots (
  id,
  contest_id,
  phase,
  reason,
  as_of,
  scoring_version,
  integrity_configuration_version,
  input_digest
) values (
  'ab000002-0000-0000-0000-000000000002',
  'aa000001-0000-0000-0000-000000000001',
  'provisional',
  'live',
  now() - interval '1 hour',
  'lead-test-v1',
  'integrity-test-v1',
  decode(repeat('22', 32), 'hex')
);

insert into public.contest_standing_entries (
  snapshot_id,
  contest_id,
  participant_id,
  display_order,
  rank,
  qualified,
  total,
  qualifying_days,
  scoreable_days,
  day_rate,
  integrity_score
) values
  (
    'ab000002-0000-0000-0000-000000000002',
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    1, 1, false, 9000, 0, 1, 0, 100
  ),
  (
    'ab000002-0000-0000-0000-000000000002',
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    2, 2, false, 8500, 0, 1, 0, 100
  );

select is(
  (select count(*) from public.notification_intents
   where event_type = 'contest_lead_lost')::bigint,
  1::bigint,
  'falling from rank one appends exactly one intent'
);
select is(
  (select recipient_user_id from public.notification_intents
   where event_type = 'contest_lead_lost'),
  'e7111111-1111-1111-1111-111111111111'::uuid,
  'the prior leader is the recipient'
);
select is(
  (select entity_id from public.notification_intents
   where event_type = 'contest_lead_lost'),
  'ab000002-0000-0000-0000-000000000002'::uuid,
  'the new snapshot is the opaque idempotent event id'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e7111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_reaction as
select public.send_comeback_reaction_v1(
  'aa000001-0000-0000-0000-000000000001',
  'ab000002-0000-0000-0000-000000000002'
) as id;

select ok(
  (select id is not null from t_reaction),
  'the trailing participant can send a comeback reaction'
);
select is(
  public.send_comeback_reaction_v1(
    'aa000001-0000-0000-0000-000000000001',
    'ab000002-0000-0000-0000-000000000002'
  ),
  (select id from t_reaction),
  'retrying the same reaction returns its original identity'
);
select throws_ok(
  $$ select public.register_push_device_v1(
       repeat('cd', 32),
       'production',
       'com.mjenkins.gametime.staging'
     ) $$,
  '23514',
  null,
  'staging cannot register a production APNs address'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e7222222-2222-2222-2222-222222222222"}',
  true
);
select throws_ok(
  $$ select public.send_comeback_reaction_v1(
       'aa000001-0000-0000-0000-000000000001',
       'ab000002-0000-0000-0000-000000000002'
     ) $$,
  '23001',
  null,
  'the current leader cannot send a comeback reaction'
);
reset role;

select is(
  (select user_id from public.push_device_tokens
   where device_token = repeat('ab', 32)),
  'e7111111-1111-1111-1111-111111111111'::uuid,
  'the token is bound to the authenticated actor'
);
select is(
  (select count(*) from public.contest_standings_reactions)::bigint,
  1::bigint,
  'the idempotent reaction exists exactly once'
);

insert into public.contest_standing_snapshots (
  id,
  contest_id,
  phase,
  reason,
  as_of,
  scoring_version,
  integrity_configuration_version,
  input_digest
) values (
  'ab000003-0000-0000-0000-000000000003',
  'aa000001-0000-0000-0000-000000000001',
  'provisional',
  'live',
  now() - interval '30 minutes',
  'lead-test-v1',
  'integrity-test-v1',
  decode(repeat('33', 32), 'hex')
);

insert into public.contest_standing_entries (
  snapshot_id,
  contest_id,
  participant_id,
  display_order,
  rank,
  qualified,
  total,
  qualifying_days,
  scoreable_days,
  day_rate,
  integrity_score
) values
  (
    'ab000003-0000-0000-0000-000000000003',
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    1, 1, false, 9500, 0, 1, 0, 100
  ),
  (
    'ab000003-0000-0000-0000-000000000003',
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    2, 2, false, 9000, 0, 1, 0, 100
  );

select is(
  (select count(*) from public.notification_intents
   where event_type = 'contest_lead_lost')::bigint,
  1::bigint,
  'remaining behind does not emit another lead-loss event'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e7111111-1111-1111-1111-111111111111"}',
  true
);
select throws_ok(
  $$ select public.send_comeback_reaction_v1(
       'aa000001-0000-0000-0000-000000000001',
       'ab000002-0000-0000-0000-000000000002'
     ) $$,
  '23001',
  null,
  'a stale standings snapshot cannot receive a new reaction'
);
reset role;

set local role service_role;
create temporary table t_claim as
select public.claim_push_deliveries_v1(
  'ad000001-0000-0000-0000-000000000001',
  25
) as claims;
select is(
  jsonb_array_length((select claims from t_claim)),
  1,
  'the worker claims the due intent for the active device'
);
select is(
  (select claims -> 0 ->> 'contest_id' from t_claim),
  'aa000001-0000-0000-0000-000000000001',
  'the claim resolves the snapshot to its opaque contest route'
);
select lives_ok(
  $$ select public.record_push_delivery_v1(
       ((select claims from t_claim) -> 0 ->> 'delivery_id')::uuid,
       'ad000001-0000-0000-0000-000000000001',
       'delivered',
       200,
       null
     ) $$,
  'the lease owner can record APNs acceptance'
);
reset role;

select is(
  (select count(*) from public.push_notification_deliveries
   where delivered_at is not null)::bigint,
  1::bigint,
  'delivery acceptance is recorded outside the business intent'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e7111111-1111-1111-1111-111111111111"}',
  true
);
select lives_ok(
  $$ select public.register_push_device_v1(
       repeat('ef', 32),
       'development',
       'com.mjenkins.gametime.staging'
     ) $$,
  'a later device binding can register without inheriting prior outbox work'
);
reset role;

set local role service_role;
create temporary table t_historical_claim as
select public.claim_push_deliveries_v1(
  'ad000002-0000-0000-0000-000000000002',
  25
) as claims;
select is(
  jsonb_array_length((select claims from t_historical_claim)),
  0,
  'a newly bound device does not receive a historical lead-loss event'
);
reset role;

-- Bob loses first place when Alice regains it, then Alice has a distinct
-- second loss event when Bob moves back ahead.
insert into public.contest_standing_snapshots (
  id,
  contest_id,
  phase,
  reason,
  as_of,
  scoring_version,
  integrity_configuration_version,
  input_digest
) values (
  'ab000004-0000-0000-0000-000000000004',
  'aa000001-0000-0000-0000-000000000001',
  'provisional',
  'live',
  now() - interval '20 minutes',
  'lead-test-v1',
  'integrity-test-v1',
  decode(repeat('44', 32), 'hex')
);

insert into public.contest_standing_entries (
  snapshot_id,
  contest_id,
  participant_id,
  display_order,
  rank,
  qualified,
  total,
  qualifying_days,
  scoreable_days,
  day_rate,
  integrity_score
) values
  (
    'ab000004-0000-0000-0000-000000000004',
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    1, 1, false, 10000, 0, 1, 0, 100
  ),
  (
    'ab000004-0000-0000-0000-000000000004',
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    2, 2, false, 9700, 0, 1, 0, 100
  );

insert into public.contest_standing_snapshots (
  id,
  contest_id,
  phase,
  reason,
  as_of,
  scoring_version,
  integrity_configuration_version,
  input_digest
) values (
  'ab000005-0000-0000-0000-000000000005',
  'aa000001-0000-0000-0000-000000000001',
  'provisional',
  'live',
  now() - interval '10 minutes',
  'lead-test-v1',
  'integrity-test-v1',
  decode(repeat('55', 32), 'hex')
);

insert into public.contest_standing_entries (
  snapshot_id,
  contest_id,
  participant_id,
  display_order,
  rank,
  qualified,
  total,
  qualifying_days,
  scoreable_days,
  day_rate,
  integrity_score
) values
  (
    'ab000005-0000-0000-0000-000000000005',
    'aa000001-0000-0000-0000-000000000001',
    'e7222222-2222-2222-2222-222222222222',
    1, 1, false, 10500, 0, 1, 0, 100
  ),
  (
    'ab000005-0000-0000-0000-000000000005',
    'aa000001-0000-0000-0000-000000000001',
    'e7111111-1111-1111-1111-111111111111',
    2, 2, false, 10100, 0, 1, 0, 100
  );

select is(
  (select count(*)
   from public.notification_intents intent
   where intent.event_type = 'contest_lead_lost'
     and intent.recipient_user_id =
       'e7111111-1111-1111-1111-111111111111')::bigint,
  2::bigint,
  'a regain followed by a later loss emits a new event for that participant'
);
select is(
  (select count(*)
   from public.notification_intents intent
   where intent.event_type = 'contest_lead_lost'
     and intent.recipient_user_id =
       'e7111111-1111-1111-1111-111111111111'
     and intent.entity_id =
       'ab000005-0000-0000-0000-000000000005')::bigint,
  1::bigint,
  'the later snapshot is its own idempotent lead-loss event'
);

set local role service_role;
create temporary table t_second_claim as
select public.claim_push_deliveries_v1(
  'ad000003-0000-0000-0000-000000000003',
  25
) as claims;
select is(
  jsonb_array_length((select claims from t_second_claim)),
  2,
  'the later event is claimed once for each device already bound to the actor'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      (select claims from t_second_claim)
    ) item(claim)
    where item.claim ->> 'snapshot_id' <>
      'ab000005-0000-0000-0000-000000000005'
  ),
  'both claims belong only to the later snapshot'
);
reset role;

update public.push_notification_deliveries delivery
set attempt_count = 8
where delivery.id = (
  select (item.claim ->> 'delivery_id')::uuid
  from jsonb_array_elements(
    (select claims from t_second_claim)
  ) item(claim)
  where item.claim ->> 'device_token' = repeat('ab', 32)
);

set local role service_role;
select lives_ok(
  $$ select public.record_push_delivery_v1(
       (
         select (item.claim ->> 'delivery_id')::uuid
         from jsonb_array_elements(
           (select claims from t_second_claim)
         ) item(claim)
         where item.claim ->> 'device_token' = repeat('ab', 32)
       ),
       'ad000003-0000-0000-0000-000000000003',
       'retry',
       503,
       'ServiceUnavailable'
     ) $$,
  'the final retry attempt is recorded without stranding the delivery'
);
reset role;

select ok(
  (select delivery.permanently_failed_at is not null
   from public.push_notification_deliveries delivery
   where delivery.id = (
     select (item.claim ->> 'delivery_id')::uuid
     from jsonb_array_elements(
       (select claims from t_second_claim)
     ) item(claim)
     where item.claim ->> 'device_token' = repeat('ab', 32)
   )),
  'attempt eight terminalizes a retryable failure'
);
select is(
  (select delivery.last_reason
   from public.push_notification_deliveries delivery
   where delivery.id = (
     select (item.claim ->> 'delivery_id')::uuid
     from jsonb_array_elements(
       (select claims from t_second_claim)
     ) item(claim)
     where item.claim ->> 'device_token' = repeat('ab', 32)
   )),
  'RetryLimitExceeded',
  'retry exhaustion has a bounded terminal reason'
);

set local role service_role;
select lives_ok(
  $$ select public.record_push_delivery_v1(
       (
         select (item.claim ->> 'delivery_id')::uuid
         from jsonb_array_elements(
           (select claims from t_second_claim)
         ) item(claim)
         where item.claim ->> 'device_token' = repeat('ef', 32)
       ),
       'ad000003-0000-0000-0000-000000000003',
       'permanent_failure',
       410,
       'Unregistered'
     ) $$,
  'APNs unregistration permanently records the delivery'
);
reset role;

select ok(
  (select token.invalidated_at is not null
   from public.push_device_tokens token
   where token.device_token = repeat('ef', 32)),
  'APNs unregistration invalidates the matching device token'
);

set local role service_role;
select is(
  jsonb_array_length(
    public.claim_push_deliveries_v1(
      'ad000004-0000-0000-0000-000000000004',
      25
    )
  ),
  0,
  'terminal and invalidated deliveries are not claimed again'
);
reset role;

select is(
  (select count(*) from cron.job
   where jobname = 'gametime-dispatch-push')::bigint,
  1::bigint,
  'one named minute worker dispatches due push work'
);

select * from finish();
rollback;
