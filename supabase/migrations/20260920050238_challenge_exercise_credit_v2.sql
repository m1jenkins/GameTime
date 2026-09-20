-- P9: a new agreement policy. Historical strict Exercise v1, consent, receipts
-- and signed requests retain their identity and semantics. No runtime gate opens.
select set_config('app.challenge_write_v1','on',true);
alter table app.challenge_real_health_source_policies_v1
 drop constraint challenge_real_health_source_policies_v1_version_check;
alter table app.challenge_real_health_source_policies_v1
 add constraint challenge_real_health_source_policies_v1_version_check check (
  version in ('apple_watch_steps_v1','apple_watch_exercise_v1','apple_watch_exercise_credit_v2',
   'apple_workout_outdoor_distance_v1','apple_workout_outdoor_timed_v1'));
insert into app.challenge_real_health_source_policies_v1(version,metric,terms) values (
 'apple_watch_exercise_credit_v2','exercise',
 '{"version":"apple_watch_exercise_credit_v2","metric":"exercise","unit":"whole_seconds","activity_label":"Activity minutes","credit":"Apple Exercise credit from eligible Watch-origin samples","accepted_causal_uncertainty":true,"causal_disclosure":"Apple Exercise credit can include indirectly derived credit. It does not measure every minute of movement. We exclude identifiable manual entries and unsupported sources, but cannot identify every activity that caused the credit.","writer_rule":"apple_health_system_watch_revision_tuple_d138","reconciliation":"reconcile_watch_switches_and_sync_revisions_before_total","normalization":"floor_total_minutes_times_60_once","missing_rule":"unresolved_never_confirmed_miss"}'::jsonb
);
create or replace function app.challenge_real_health_policy_metric_v1(p_source text)
returns text language sql immutable set search_path='' as $$
 select case p_source
  when 'apple_watch_steps_v1' then 'steps'
  when 'apple_watch_exercise_v1' then 'exercise'
  when 'apple_watch_exercise_credit_v2' then 'exercise'
  when 'apple_workout_outdoor_distance_v1' then 'distance'
  when 'apple_workout_outdoor_timed_v1' then 'timed' end
$$;
create or replace function app.challenge_real_health_policy_available_v1(p_source text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_source in ('apple_watch_steps_v1','apple_watch_exercise_credit_v2',
  'apple_workout_outdoor_distance_v1','apple_workout_outdoor_timed_v1'),false)
$$;
create function app.challenge_exercise_credit_terms_v2(p_source text)
returns jsonb language sql stable set search_path='' as $$
 select case when p_source='apple_watch_exercise_credit_v2' then
  jsonb_build_object('source_terms',(select terms from app.challenge_real_health_source_policies_v1 where version=p_source))
  else '{}'::jsonb end
$$;
revoke all on function app.challenge_exercise_credit_terms_v2(text) from public,anon,authenticated,service_role;

do $$
declare d text; marker text;
begin
 d:=pg_get_functiondef('app.challenge_real_health_payload_v1(jsonb)'::regprocedure);
 marker:='(p->>''metric''=''exercise'' and state_value=''value'')';
 if position(marker in d)=0 then raise exception 'Unexpected strict Exercise payload guard'; end if;
 execute replace(d,marker,'(p->>''source_policy_version''=''apple_watch_exercise_v1'' and state_value=''value'')');
 d:=pg_get_functiondef('app.challenge_real_health_evaluate_v1(uuid,boolean)'::regprocedure);
 marker:='or app.challenge_policy_v1(challenge.policy)->>''metric''=''exercise''';
 if position(marker in d)=0 then raise exception 'Unexpected strict Exercise result guard'; end if;
 execute replace(d,marker,'or challenge.real_source_policy_version=''apple_watch_exercise_v1''');
 -- Terms are added before digest construction, only for new v2 agreements.
 d:=pg_get_functiondef('app.challenge_real_health_personal_terms_v1(uuid,text,jsonb,bigint,text)'::regprocedure);
 marker:='jsonb_build_object(''source'',p_source_policy_version,''source_policy_version'',p_source_policy_version)';
 if position(marker in d)=0 then raise exception 'Unexpected Personal source terms'; end if;
 execute replace(d,marker,marker||'||app.challenge_exercise_credit_terms_v2(p_source_policy_version)');
 d:=pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
 marker:='jsonb_build_object(''source'',c.real_source_policy_version,''source_policy_version'',c.real_source_policy_version)';
 if position(marker in d)=0 then raise exception 'Unexpected friend source terms'; end if;
 d:=replace(d,marker,marker||'||app.challenge_exercise_credit_terms_v2(c.real_source_policy_version)');
 marker:='policy_name:=coalesce(p_payload->>''policy'',''friend_steps_goal_v1''); pol:=app.challenge_policy_v1(policy_name);';
 if position(marker in d)=0 then raise exception 'Unexpected real mode admission'; end if;
 d:=replace(d,marker,marker||' if real_source is not null and pol->>''competition''=''leaderboard'' then raise exception ''challenge_real_leaderboard_unavailable'' using errcode=''22023''; end if;');
 execute d;
end $$;
-- Existing readiness/admission, source/digest/window matching, key/counter
-- recovery and privacy use these explicit mappings. Community stays steps-only.
