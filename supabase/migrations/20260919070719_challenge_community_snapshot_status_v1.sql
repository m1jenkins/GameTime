-- Read-only local monitoring for one explicitly selected published cohort.
-- Capture timestamps use the challenge clock; invocation timestamps are wall
-- clock records. A checked invocation can be a throttled no-op, never a capture.
create index challenge_snapshot_invocations_attempted_v1
 on app.challenge_snapshot_invocations_v1(challenge_id,dispatched_at desc,id desc)
 where dispatched_at is not null;

create function public.challenge_community_snapshot_status_v1(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 runtime app.challenge_runtime_v1;
 attempt app.challenge_snapshot_invocations_v1;
 wall_now timestamptz := statement_timestamp();
 capture_now timestamptz;
 captured timestamptz;
 pending timestamptz;
 succeeded timestamptz;
 capture_gate text;
begin
 perform app.duel_require_service_v1();
 if p_id is null then
  raise exception 'challenge_invalid_snapshot' using errcode='22023';
 end if;
 if not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) then
  raise exception 'challenge_snapshot_unavailable' using errcode='42501';
 end if;

 -- These are the capture RPC's gates, not worker processing/admission controls.
 -- Do not call capture, disclosure helpers, locks or any write/audit operation.
 select * into runtime from app.challenge_runtime_v1 where singleton;
 capture_gate := case when not found then 'runtime_unavailable'
  when not runtime.fixtures then 'fixtures_disabled'
  when not runtime.discovery then 'discovery_disabled' else 'enabled' end;
 if capture_gate <> 'runtime_unavailable' then
  capture_now := coalesce(runtime.fictional_now,wall_now);
 end if;
 select captured_at into captured from app.challenge_community_snapshots_v1
  where challenge_id=p_id order by captured_at desc limit 1;
 select prepared_at into pending from app.challenge_snapshot_invocations_v1
  where challenge_id=p_id and state='prepared';
 select * into attempt from app.challenge_snapshot_invocations_v1
  where challenge_id=p_id and dispatched_at is not null
  order by dispatched_at desc,id desc limit 1;
 select dispatched_at into succeeded from app.challenge_snapshot_invocations_v1
  where challenge_id=p_id and state='dispatched' and dispatched_at is not null
  order by dispatched_at desc,id desc limit 1;

 return jsonb_build_object(
  'server_time',wall_now,
  'capture_authorization',capture_gate,
  'snapshot_age_clock',case when capture_now is null then 'unavailable'
   when runtime.fictional_now is not null then 'fixture' else 'server' end,
  'snapshot_clock_now',capture_now,
  'capture_status',case when captured is null then 'missing'
   when capture_now is null then 'clock_unavailable'
   when captured>capture_now then 'ahead_of_clock' else 'recorded' end,
  'last_capture_at',captured,
  'capture_age_seconds',case when captured<=capture_now
   then floor(extract(epoch from capture_now-captured)) end,
  'pending_invocation_prepared_at',pending,
  'last_attempt_at',attempt.dispatched_at,
  'last_attempt_status',case when attempt.id is null then 'none'
   when attempt.state='dispatched' then 'checked'
   when attempt.last_error_code='42501' then 'disabled' else 'failed' end,
  'last_attempt_error_code',case when attempt.state='failed' then attempt.last_error_code end,
  'last_successful_invocation_at',succeeded
 );
end $$;

revoke all on function public.challenge_community_snapshot_status_v1(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.challenge_community_snapshot_status_v1(uuid) to service_role;
comment on function public.challenge_community_snapshot_status_v1(uuid) is
 'Service-only read-only local capture age and dispatch status. No freshness threshold; snapshot age uses the current challenge clock, not invocation wall time.';
