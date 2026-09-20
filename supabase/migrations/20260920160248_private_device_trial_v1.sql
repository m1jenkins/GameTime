-- Optional, project-local private-device trial. The selected hosted project
-- enables this only after its operator has enrolled the actual Apple sign-in
-- account. Ordinary installations retain their historical behavior.
create table app.challenge_private_device_trial_v1 (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into app.challenge_private_device_trial_v1 default values;

create table app.challenge_private_device_accounts_v1 (
  actor_id uuid primary key references auth.users(id) on delete cascade,
  enrolled_at timestamptz not null default clock_timestamp()
);
alter table app.challenge_private_device_trial_v1 enable row level security;
alter table app.challenge_private_device_accounts_v1 enable row level security;
revoke all on app.challenge_private_device_trial_v1,
  app.challenge_private_device_accounts_v1 from public, anon, authenticated, service_role;

create function app.challenge_private_device_allowed_v1(p_actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not coalesce((select enabled from app.challenge_private_device_trial_v1 where singleton), true)
    or exists(select 1 from app.challenge_private_device_accounts_v1 where actor_id = p_actor);
$$;

create function app.challenge_private_device_require_v1(p_actor uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.challenge_private_device_allowed_v1(p_actor) then
    raise exception 'challenge_private_trial_account_required' using errcode = '42501';
  end if;
end;
$$;

-- Preserve the existing fixture branch. A real-source command must have an
-- enrolled account, and the private trial supports only Personal steps.
create or replace function app.challenge_admit_v1(a uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if (select enabled from app.challenge_private_device_trial_v1 where singleton) then
    perform app.challenge_private_device_require_v1(a);
    if current_setting('app.challenge_real_health_command_v1', true) is distinct from 'on' then
      raise exception 'challenge_private_trial_personal_steps_only' using errcode = '42501';
    end if;
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
end;
$$;

-- These row guards also cover service RPC receipt recovery and any future
-- direct privileged writer. Existing records remain readable for safe exits.
create function app.challenge_private_device_row_guard_v1()
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
     and (source_version <> 'apple_watch_steps_v1' or policy_name is not null and policy_name <> 'personal_steps_goal_v1') then
    raise exception 'challenge_private_trial_personal_steps_only' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger challenge_private_trial_device_registration
  before insert on public.device_attestations for each row
  execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_lobby
  before insert or update of real_source_policy_version on app.challenge_lobbies_v1
  for each row execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_consent
  before insert on app.challenge_consents_v1 for each row
  execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_readiness
  before insert or update on app.challenge_real_health_readiness_v1
  for each row execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_readiness_request
  before insert on app.challenge_real_health_readiness_requests_v1
  for each row execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_admission
  before insert on app.challenge_real_health_admissions_v1 for each row
  execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_fact
  before insert on app.challenge_real_health_facts_v1 for each row
  execute function app.challenge_private_device_row_guard_v1();
create trigger challenge_private_trial_real_request
  before insert on app.challenge_real_health_requests_v1 for each row
  execute function app.challenge_private_device_row_guard_v1();

revoke all on function app.challenge_private_device_allowed_v1(uuid),
  app.challenge_private_device_require_v1(uuid),
  app.challenge_private_device_row_guard_v1() from public, anon, authenticated, service_role;
