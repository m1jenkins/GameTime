-- Hosted-order upgrade rehearsal, part 1 of 2. Run only on a disposable
-- stack whose migrations stop at 20260922150718 and leave out
-- 20260920162025, 20260922181912 and later, which matches gametime-p11b on
-- September 22. It commits fictional rows and a rehearsal-only clock seam.
-- Part 2 is friends-upgrade-after.inc, run after `migration up --include-all`.
begin;
create schema friends_upgrade;
create table friends_upgrade.clock(now timestamptz not null);
insert into friends_upgrade.clock values ('2026-09-22 19:00:00+00');
grant usage on schema friends_upgrade to authenticated, service_role;
grant select on friends_upgrade.clock to authenticated, service_role;
create or replace function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path = '' as $$
  select coalesce((select now from friends_upgrade.clock), clock_timestamp())
$$;

-- Hosted configuration: private trial on, one enrolled account, device
-- proof off, real admission, ingestion and processing on.
insert into auth.users(id) values ('b7000000-0000-4000-8000-000000000701');
insert into public.profiles(id, handle, display_name, timezone)
  values ('b7000000-0000-4000-8000-000000000701', 'upgrade701', 'Fictional Upgrade', 'America/Los_Angeles');
insert into auth.sessions(id, user_id)
  values ('b7100000-0000-4000-8000-000000000701', 'b7000000-0000-4000-8000-000000000701');
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_age_v1 values ('b7000000-0000-4000-8000-000000000701', 'age_21_v1', '2026-09-20 12:00:00+00');
update app.challenge_private_device_trial_v1 set enabled = true, require_device_verification = false;
insert into app.challenge_private_device_accounts_v1(actor_id) values ('b7000000-0000-4000-8000-000000000701');
select public.challenge_real_health_runtime_v1(true, true, true);

create function pg_temp.call(q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"b7000000-0000-4000-8000-000000000701","session_id":"b7100000-0000-4000-8000-000000000701"}', true);
  perform set_config('role', 'authenticated', true);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;

select public.challenge_real_health_readiness_v1('b7200000-0000-4000-8000-000000000001',
  'b7000000-0000-4000-8000-000000000701', 'apple_watch_steps_v1', '2026-09-22 18:59:00+00',
  'b7100000-0000-4000-8000-000000000701', clock_timestamp() + interval '1 hour', null, null,
  extensions.digest('upgrade readiness', 'sha256'), false, null);

create table friends_upgrade.goal as
select p as preview, pg_temp.call(format($q$select public.challenge_mutate_v1('b7200000-0000-4000-8000-000000000002', %L::jsonb)$q$,
  jsonb_build_object('op', 'personal_commit', 'policy', 'personal_steps_goal_v1',
    'config', '{"start_date":"2026-09-24","days":7,"timezone":"America/Los_Angeles","amount_cents":2000}'::jsonb,
    'target', 4703, 'digest', p->>'digest', 'consent', true, 'source_policy_version', 'apple_watch_steps_v1'))) as receipt
from (select pg_temp.call($q$select public.challenge_personal_preview_v1('personal_steps_goal_v1',
  '{"start_date":"2026-09-24","days":7,"timezone":"America/Los_Angeles","amount_cents":2000}'::jsonb,
  4703, 'apple_watch_steps_v1')$q$) p) x;

-- Midway through the goal: it starts, then one saved update.
update friends_upgrade.clock set now = '2026-09-26 19:00:00+00';
select public.challenge_process_v1((receipt->>'id')::uuid) from friends_upgrade.goal;
create function pg_temp.progress(p_request uuid, p_revision integer, p_value integer) returns jsonb language sql as $$
  select public.challenge_real_health_ingest_v1(p_request, body, 'b7100000-0000-4000-8000-000000000701',
    clock_timestamp() + interval '1 hour', null, null, extensions.digest(body::text, 'sha256'), false)
  from (select jsonb_build_object('contract_version', 1, 'actor_id', c.creator_id, 'challenge_id', c.id,
    'agreement_version', c.agreement_version, 'terms_digest', a.digest, 'source_policy_version', 'apple_watch_steps_v1',
    'metric', 'steps', 'window_starts_at', c.starts_at, 'window_ends_at', c.ends_at, 'request_id', p_request,
    'revision', p_revision, 'previous_revision', case when p_revision = 1 then null else p_revision - 1 end,
    'state', 'value', 'value', p_value, 'observed_at', k.now, 'queried_through_at', k.now) body
    from friends_upgrade.goal g
    join app.challenge_lobbies_v1 c on c.id = (g.receipt->>'id')::uuid
    join app.challenge_agreements_v1 a on a.challenge_id = c.id and a.version = c.agreement_version
    cross join friends_upgrade.clock k) b
$$;
select pg_temp.progress('b7200000-0000-4000-8000-000000000003', 1, 3000);

create table friends_upgrade.before as
select c.id, c.status, c.revision, a.digest, a.terms,
  (select jsonb_agg(to_jsonb(f) order by f.revision) from app.challenge_real_health_facts_v1 f where f.challenge_id = c.id) facts,
  app.challenge_real_health_evaluate_v1(c.id) evaluation,
  (select array_agg(version order by version) from supabase_migrations.schema_migrations) migrations
from friends_upgrade.goal g
join app.challenge_lobbies_v1 c on c.id = (g.receipt->>'id')::uuid
join app.challenge_agreements_v1 a on a.challenge_id = c.id and a.version = c.agreement_version;
commit;
