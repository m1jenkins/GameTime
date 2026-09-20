-- P8 ordered continuation: Exercise remains unavailable; cumulative outdoor
-- distance and whole-workout elapsed time share the proven signed boundary.
-- These fixed mappings are versioned policy, never caller-provided allowlists.
create function app.challenge_real_health_policy_metric_v1(p_source text)
returns text language sql immutable set search_path='' as $$
 select case p_source
  when 'apple_watch_steps_v1' then 'steps'
  when 'apple_watch_exercise_v1' then 'exercise'
  when 'apple_workout_outdoor_distance_v1' then 'distance'
  when 'apple_workout_outdoor_timed_v1' then 'timed' end
$$;
create function app.challenge_real_health_policy_available_v1(p_source text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_source in ('apple_watch_steps_v1','apple_workout_outdoor_distance_v1','apple_workout_outdoor_timed_v1'),false)
$$;

alter table app.challenge_lobbies_v1 drop constraint challenge_real_source_policy_steps_v1;
alter table app.challenge_lobbies_v1 add constraint challenge_real_source_policy_metric_v1
 check (real_source_policy_version is null or
   app.challenge_real_health_policy_metric_v1(real_source_policy_version) = app.challenge_policy_v1(policy)->>'metric');
alter table app.challenge_real_health_admissions_v1 drop constraint challenge_real_health_admissions_v1_metric_check;
alter table app.challenge_real_health_admissions_v1 add constraint challenge_real_health_admission_metric_v1
 check (metric = app.challenge_real_health_policy_metric_v1(source_policy_version));

-- Comparable timed readiness is for one selected distance. Other metrics use
-- an internal zero key; their five-field wire contract still omits distance.
alter table app.challenge_real_health_readiness_v1 add column distance_mm bigint not null default 0;
alter table app.challenge_real_health_readiness_requests_v1 add column distance_mm bigint not null default 0;
alter table app.challenge_real_health_readiness_v1 drop constraint challenge_real_health_readiness_v1_pkey;
alter table app.challenge_real_health_readiness_v1 add primary key(actor_id,source_policy_version,distance_mm);
alter table app.challenge_real_health_readiness_v1 add constraint challenge_real_readiness_distance_v1
 check (case when source_policy_version='apple_workout_outdoor_timed_v1' then distance_mm between 1 and 1000000000 else distance_mm=0 end);
alter table app.challenge_real_health_readiness_requests_v1 add constraint challenge_real_readiness_request_distance_v1
 check (case when source_policy_version='apple_workout_outdoor_timed_v1' then distance_mm between 1 and 1000000000 else distance_mm=0 end);

create function app.challenge_real_health_has_readiness_v1(p_actor uuid,p_source text,p_distance bigint,p_now timestamptz)
returns boolean language sql stable set search_path='' as $$
 select app.challenge_real_health_policy_available_v1(p_source) and exists(
  select 1 from app.challenge_real_health_readiness_v1 r
  where r.actor_id=p_actor and r.source_policy_version=p_source and r.distance_mm=coalesce(p_distance,0)
    and r.observed_at between p_now-(case when p_source='apple_workout_outdoor_timed_v1' then interval '90 days' else interval '30 days' end) and p_now)
$$;

-- Preserve all session/key/counter/recovery locks from the proven boundary.
do $$
declare d text;
begin
 d:=pg_get_functiondef('public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean)'::regprocedure);
 if position('p_recovery_only boolean DEFAULT false)' in d)=0 then raise exception 'Unexpected readiness signature'; end if;
 d:=replace(d,'p_recovery_only boolean DEFAULT false)','p_recovery_only boolean DEFAULT false, p_distance_mm bigint DEFAULT NULL)');
 d:=replace(d,'or p_source_policy_version <> ''apple_watch_steps_v1''',
  'or not app.challenge_real_health_policy_available_v1(p_source_policy_version)
   or (p_source_policy_version=''apple_workout_outdoor_timed_v1'' and (p_distance_mm is null or p_distance_mm not between 1 and 1000000000))
   or (p_source_policy_version<>''apple_workout_outdoor_timed_v1'' and p_distance_mm is not null)');
 d:=replace(d,'saved.source_policy_version, saved.observed_at, saved.payload_digest,','saved.source_policy_version, saved.distance_mm, saved.observed_at, saved.payload_digest,');
 d:=replace(d,'(p_source_policy_version, p_observed_at, p_payload_digest,','(p_source_policy_version, coalesce(p_distance_mm,0), p_observed_at, p_payload_digest,');
 d:=replace(d,'readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)','readiness_v1(actor_id,source_policy_version,distance_mm,observed_at,recorded_at)');
 d:=replace(d,'values(p_actor_id,p_source_policy_version,p_observed_at,now_at)','values(p_actor_id,p_source_policy_version,coalesce(p_distance_mm,0),p_observed_at,now_at)');
 d:=replace(d,'on conflict(actor_id,source_policy_version)','on conflict(actor_id,source_policy_version,distance_mm)');
 d:=replace(d,'request_id, actor_id, source_policy_version, observed_at, payload_digest,','request_id, actor_id, source_policy_version, distance_mm, observed_at, payload_digest,');
 d:=replace(d,'p_request_id, p_actor_id, p_source_policy_version, p_observed_at, p_payload_digest,','p_request_id, p_actor_id, p_source_policy_version, coalesce(p_distance_mm,0), p_observed_at, p_payload_digest,');
 execute d;
end $$;
drop function public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean);
revoke all on function public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean,bigint) from public,anon,authenticated,service_role;
grant execute on function public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean,bigint) to service_role;

do $$
declare d text;
begin
 d:=pg_get_functiondef('app.challenge_real_health_payload_v1(jsonb)'::regprocedure);
 if position('expected := required || array[''value''];' in d)=0 then
  raise exception 'Unexpected real Health payload shape';
 end if;
 d:=replace(d,'expected := required || array[''value''];',
  'expected := required || array[''value''];
  if p->>''metric''=''timed'' then
   expected:=expected||array[''distance_mm''];
   if jsonb_typeof(p->''distance_mm'') is distinct from ''number''
      or p->>''distance_mm'' !~ ''^[1-9][0-9]*$''
      or (p->>''distance_mm'')::numeric > 1000000000 then
    raise exception ''challenge_invalid_real_health_request'' using errcode=''22023'';
   end if;
  end if;');
 d:=replace(d,'or p ->> ''contract_version'' <> ''1''',
  'or p->''contract_version'' is distinct from ''1''::jsonb');
 d:=replace(d,'or (p ->> ''revision'')::numeric > 2147483647',
  'or (p->>''agreement_version'')::numeric > 2147483647
     or (p ->> ''revision'')::numeric > 2147483647');
 d:=replace(d,'or p ->> ''source_policy_version'' <> ''apple_watch_steps_v1''',
  'or app.challenge_real_health_policy_metric_v1(p->>''source_policy_version'') is null
   or app.challenge_real_health_policy_metric_v1(p->>''source_policy_version'') is distinct from p->>''metric''');
 d:=replace(d,'or p ->> ''metric'' <> ''steps''',
  'or (p->>''metric''=''exercise'' and state_value=''value'')');
 execute d;
 d:=pg_get_functiondef('public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)'::regprocedure);
 if position('or lobby.policy not like ''%_steps_%''' in d)=0 then
  raise exception 'Unexpected real Health metric binding';
 end if;
 d:=replace(d,'or lobby.policy not like ''%_steps_%''',
  'or app.challenge_real_health_policy_metric_v1(lobby.real_source_policy_version) is distinct from app.challenge_policy_v1(lobby.policy)->>''metric''
     or (p_payload->>''metric''=''timed'' and (
       (p_payload->>''distance_mm'')::bigint is distinct from (lobby.config->>''distance_mm'')::bigint
       or (p_payload->>''distance_mm'')::bigint is distinct from (agreement.terms->''config''->>''distance_mm'')::bigint))');
 d:=replace(d,'''steps'', lobby.starts_at, lobby.ends_at, now_at','p_payload->>''metric'', lobby.starts_at, lobby.ends_at, now_at');
 execute d;
 d:=pg_get_functiondef('app.challenge_real_health_evaluate_v1(uuid,boolean)'::regprocedure);
 d:=replace(d,'when app.challenge_policy_v1(challenge.policy) ->> ''competition'' = ''leaderboard'' then ''unresolved''',
  'when app.challenge_policy_v1(challenge.policy)->>''competition''=''leaderboard'' or app.challenge_policy_v1(challenge.policy)->>''metric''=''exercise'' then ''unresolved''');
 d:=replace(d,'fact.value >= member.target',
  '(case when app.challenge_policy_v1(challenge.policy)->>''metric''=''timed'' then fact.value < member.target else fact.value >= member.target end)');
 execute d;
end $$;

-- A timed observation is an upper bound on the best elapsed time; a quantity
-- observation is a lower bound on the total. Either can establish a met goal.
-- Neither proves a missed goal or complete leaderboard. Existing allocation
-- and normalized tie rules remain in challenge_evaluate_policy_v1.

do $$
declare d text;
begin
 d:=pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'p_payload->>''source_policy_version''=''apple_watch_steps_v1''',
  'app.challenge_real_health_policy_available_v1(p_payload->>''source_policy_version'')');
 d:=replace(d,'real_source<>''apple_watch_steps_v1''','not app.challenge_real_health_policy_available_v1(real_source)');
 d:=replace(d,'pol->>''metric''<>''steps''',
  'pol->>''metric'' is distinct from app.challenge_real_health_policy_metric_v1(real_source)');
 d:=replace(d,
  'not exists(select 1 from app.challenge_real_health_readiness_v1 readiness where readiness.actor_id=a and readiness.source_policy_version=c.real_source_policy_version and readiness.observed_at between n-interval ''30 days'' and n)',
  'not app.challenge_real_health_has_readiness_v1(a,c.real_source_policy_version,(c.config->>''distance_mm'')::bigint,n)');
 execute d;
end $$;

-- Clone the deployed Personal term builder so its legacy clock/digest are not
-- reinterpreted; real Personal previews use the source clock before consent.
do $$
declare d text;
begin
 d:=pg_get_functiondef('app.challenge_personal_terms_v1(uuid,text,jsonb,bigint)'::regprocedure);
 d:=replace(d,'app.challenge_personal_terms_v1','app.challenge_real_health_personal_base_terms_v1');
 d:=replace(d,'app.challenge_now_v1()','app.challenge_real_health_now_v1()');
 execute d;
end $$;
create or replace function app.challenge_real_health_personal_terms_v1(p_actor uuid,p_policy text,p_config jsonb,p_target bigint,p_source_policy_version text)
returns jsonb language plpgsql set search_path='' as $$
declare terms jsonb;
begin
 if not app.challenge_real_health_policy_available_v1(p_source_policy_version)
    or app.challenge_real_health_policy_metric_v1(p_source_policy_version) is distinct from app.challenge_policy_v1(p_policy)->>'metric' then
  raise exception 'challenge_invalid_real_health_source' using errcode='22023';
 end if;
 terms:=app.challenge_real_health_personal_base_terms_v1(p_actor,p_policy,p_config,p_target);
 return terms||jsonb_build_object('source',p_source_policy_version,'source_policy_version',p_source_policy_version);
end $$;
do $$
declare d text;
begin
 d:=pg_get_functiondef('app.challenge_personal_commit_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'perform app.challenge_real_health_steps_policy_v1(source_version);',
  'if not app.challenge_real_health_policy_available_v1(source_version) then raise exception ''challenge_invalid_real_health_source'' using errcode=''22023''; end if;');
 d:=replace(d,
  'not exists(select 1 from app.challenge_real_health_readiness_v1 readiness
    where readiness.actor_id=a and readiness.source_policy_version=source_version
      and readiness.observed_at between n-interval ''30 days'' and n)',
  'not app.challenge_real_health_has_readiness_v1(a,source_version,(cfg->>''distance_mm'')::bigint,n)');
 execute d;
end $$;

revoke all on function app.challenge_real_health_policy_metric_v1(text),
 app.challenge_real_health_policy_available_v1(text),app.challenge_real_health_has_readiness_v1(uuid,text,bigint,timestamptz),
 app.challenge_real_health_personal_base_terms_v1(uuid,text,jsonb,bigint)
 from public,anon,authenticated,service_role;
