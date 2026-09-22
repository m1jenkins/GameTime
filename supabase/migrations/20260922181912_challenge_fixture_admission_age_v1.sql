-- Restore 21+ confirmation on the fixture admission branch. The check was
-- added in 20260908050901 and dropped when 20260920010824 rewrote this
-- function; 20260920160248 kept the gap. The body below is 20260920160248's
-- definition with one addition: after the existing paused check, a fixture
-- actor without an age record is refused with `challenge_age_required`, in the
-- order 20260908050901 used. Private-trial checks, the real-health branch,
-- suspension handling and every error code are otherwise unchanged.
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
  if not exists (select 1 from app.challenge_age_v1 where actor_id = a) then
    raise exception 'challenge_age_required' using errcode = '42501';
  end if;
end;
$$;
