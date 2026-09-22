-- D142 build 1: a server-side per-policy allowlist and an account-mode
-- setting, independent of the private-device trial.
--
-- Before this, the only per-policy control was the immutable source list plus
-- the private trial's pair guard, and turning the trial off opened every real
-- policy, community included. Now:
--
-- * challenge_policy_allowlist_v1 holds the (policy, source) pairs a project
--   offers. It is seeded with the trial's two pairs, Personal Steps and
--   Personal Outdoor runs, so the enabled trial behaves exactly as before.
--   The trial pair guard now reads this list.
-- * With allowlist_enforced on, the same list applies to everyone, with or
--   without the trial. New lobbies, agreement consents, readiness and
--   admissions must name an allowed real pair. The fictional fixture path,
--   community publication and joining, and invitation-link issue and
--   redemption are refused unless the operator allows them. Saved activity
--   for agreements already made is not affected.
-- * account_mode lets any age-confirmed account that isn't suspended save
--   activity without device verification. Each request keeps recording its
--   verification_mode.
-- * challenge_availability_v1 reports the allowed pairs and the caller's
--   verification mode, so the app stops inferring them from its build.
--
-- Every default leaves an existing project unchanged. Hosted values are set
-- by an operator in a separately approved step.

create table app.challenge_policy_runtime_v1 (
  singleton boolean primary key default true check (singleton),
  allowlist_enforced boolean not null default false,
  links_enabled boolean not null default false,
  account_mode boolean not null default false
);
insert into app.challenge_policy_runtime_v1 default values;

create table app.challenge_policy_allowlist_v1 (
  policy text not null check (app.challenge_policy_v1(policy) is not null),
  source_policy_version text not null
    check (app.challenge_real_health_policy_available_v1(source_policy_version)),
  primary key (policy, source_policy_version),
  check (app.challenge_real_health_policy_metric_v1(source_policy_version) = split_part(policy, '_', 2))
);
insert into app.challenge_policy_allowlist_v1 values
  ('personal_steps_goal_v1', 'apple_watch_steps_v1'),
  ('personal_distance_goal_v1', 'apple_workout_outdoor_distance_v1');

alter table app.challenge_policy_runtime_v1 enable row level security;
alter table app.challenge_policy_allowlist_v1 enable row level security;
revoke all on app.challenge_policy_runtime_v1, app.challenge_policy_allowlist_v1
  from public, anon, authenticated, service_role;

create function app.challenge_policy_enforced_v1()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select allowlist_enforced from app.challenge_policy_runtime_v1 where singleton), false);
$$;

-- A source alone (readiness) is allowed when any allowed policy uses it.
create function app.challenge_policy_pair_allowed_v1(p_source text, p_policy text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app.challenge_policy_allowlist_v1
    where source_policy_version = p_source and (p_policy is null or policy = p_policy));
$$;

-- The trial's pair guard keeps its name and error for existing clients; its
-- answer now comes from the allowlist.
create or replace function app.challenge_private_trial_pair_allowed_v1(p_source text, p_policy text)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.challenge_policy_pair_allowed_v1(p_source, p_policy);
$$;

-- The 20260922150718 row guard, plus the enforced allowlist. Admissions now
-- read their challenge's policy so the pair is checked, not only the source.
-- A real create inserts its lobby first and names the source in a following
-- update, which this trigger checks. The real-health command marker is on
-- only when the payload names an available source.
create or replace function app.challenge_private_device_row_guard_v1()
returns trigger language plpgsql set search_path = '' as $$
declare actor uuid; source_version text; policy_name text;
begin
  if tg_table_name = 'device_attestations' then
    actor := new.user_id;
  elsif tg_table_name = 'challenge_lobbies_v1' then
    actor := new.creator_id;
    source_version := new.real_source_policy_version;
    policy_name := new.policy;
  elsif tg_table_name = 'challenge_consents_v1' then
    actor := new.actor_id;
    select real_source_policy_version, policy into source_version, policy_name
      from app.challenge_lobbies_v1 where id = new.challenge_id;
  elsif tg_table_name = 'challenge_real_health_facts_v1' then
    actor := new.actor_id;
    select real_source_policy_version, policy into source_version, policy_name
      from app.challenge_lobbies_v1 where id = new.challenge_id;
  elsif tg_table_name = 'challenge_real_health_requests_v1' then
    actor := new.actor_id;
    source_version := new.payload->>'source_policy_version';
    select policy into policy_name from app.challenge_lobbies_v1
      where id = (new.payload->>'challenge_id')::uuid;
  elsif tg_table_name = 'challenge_real_health_admissions_v1' then
    actor := new.actor_id;
    source_version := new.source_policy_version;
    select policy into policy_name from app.challenge_lobbies_v1 where id = new.challenge_id;
  else
    actor := new.actor_id;
    source_version := new.source_policy_version;
  end if;
  if (tg_table_name = 'device_attestations' or tg_table_name like 'challenge_real_health_%'
      or source_version is not null)
     and not app.challenge_private_device_allowed_v1(actor) then
    raise exception 'challenge_private_trial_account_required' using errcode = '42501';
  end if;
  if (select enabled from app.challenge_private_device_trial_v1 where singleton)
     and source_version is not null
     and not app.challenge_private_trial_pair_allowed_v1(source_version, policy_name) then
    raise exception 'challenge_private_trial_personal_steps_only' using errcode = '42501';
  end if;
  if app.challenge_policy_enforced_v1()
     and tg_table_name in ('challenge_lobbies_v1', 'challenge_consents_v1',
       'challenge_real_health_readiness_v1', 'challenge_real_health_readiness_requests_v1',
       'challenge_real_health_admissions_v1')
     and (case when source_version is not null
       then not app.challenge_policy_pair_allowed_v1(source_version, policy_name)
       else not (tg_table_name = 'challenge_lobbies_v1' and tg_op = 'INSERT'
         and coalesce(current_setting('app.challenge_real_health_command_v1', true), '') = 'on') end) then
    raise exception 'challenge_policy_unavailable' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- The 20260922181912 admission body, plus one check: with the allowlist
-- enforced, the fictional fixture path is closed.
create or replace function app.challenge_admit_v1(a uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if (select enabled from app.challenge_private_device_trial_v1 where singleton) then
    perform app.challenge_private_device_require_v1(a);
    if current_setting('app.challenge_real_health_command_v1', true) is distinct from 'on' then
      raise exception 'challenge_private_trial_personal_steps_only' using errcode = '42501';
    end if;
  end if;
  if app.challenge_policy_enforced_v1()
     and current_setting('app.challenge_real_health_command_v1', true) is distinct from 'on' then
    raise exception 'challenge_policy_unavailable' using errcode = '42501';
  end if;
  if current_setting('app.challenge_real_health_command_v1', true) = 'on'
     and exists (select 1 from app.challenge_real_health_runtime_v1 where singleton and admission_enabled)
  then
    perform app.challenge_private_device_require_v1(a);
    if not exists(select 1 from app.challenge_age_v1 where actor_id = a) then
      raise exception 'challenge_age_required' using errcode = '42501';
    end if;
    if app.challenge_actor_unavailable_v1(a) then
      raise exception 'challenge_admission_paused' using errcode = '42501';
    end if;
    return;
  end if;
  if not exists (
    select 1 from app.challenge_runtime_v1
    where singleton and admission and fixtures
      and (a = any(actors) or exists (select 1 from app.challenge_access_v1 where actor_id = a))
  ) or exists (select 1 from app.challenge_suspensions_v1 where actor_id = a and suspended) then
    raise exception 'challenge_admission_paused' using errcode = '42501';
  end if;
  if not exists (select 1 from app.challenge_age_v1 where actor_id = a) then
    raise exception 'challenge_age_required' using errcode = '42501';
  end if;
end;
$$;

-- Invitation links stay closed under the allowlist unless the operator turns
-- them on. Row guards also cover privileged writers and receipt recovery.
create function app.challenge_policy_link_guard_v1()
returns trigger language plpgsql set search_path = '' as $$
begin
  if app.challenge_policy_enforced_v1()
     and not coalesce((select links_enabled from app.challenge_policy_runtime_v1 where singleton), false) then
    raise exception 'challenge_link_unavailable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger challenge_policy_link_issue
  before insert on app.challenge_links_v1
  for each row execute function app.challenge_policy_link_guard_v1();
create trigger challenge_policy_link_redeem
  before insert on app.challenge_redemptions_v1
  for each row execute function app.challenge_policy_link_guard_v1();

-- Account mode is independent of trial enrollment. The enrolled-account path
-- from 20260920164443 is unchanged.
create or replace function app.challenge_private_account_health_allowed_v1(p_actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app.challenge_private_device_trial_v1 trial
    join app.challenge_private_device_accounts_v1 enrolled on enrolled.actor_id = p_actor
    where trial.singleton and trial.enabled and not trial.require_device_verification
  ) or exists (
    select 1 from app.challenge_policy_runtime_v1 runtime
    where runtime.singleton and runtime.account_mode
      and exists (select 1 from app.challenge_age_v1 where actor_id = p_actor)
      and not app.challenge_actor_unavailable_v1(p_actor)
  );
$$;

-- The goal and leaderboard pairs a project can offer when nothing restricts
-- it. Informational only: creation still passes every existing gate.
create function app.challenge_policy_catalog_v1()
returns table (policy text, source_policy_version text)
language sql immutable set search_path = '' as $$
  values
    ('friend_steps_goal_v1', 'apple_watch_steps_v1'),
    ('friend_exercise_goal_v1', 'apple_watch_exercise_credit_v2'),
    ('friend_distance_goal_v1', 'apple_workout_outdoor_distance_v1'),
    ('friend_timed_goal_v1', 'apple_workout_outdoor_timed_v1'),
    ('friend_steps_leaderboard_v2', 'apple_watch_steps_v1'),
    ('friend_exercise_leaderboard_v2', 'apple_watch_exercise_credit_v2'),
    ('friend_distance_leaderboard_v2', 'apple_workout_outdoor_distance_v1'),
    ('friend_timed_leaderboard_v2', 'apple_workout_outdoor_timed_v1'),
    ('personal_steps_goal_v1', 'apple_watch_steps_v1'),
    ('personal_exercise_goal_v1', 'apple_watch_exercise_credit_v2'),
    ('personal_distance_goal_v1', 'apple_workout_outdoor_distance_v1'),
    ('personal_timed_goal_v1', 'apple_workout_outdoor_timed_v1'),
    ('community_steps_goal_v1', 'apple_watch_steps_v1');
$$;

-- What this project offers the signed-in caller, and how their uploads are
-- verified. "restricted" means the allowlist applies, through the enforced
-- setting or the private trial. links and community are null when this
-- runtime doesn't govern them.
create function public.challenge_availability_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_session_v1();
 trial boolean := coalesce((select enabled from app.challenge_private_device_trial_v1 where singleton), false);
 enforced boolean := app.challenge_policy_enforced_v1();
 restricted boolean := app.challenge_policy_enforced_v1()
   or coalesce((select enabled from app.challenge_private_device_trial_v1 where singleton), false);
begin
  return jsonb_build_object(
    'restricted', restricted,
    'admission', coalesce((select admission_enabled from app.challenge_real_health_runtime_v1 where singleton), false),
    'account_allowed', app.challenge_private_device_allowed_v1(a),
    'verification_mode', case when app.challenge_private_account_health_allowed_v1(a)
      then 'private_account' else 'app_attest' end,
    'policies', coalesce((
      select jsonb_agg(jsonb_build_object('policy', x.policy, 'source_policy_version', x.source_policy_version)
        order by x.policy, x.source_policy_version)
      from (
        select l.policy, l.source_policy_version from app.challenge_policy_allowlist_v1 l where restricted
        union all
        select c.policy, c.source_policy_version from app.challenge_policy_catalog_v1() c where not restricted
      ) x), '[]'),
    'links', case when enforced then coalesce((select links_enabled from app.challenge_policy_runtime_v1 where singleton), false)
      when trial then false end,
    'community', case when restricted then exists (
      select 1 from app.challenge_policy_allowlist_v1 where policy = 'community_steps_goal_v1') end);
end;
$$;

revoke all on function app.challenge_policy_enforced_v1(),
  app.challenge_policy_pair_allowed_v1(text, text),
  app.challenge_private_trial_pair_allowed_v1(text, text),
  app.challenge_private_device_row_guard_v1(),
  app.challenge_policy_link_guard_v1(),
  app.challenge_private_account_health_allowed_v1(uuid),
  app.challenge_policy_catalog_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.challenge_availability_v1() from public, anon, authenticated, service_role;
grant execute on function public.challenge_availability_v1() to authenticated;
