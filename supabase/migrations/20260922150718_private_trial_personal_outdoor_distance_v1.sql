-- Widen the enabled private-device trial without turning it off.
-- Personal steps and personal outdoor-run distance may be written.
-- Friend, community, Activity minutes, timed runs, and mismatched pairs stay refused.
-- The exception name stays so existing clients keep their recovery mapping.
create function app.challenge_private_trial_pair_allowed_v1(p_source text, p_policy text)
returns boolean language sql immutable set search_path = '' as $$
  select case p_source
    when 'apple_watch_steps_v1' then p_policy is null or p_policy = 'personal_steps_goal_v1'
    when 'apple_workout_outdoor_distance_v1' then p_policy is null or p_policy = 'personal_distance_goal_v1'
    else false
  end;
$$;

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
  return new;
end;
$$;

revoke all on function app.challenge_private_trial_pair_allowed_v1(text, text),
  app.challenge_private_device_row_guard_v1()
  from public, anon, authenticated, service_role;
