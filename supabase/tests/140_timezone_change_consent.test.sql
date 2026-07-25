-- M5: a participant's accepted timezone remains the immutable base epoch.
-- Later epochs require unanimous consent from every other accepted participant,
-- and ingest resolves the epoch at the bucket rather than at write time.

begin;
select plan(69);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), -- alice, requester
  ('22222222-2222-2222-2222-222222222222'), -- bob, reviewer/epoch fixture
  ('33333333-3333-3333-3333-333333333333'), -- carol, reviewer
  ('44444444-4444-4444-4444-444444444444'), -- dave, invited roster member
  ('55555555-5555-5555-5555-555555555555'); -- erin, unrelated

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol'),
  ('44444444-4444-4444-4444-444444444444', 'dave',  'Dave'),
  ('55555555-5555-5555-5555-555555555555', 'erin',  'Erin');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001',
   'Trail Fund', '12-3456789', 'trail-fund');

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values
  (
    'a0000001-0000-0000-0000-000000000001',
    'Timezone Group', '11111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 10000, 2500,
    date_trunc('hour', now()) - interval '10 days',
    date_trunc('hour', now()) + interval '2 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    'Still Pending', '11111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 10000, 2500,
    date_trunc('hour', now()) + interval '1 day',
    date_trunc('hour', now()) + interval '3 days',
    2
  ),
  (
    'a0000001-0000-0000-0000-000000000003',
    'Already Ended', '11111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 10000, 2500,
    date_trunc('hour', now()) - interval '5 days',
    date_trunc('hour', now()) - interval '1 hour',
    2
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id, user_id, status, invited_by, timezone, charity_id
) values
  (
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111', 'accepted', null,
    'UTC', 'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222', 'invited',
    '11111111-1111-1111-1111-111111111111', null, null
  ),
  (
    'a0000001-0000-0000-0000-000000000001',
    '33333333-3333-3333-3333-333333333333', 'invited',
    '11111111-1111-1111-1111-111111111111', null, null
  ),
  (
    'a0000001-0000-0000-0000-000000000001',
    '44444444-4444-4444-4444-444444444444', 'invited',
    '11111111-1111-1111-1111-111111111111', null, null
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111', 'accepted', null,
    'UTC', 'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111', 'accepted', null,
    'UTC', 'c0000001-0000-0000-0000-000000000001'
  );

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = 'a0000001-0000-0000-0000-000000000001'
  and user_id in (
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
  );

update public.contests
set status = 'active', activated_at = now()
where id in (
  'a0000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000003'
);

-- ---------------------------------------------------------------------------
-- Shape, indexes, RLS, and least privilege
-- ---------------------------------------------------------------------------

select has_type(
  'public', 'timezone_change_state',
  'timezone consent has a closed computed-state vocabulary'
);
select has_table(
  'public', 'timezone_change_requests',
  'timezone requests are durable'
);
select has_column(
  'public', 'timezone_change_requests', 'required_reviewer_count',
  'each request snapshots its immutable consent denominator'
);
select has_table(
  'public', 'timezone_change_reviews',
  'timezone reviews are a separate vote ledger'
);
select has_table(
  'public', 'timezone_change_applied_events',
  'applied timezone epochs are explicit events'
);
select has_view(
  'public', 'timezone_change_request_status',
  'request status is computed rather than overwritten'
);
select ok(
  (select 'security_invoker=true' = any(reloptions)
   from pg_class
   where oid = 'public.timezone_change_request_status'::regclass),
  'the status view invokes underlying RLS'
);
select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.timezone_change_requests'::regclass,
     'public.timezone_change_reviews'::regclass,
     'public.timezone_change_applied_events'::regclass
   )),
  'all three consent ledgers have RLS enabled'
);
select has_index(
  'public', 'timezone_change_requests',
  'timezone_change_requests_participant_idx',
  'the request participant foreign key and unresolved scan are indexed'
);
select has_index(
  'public', 'timezone_change_reviews',
  'timezone_change_reviews_reviewer_idx',
  'the review reviewer foreign key is indexed'
);
select has_index(
  'public', 'timezone_change_applied_events',
  'timezone_change_applied_events_epoch_idx',
  'applied epochs are indexed by contest, participant, and effective time'
);
select ok(
  (select index_definition.indexdef like 'CREATE UNIQUE INDEX%'
   from pg_catalog.pg_indexes index_definition
   where index_definition.schemaname = 'public'
     and index_definition.indexname =
       'timezone_change_applied_events_epoch_idx'),
  'one participant cannot have two ambiguous epochs at the same instant'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.timezone_change_requests', 'select'
  )
  and has_table_privilege(
    'authenticated', 'public.timezone_change_reviews', 'select'
  )
  and has_table_privilege(
    'authenticated', 'public.timezone_change_applied_events', 'select'
  ),
  'authenticated roster members may select consent facts'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.timezone_change_requests', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_requests', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_requests', 'delete'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_reviews', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_reviews', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_reviews', 'delete'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_applied_events', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_applied_events', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.timezone_change_applied_events', 'delete'
  ),
  'authenticated callers cannot write any consent fact directly'
);
select ok(
  not has_table_privilege(
    'anon', 'public.timezone_change_requests', 'select'
  )
  and not has_table_privilege(
    'anon', 'public.timezone_change_reviews', 'select'
  )
  and not has_table_privilege(
    'anon', 'public.timezone_change_applied_events', 'select'
  ),
  'anonymous callers cannot read consent facts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.request_timezone_change(uuid,text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.review_timezone_change(uuid,boolean)',
    'execute'
  ),
  'authenticated callers reach only the guarded consent functions'
);
select ok(
  not has_function_privilege(
    'anon', 'public.request_timezone_change(uuid,text)', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.review_timezone_change(uuid,boolean)', 'execute'
  ),
  'anonymous callers cannot invoke the consent functions'
);
select ok(
  not has_table_privilege(
    'service_role', 'public.timezone_change_requests', 'insert'
  )
  and not has_table_privilege(
    'service_role', 'public.timezone_change_requests', 'update'
  )
  and not has_table_privilege(
    'service_role', 'public.timezone_change_requests', 'delete'
  )
  and not has_table_privilege(
    'service_role', 'public.timezone_change_reviews', 'insert'
  )
  and not has_table_privilege(
    'service_role', 'public.timezone_change_applied_events', 'insert'
  )
  and not has_function_privilege(
    'service_role', 'public.request_timezone_change(uuid,text)', 'execute'
  )
  and not has_function_privilege(
    'service_role', 'public.review_timezone_change(uuid,boolean)', 'execute'
  ),
  'service_role can inspect consent facts but cannot bypass guarded user writes'
);

-- ---------------------------------------------------------------------------
-- Request eligibility, validation, and pending idempotency
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}',
  true
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000001', 'Asia/Kolkata') $$,
  '23001',
  null,
  'an invited but unaccepted roster member cannot request a change'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}',
  true
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000001', 'Asia/Kolkata') $$,
  '42501',
  null,
  'an outsider cannot request a change'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000002', 'Asia/Kolkata') $$,
  '23001',
  null,
  'a pending contest cannot accept a timezone request'
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000003', 'Asia/Kolkata') $$,
  '23001',
  null,
  'an active row whose ends_at has passed cannot accept a request'
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000001', 'Mars/Olympus') $$,
  '22023',
  null,
  'the requested target must be a valid IANA zone'
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000001', 'UTC') $$,
  '22023',
  null,
  'the target must differ from the currently effective zone'
);

create temporary table t_request as
select public.request_timezone_change(
  'a0000001-0000-0000-0000-000000000001',
  'Asia/Kolkata'
) as id;

select is(
  (select state
   from public.timezone_change_request_status
   where id = (select id from t_request)),
  'pending'::public.timezone_change_state,
  'silence leaves the request pending'
);
select is(
  (select reviewer_count
   from public.timezone_change_request_status
   where id = (select id from t_request)),
  2,
  'a group request requires every other accepted participant'
);
select is(
  public.request_timezone_change(
    'a0000001-0000-0000-0000-000000000001',
    'Asia/Kolkata'
  ),
  (select id from t_request),
  'an identical pending request retry returns the same id'
);
select ok(
  (
    select count(*) = 2
       and count(distinct recipient_user_id) = 2
       and bool_and(
         recipient_user_id in (
           '22222222-2222-2222-2222-222222222222',
           '33333333-3333-3333-3333-333333333333'
         )
       )
    from public.notification_intents
    where event_type = 'timezone_consent_requested'
      and entity_id = (select id from t_request)
  ),
  'the request retry cannot duplicate either opponent-consent intent'
);
select throws_ok(
  $$ select public.request_timezone_change(
       'a0000001-0000-0000-0000-000000000001',
       'America/New_York') $$,
  '23505',
  null,
  'a different target cannot replace an unresolved request'
);

-- ---------------------------------------------------------------------------
-- Eligibility, immutable votes, and unanimous group approval
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  '42501',
  null,
  'the requester cannot approve their own timezone change'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}',
  true
);
select throws_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  '42501',
  null,
  'an outsider cannot review a timezone change'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  'one accepted opponent may approve'
);
select is(
  (select state
   from public.timezone_change_request_status
   where id = (select id from t_request)),
  'pending'::public.timezone_change_state,
  'one approval is still pending in a three-person contest'
);
select is(
  (select count(*)
   from public.timezone_change_applied_events
   where request_id = (select id from t_request)),
  0::bigint,
  'partial approval creates no applied event'
);
select is(
  (
    select count(*)
    from public.notification_intents
    where event_type = 'timezone_consent_resolved'
      and entity_id = (select id from t_request)
  ),
  0::bigint,
  'partial approval does not tell the requester consent is resolved'
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  'an identical vote retry is idempotent'
);
select throws_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), false) $$,
  '23001',
  null,
  'a conflicting vote retry cannot rewrite history'
);

-- The authority truncates effective_at to milliseconds, so the bound has to be
-- truncated the same way. Comparing against a raw microsecond reading fails
-- whenever the bound and the approval land in the same millisecond.
create temporary table t_approval_window as
select date_trunc('milliseconds', clock_timestamp()) as lower_bound;

select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  'the final accepted opponent may approve'
);
select is(
  (select state
   from public.timezone_change_request_status
   where id = (select id from t_request)),
  'approved'::public.timezone_change_state,
  'unanimous approval resolves the group request'
);
select is(
  (select count(*)
   from public.timezone_change_applied_events
   where request_id = (select id from t_request)),
  1::bigint,
  'unanimous approval creates exactly one applied event'
);
select ok(
  (select effective_at >= (select lower_bound from t_approval_window)
          and effective_at <= clock_timestamp()
   from public.timezone_change_applied_events
   where request_id = (select id from t_request)),
  'the final approval supplies effective_at from the server clock'
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_request), true) $$,
  'retrying the final approval remains idempotent'
);
select is(
  (select count(*)
   from public.timezone_change_applied_events
   where request_id = (select id from t_request)),
  1::bigint,
  'a final-approval retry cannot duplicate the applied event'
);
select ok(
  (
    select count(*) = 1
       and bool_and(
         recipient_user_id = '11111111-1111-1111-1111-111111111111'
       )
    from public.notification_intents
    where event_type = 'timezone_consent_resolved'
      and entity_id = (select id from t_request)
  ),
  'final approval and its requester-resolution intent are idempotent together'
);
select is(
  (select timezone
   from public.contest_participants
   where contest_id = 'a0000001-0000-0000-0000-000000000001'
     and user_id = '11111111-1111-1111-1111-111111111111'),
  'UTC'::text,
  'the roster timezone remains the immutable initial zone'
);

-- ---------------------------------------------------------------------------
-- Rejection is terminal
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
create temporary table t_rejected_request as
select public.request_timezone_change(
  'a0000001-0000-0000-0000-000000000001',
  'America/New_York'
) as id;

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_rejected_request), false) $$,
  'an accepted opponent may reject'
);
select is(
  (select state
   from public.timezone_change_request_status
   where id = (select id from t_rejected_request)),
  'rejected'::public.timezone_change_state,
  'one rejection is terminal under unanimous consent'
);
select is(
  (select count(*)
   from public.timezone_change_applied_events
   where request_id = (select id from t_rejected_request)),
  0::bigint,
  'a rejected request creates no applied event'
);
select lives_ok(
  $$ select public.review_timezone_change(
       (select id from t_rejected_request), false) $$,
  'an identical rejection retry is idempotent'
);
select ok(
  (
    select count(*) = 1
       and bool_and(
         recipient_user_id = '11111111-1111-1111-1111-111111111111'
       )
    from public.notification_intents
    where event_type = 'timezone_consent_resolved'
      and entity_id = (select id from t_rejected_request)
  ),
  'rejection and its requester-resolution intent are idempotent together'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select throws_ok(
  $$ select public.review_timezone_change(
       (select id from t_rejected_request), true) $$,
  '23001',
  null,
  'no later vote can reopen a rejected request'
);

-- ---------------------------------------------------------------------------
-- Append-only enforcement and the original roster freeze
-- ---------------------------------------------------------------------------

reset role;
select throws_ok(
  $$ update public.timezone_change_requests
     set to_timezone = 'Pacific/Honolulu'
     where id = (select id from t_request) $$,
  '23001',
  null,
  'request facts cannot be updated even by a privileged writer'
);
select throws_ok(
  $$ update public.timezone_change_reviews
     set approved = false
     where request_id = (select id from t_request)
       and reviewer_user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23001',
  null,
  'review facts cannot be updated even by a privileged writer'
);
select throws_ok(
  $$ update public.timezone_change_applied_events
     set effective_at = effective_at + interval '1 hour'
     where request_id = (select id from t_request) $$,
  '23001',
  null,
  'applied events cannot be updated even by a privileged writer'
);
select throws_ok(
  $$ update public.contest_participants
     set timezone = 'Asia/Kolkata'
     where contest_id = 'a0000001-0000-0000-0000-000000000001'
       and user_id = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'consent does not unfreeze contest_participants.timezone'
);

-- ---------------------------------------------------------------------------
-- Effective-time ingest, late revisions, and a straddling hour
-- ---------------------------------------------------------------------------

create temporary table t_epochs as
select
  date_trunc('hour', now()) - interval '4 days' + interval '30 minutes'
    as effective_at;

insert into public.timezone_change_requests (
  id, contest_id, user_id, from_timezone, to_timezone, requested_at,
  required_reviewer_count
) values (
  'b0000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222',
  'UTC',
  'Asia/Kolkata',
  (select effective_at - interval '1 hour' from t_epochs),
  2
);

insert into public.timezone_change_reviews (
  request_id, reviewer_user_id, approved, reviewed_at
) values
  (
    'b0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    true,
    (select effective_at from t_epochs)
  ),
  (
    'b0000001-0000-0000-0000-000000000001',
    '33333333-3333-3333-3333-333333333333',
    true,
    (select effective_at from t_epochs)
  );

insert into public.timezone_change_applied_events (
  id, request_id, contest_id, user_id, from_timezone, to_timezone, effective_at
) values (
  'b1000001-0000-0000-0000-000000000001',
  'b0000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222',
  'UTC',
  'Asia/Kolkata',
  (select effective_at from t_epochs)
);

create or replace function pg_temp.new_timezone_batch(p_tag text)
returns uuid
language sql
as $$
  insert into public.ingest_batches (
    contest_id, user_id, client_batch_id, attested, payload_digest,
    observation_count, observed_at
  )
  values (
    'a0000001-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222',
    md5(p_tag)::uuid,
    false,
    extensions.digest(p_tag, 'sha256'),
    1,
    now()
  )
  returning id;
$$;

create temporary table t_buckets as
select
  effective_at - interval '2 hours 30 minutes' as old_bucket,
  effective_at as new_bucket,
  date_trunc('hour', effective_at) as straddling_bucket
from t_epochs;

select lives_ok(
  format($$ insert into public.metric_snapshots (
      batch_id, contest_id, user_id, metric, bucket_start, value,
      provenance, sample_count, observed_at, local_day, local_hour
    ) values (
      %L, 'a0000001-0000-0000-0000-000000000001',
      '22222222-2222-2222-2222-222222222222', 'steps',
      %L, 100, 'device', 1, now(), 'epoch', 0
    ) $$,
    pg_temp.new_timezone_batch('timezone-old-1'),
    (select old_bucket from t_buckets)),
  'a bucket before the change still uses the initial UTC epoch'
);
select lives_ok(
  format($$ insert into public.metric_snapshots (
      batch_id, contest_id, user_id, metric, bucket_start, value,
      provenance, sample_count, observed_at, local_day, local_hour
    ) values (
      %L, 'a0000001-0000-0000-0000-000000000001',
      '22222222-2222-2222-2222-222222222222', 'steps',
      %L, 150, 'device', 2, now(), 'epoch', 0
    ) $$,
    pg_temp.new_timezone_batch('timezone-old-2'),
    (select old_bucket from t_buckets)),
  'a late upward revision before the change keeps the old zone'
);
select ok(
  (select count(*) = 2
          and bool_and(local_day = (bucket_start at time zone 'UTC')::date)
          and bool_and(
            local_hour = extract(
              hour from bucket_start at time zone 'UTC'
            )::smallint
          )
   from public.metric_snapshots
   where contest_id = 'a0000001-0000-0000-0000-000000000001'
     and user_id = '22222222-2222-2222-2222-222222222222'
     and bucket_start = (select old_bucket from t_buckets)),
  'both old-epoch observations are stamped from UTC'
);
select lives_ok(
  format($$ insert into public.metric_snapshots (
      batch_id, contest_id, user_id, metric, bucket_start, value,
      provenance, sample_count, observed_at, local_day, local_hour
    ) values (
      %L, 'a0000001-0000-0000-0000-000000000001',
      '22222222-2222-2222-2222-222222222222', 'steps',
      %L, 200, 'device', 3, now(), 'epoch', 0
    ) $$,
    pg_temp.new_timezone_batch('timezone-new'),
    (select new_bucket from t_buckets)),
  'a bucket at the effective boundary uses the new Kolkata epoch'
);
select ok(
  (select local_day = (bucket_start at time zone 'Asia/Kolkata')::date
          and local_hour = extract(
            hour from bucket_start at time zone 'Asia/Kolkata'
          )::smallint
   from public.metric_snapshots
   where contest_id = 'a0000001-0000-0000-0000-000000000001'
     and user_id = '22222222-2222-2222-2222-222222222222'
     and bucket_start = (select new_bucket from t_buckets)),
  'new-epoch local fields come from Asia/Kolkata'
);
select throws_ok(
  format($$ insert into public.metric_snapshots (
      batch_id, contest_id, user_id, metric, bucket_start, value,
      provenance, sample_count, observed_at, local_day, local_hour
    ) values (
      %L, 'a0000001-0000-0000-0000-000000000001',
      '22222222-2222-2222-2222-222222222222', 'steps',
      %L, 300, 'device', 4, now(), 'epoch', 0
    ) $$,
    pg_temp.new_timezone_batch('timezone-straddle'),
    (select straddling_bucket from t_buckets)),
  '22023',
  null,
  'an hour with an effective_at strictly inside it is rejected'
);

-- ---------------------------------------------------------------------------
-- RLS visibility is the contest roster, not the whole social graph
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}',
  true
);
select ok(
  (select count(*) > 0 from public.timezone_change_requests)
  and (select count(*) > 0 from public.timezone_change_reviews)
  and (select count(*) > 0 from public.timezone_change_applied_events)
  and (select count(*) > 0 from public.timezone_change_request_status),
  'an invited roster member may read the contest consent history'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}',
  true
);
select ok(
  (select count(*) = 0 from public.timezone_change_requests)
  and (select count(*) = 0 from public.timezone_change_reviews)
  and (select count(*) = 0 from public.timezone_change_applied_events)
  and (select count(*) = 0 from public.timezone_change_request_status),
  'an unrelated account cannot enumerate consent history'
);
select throws_ok(
  $$ insert into public.timezone_change_requests (
       contest_id, user_id, from_timezone, to_timezone
     ) values (
       'a0000001-0000-0000-0000-000000000001',
       '55555555-5555-5555-5555-555555555555',
       'UTC', 'Asia/Kolkata'
     ) $$,
  '42501',
  null,
  'an authenticated caller cannot bypass the request function'
);
reset role;

-- The epoch trigger protects privileged fixture/import paths too. This request
-- also proves that deleting a silent reviewer cannot shrink the denominator.
insert into public.timezone_change_requests (
  id, contest_id, user_id, from_timezone, to_timezone,
  required_reviewer_count
) values (
  'b0000001-0000-0000-0000-000000000003',
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'Asia/Kolkata',
  'Pacific/Honolulu',
  2
);
insert into public.timezone_change_reviews (
  request_id, reviewer_user_id, approved
) values (
  'b0000001-0000-0000-0000-000000000003',
  '33333333-3333-3333-3333-333333333333',
  true
);
select throws_ok(
  $$ insert into public.timezone_change_applied_events (
       request_id, contest_id, user_id, from_timezone, to_timezone, effective_at
     ) values (
       'b0000001-0000-0000-0000-000000000003',
       'a0000001-0000-0000-0000-000000000001',
       '11111111-1111-1111-1111-111111111111',
       'Asia/Kolkata',
       'Pacific/Honolulu',
       date_trunc('milliseconds', clock_timestamp())
         + interval '1 microsecond'
     ) $$,
  '23514',
  null,
  'a privileged writer cannot persist a sub-millisecond timezone epoch'
);
select throws_ok(
  $$ insert into public.timezone_change_applied_events (
       request_id, contest_id, user_id, from_timezone, to_timezone, effective_at
     )
     select
       'b0000001-0000-0000-0000-000000000003',
       id,
       '11111111-1111-1111-1111-111111111111',
       'Asia/Kolkata',
       'Pacific/Honolulu',
       ends_at
     from public.contests
     where id = 'a0000001-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'an epoch on the contest boundary is rejected even for a privileged writer'
);

-- A privileged account cascade must be able to remove the request children.
-- Direct callers still have neither a DELETE grant nor a DELETE policy.
insert into public.timezone_change_requests (
  id, contest_id, user_id, from_timezone, to_timezone,
  required_reviewer_count
) values (
  'b0000001-0000-0000-0000-000000000002',
  'a0000001-0000-0000-0000-000000000001',
  '44444444-4444-4444-4444-444444444444',
  'UTC',
  'America/Chicago',
  2
);
insert into public.timezone_change_reviews (
  request_id, reviewer_user_id, approved
) values (
  'b0000001-0000-0000-0000-000000000002',
  '22222222-2222-2222-2222-222222222222',
  true
);
insert into public.timezone_change_applied_events (
  id, request_id, contest_id, user_id, from_timezone, to_timezone
) values (
  'b1000001-0000-0000-0000-000000000002',
  'b0000001-0000-0000-0000-000000000002',
  'a0000001-0000-0000-0000-000000000001',
  '44444444-4444-4444-4444-444444444444',
  'UTC',
  'America/Chicago'
);
select lives_ok(
  $$ delete from auth.users
     where id = '44444444-4444-4444-4444-444444444444' $$,
  'account deletion may cascade through all three consent ledgers'
);
select lives_ok(
  $$ delete from auth.users
     where id = '22222222-2222-2222-2222-222222222222' $$,
  'account deletion may retain the reviewer UUID as a pseudonymous audit fact'
);
select ok(
  (select state = 'approved'::public.timezone_change_state
   from public.timezone_change_request_status
   where id = (select id from t_request))
  and
  (select state = 'pending'::public.timezone_change_state
   from public.timezone_change_request_status
   where id = 'b0000001-0000-0000-0000-000000000003'),
  'reviewer deletion neither reopens approval nor turns silence into consent'
);

select * from finish();
rollback;
