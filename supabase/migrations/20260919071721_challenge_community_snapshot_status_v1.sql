-- Local, service-only observation of one explicitly selected published cohort.
-- No capture, disclosure, runtime, scheduler or alert-policy changes.
create function public.challenge_community_snapshot_status_v1(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 runtime app.challenge_runtime_v1;
 wall timestamptz := statement_timestamp();
 reference_at timestamptz;
 capture_at timestamptz;
 prepared_at timestamptz;
 attempted_at timestamptz;
 succeeded_at timestamptz;
 attempt_state text;
 error_code text;
 published boolean;
begin
 perform app.duel_require_service_v1();
 if p_id is null then
  raise exception 'challenge_snapshot_selection_required' using errcode='22023';
 end if;
 select * into runtime from app.challenge_runtime_v1 where singleton;
 reference_at := case when runtime.singleton then coalesce(runtime.fictional_now,wall) end;
 select exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) into published;
 if published then
  select max(captured_at) into capture_at
   from app.challenge_community_snapshots_v1 where challenge_id=p_id;
  select max(i.prepared_at), max(i.dispatched_at) filter(where i.state='dispatched')
   into prepared_at,succeeded_at from app.challenge_snapshot_invocations_v1 i where i.challenge_id=p_id;
  select i.dispatched_at,i.state,i.last_error_code into attempted_at,attempt_state,error_code
   from app.challenge_snapshot_invocations_v1 i
   where i.challenge_id=p_id and i.dispatched_at is not null
   order by i.dispatched_at desc,i.id desc limit 1;
 end if;
 return jsonb_build_object(
  'observed_wall_at',wall,
  -- Captures use challenge_now_v1; journal timestamps always use wall time.
  -- The old snapshot table does not record the clock mode at capture time.
  -- reference_clock labels ONLY the current reference, never historical origin.
  'reference_clock',case when runtime.singleton is null then 'unavailable' when runtime.fictional_now is not null then 'fixture' else 'wall' end,
  'snapshot_reference_at',reference_at,
  'capture_state',case when not published then 'cohort_unavailable'
   when runtime.singleton is null then 'runtime_unavailable'
   when not runtime.fixtures then 'fixtures_disabled'
   when not runtime.discovery then 'discovery_disabled' else 'enabled' end,
  'snapshot_state',case when not published then 'unavailable'
   when capture_at is null then 'missing'
   when reference_at is null then 'clock_unavailable'
   when capture_at>reference_at then 'clock_ahead' else 'recorded' end,
  'last_capture_at',capture_at,
  'capture_age_seconds',case when capture_at<=reference_at then floor(extract(epoch from reference_at-capture_at)) end,
  'last_prepared_wall_at',prepared_at,
  'last_attempt_wall_at',attempted_at,
  'last_attempt_state',case when attempt_state='dispatched' then 'checked' when attempt_state='failed' then 'failed' else 'none' end,
  'last_attempt_error_code',case when error_code ~ '^[0-9A-Z]{5}$' then error_code end,
  'last_successful_invocation_wall_at',succeeded_at
 );
end $$;
revoke all on function public.challenge_community_snapshot_status_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.challenge_community_snapshot_status_v1(uuid) to service_role;
