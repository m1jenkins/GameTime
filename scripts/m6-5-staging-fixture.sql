\set ON_ERROR_STOP on

-- Repeatable, staging-only data for the M6.5 real-device conformance target.
--
-- Usage:
--   STAGING_DATABASE_URL=... CONFORMANCE_USER_ID=... \
--     ./scripts/m6-5-install-staging-fixture.sh
--
-- Do not invoke this file directly. The wrapper proves that the database URL's
-- host matches the separately reviewed project identity in
-- supabase/staging-project-ref. The fixed IDs make reruns deterministic. Only
-- a row already carrying this fixture's exact synthetic identity is replaced;
-- device registrations and their assertion counters are retained.

\if :{?gametime_environment}
\else
\echo 'gametime_environment is required and must equal staging'
\quit 3
\endif

select :'gametime_environment' = 'staging' as is_staging \gset
\if :is_staging
\else
\echo 'Refusing to install the M6.5 fixture outside staging'
\quit 3
\endif

\if :{?verified_staging_project_ref}
\else
\echo 'Use scripts/m6-5-install-staging-fixture.sh; verified project ref is missing'
\quit 3
\endif

select :'verified_staging_project_ref' ~ '^[a-z0-9]{20}$'
  as project_ref_was_verified \gset
\if :project_ref_was_verified
\else
\echo 'The verified staging project ref has an invalid shape'
\quit 3
\endif

\if :{?conformance_user_id}
\else
\echo 'conformance_user_id is required'
\quit 3
\endif

\if :{?latitude}
\else
\echo 'latitude is required'
\quit 3
\endif

\if :{?longitude}
\else
\echo 'longitude is required'
\quit 3
\endif

select exists (
  select 1
  from public.profiles
  where id = :'conformance_user_id'::uuid
) as user_is_onboarded \gset

\if :user_is_onboarded
\else
\echo 'The conformance user has no profile; complete onboarding first'
\quit 3
\endif

select not exists (
  select 1
  from public.charities
  where id = '65000000-0000-4000-8000-000000000004'
    and (
      name <> 'GameTime M6.5 Staging Fixture'
      or slug <> 'gametime-m65-staging'
      or ein <> '00-0000065'
    )
) as charity_identity_is_safe \gset

\if :charity_identity_is_safe
\else
\echo 'Reserved fixture charity ID belongs to another row; refusing to overwrite it'
\quit 3
\endif

select not exists (
  select 1
  from public.contests
  where id = '65000000-0000-4000-8000-000000000001'
    and (
      title <> 'M6.5 device conformance — not a real contest'
      or created_by <> :'conformance_user_id'::uuid
    )
) as contest_identity_is_safe \gset

\if :contest_identity_is_safe
\else
\echo 'Reserved fixture contest ID belongs to another row; refusing to delete it'
\quit 3
\endif

begin;

-- Obviously synthetic and isolated to staging. This is not a real donation
-- destination and the reserved .test host cannot resolve.
insert into public.charities (
  id, name, ein, slug, url, is_active
) values (
  '65000000-0000-4000-8000-000000000004',
  'GameTime M6.5 Staging Fixture',
  '00-0000065',
  'gametime-m65-staging',
  'https://m65.gametime.example.test',
  true
)
on conflict (id) do update
set name = excluded.name,
    ein = excluded.ein,
    slug = excluded.slug,
    url = excluded.url,
    is_active = true;

delete from public.contests
where id = '65000000-0000-4000-8000-000000000001';

-- The target needs a finished hourly bucket now. The backdating guard is
-- disabled only inside this transaction and restored before anything commits.
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
) values (
  '65000000-0000-4000-8000-000000000001',
  'M6.5 device conformance — not a real contest',
  :'conformance_user_id'::uuid,
  'steps',
  'cumulative',
  100,
  100,
  'void',
  date_trunc('hour', clock_timestamp(), 'UTC') - interval '6 hours',
  date_trunc('hour', clock_timestamp(), 'UTC') + interval '24 hours',
  2
);

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  timezone,
  charity_id
) values (
  '65000000-0000-4000-8000-000000000001',
  :'conformance_user_id'::uuid,
  'accepted',
  'UTC',
  '65000000-0000-4000-8000-000000000004'
);

insert into public.contest_geofences (
  id,
  contest_id,
  name,
  center_latitude,
  center_longitude,
  radius_meters,
  max_accuracy_meters,
  minimum_dwell_seconds,
  maximum_sample_gap_seconds,
  minimum_workout_overlap_seconds
) values (
  '65000000-0000-4000-8000-000000000003',
  '65000000-0000-4000-8000-000000000001',
  'M6.5 staging device location',
  :'latitude'::numeric,
  :'longitude'::numeric,
  100,
  50,
  10,
  90,
  10
);

update public.contests
set status = 'active',
    activated_at = clock_timestamp()
where id = '65000000-0000-4000-8000-000000000001';

commit;

\echo 'M6.5 staging fixture installed'
select
  '65000000-0000-4000-8000-000000000001'::uuid as contest_id,
  '65000000-0000-4000-8000-000000000003'::uuid as geofence_id,
  date_trunc('hour', clock_timestamp(), 'UTC') - interval '2 hours'
    as metric_bucket_start,
  :'latitude'::numeric as latitude,
  :'longitude'::numeric as longitude;
