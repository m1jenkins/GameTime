-- P8 continuation: frozen source identities for the remaining matrix.  Exercise
-- is intentionally present but unavailable because the required causal origin
-- signal cannot be established by the native source API.
-- The first migration deliberately constrained this private registry to the
-- first steps source.  Expand the registry before inserting the recorded
-- unavailable/running identities; its entry guard still requires this local
-- migration write context.
select set_config('app.challenge_write_v1','on',true);
alter table app.challenge_real_health_source_policies_v1
  drop constraint challenge_real_health_source_policies_v1_version_check;
alter table app.challenge_real_health_source_policies_v1
  drop constraint challenge_real_health_source_policies_v1_metric_check;
alter table app.challenge_real_health_source_policies_v1
  add constraint challenge_real_health_source_policies_v1_version_check check (
    version in ('apple_watch_steps_v1','apple_watch_exercise_v1',
      'apple_workout_outdoor_distance_v1','apple_workout_outdoor_timed_v1')
  );
alter table app.challenge_real_health_source_policies_v1
  add constraint challenge_real_health_source_policies_v1_metric_check check (
    metric in ('steps','exercise','distance','timed')
  );
insert into app.challenge_real_health_source_policies_v1(version,metric,terms) values
 ('apple_watch_exercise_v1','exercise','{"version":"apple_watch_exercise_v1","availability":"unavailable_causal_origin"}'::jsonb),
 ('apple_workout_outdoor_distance_v1','distance','{"version":"apple_workout_outdoor_distance_v1","metric":"distance","unit":"whole_millimetres","provenance":"automatic_outdoor_workout_only","normalization":"floor"}'::jsonb),
 ('apple_workout_outdoor_timed_v1','timed','{"version":"apple_workout_outdoor_timed_v1","metric":"timed","unit":"whole_elapsed_seconds","provenance":"automatic_outdoor_workout_only","normalization":"ceil_elapsed"}'::jsonb);

-- Only the adopted steps policy is eligible for a new agreement in this
-- migration.  The other registered source identities are intentionally not a
-- back door into admission while their separate capability work remains open.
create function app.challenge_real_health_steps_policy_v1(p_source_policy_version text)
returns void language plpgsql stable set search_path='' as $$
begin
 if p_source_policy_version is distinct from 'apple_watch_steps_v1'
    or not exists(
      select 1 from app.challenge_real_health_source_policies_v1
      where version=p_source_policy_version and metric='steps'
    ) then
  raise exception 'challenge_invalid_real_health_source' using errcode='22023';
 end if;
end $$;

create function app.challenge_real_health_personal_terms_v1(
  p_actor uuid,p_policy text,p_config jsonb,p_target bigint,p_source_policy_version text
) returns jsonb language plpgsql set search_path='' as $$
declare pol jsonb:=app.challenge_policy_v1(p_policy); cfg jsonb;
begin
 perform app.challenge_real_health_steps_policy_v1(p_source_policy_version);
 if pol->>'mode' is distinct from 'personal' or p_target is null or p_target not between 1 and 1000000000 then
  raise exception 'challenge_invalid_target' using errcode='22023';
 end if;
 cfg:=app.challenge_window_v1(p_config,app.challenge_real_health_now_v1());
 if (pol->>'metric'='timed')<>(cfg ? 'distance_mm') then
  raise exception 'challenge_distance_required_for_timed' using errcode='22023';
 end if;
 if pol->>'metric' is distinct from 'steps' then
  raise exception 'challenge_invalid_real_health_source' using errcode='22023';
 end if;
 return jsonb_build_object('policy',p_policy,'source',p_source_policy_version,'source_policy_version',p_source_policy_version,
  'mode','personal','competition','goal','metric',pol->>'metric','unit',pol->>'unit','comparator',pol->>'comparator',
  'config',cfg,'version',1,'participants',jsonb_build_array(jsonb_build_object('actor_id',p_actor,'target',p_target)),
  'simulation','nonredeemable','review_hours',48,'resolution_hours',72,
  'missing_rule','exclude_refund_minimum','exit_rule','exclude_refund_minimum','minimum',1,
  'allocation_rule','return_qualifiers_split_misses_remainder_unallocated');
end $$;

-- The existing three-argument preview remains the historical, fictional
-- contract.  A caller must deliberately name the real source in this new
-- overload, so a saved fictional digest can never be reused as real consent.
create function public.challenge_personal_preview_v1(
  p_policy text,p_config jsonb,p_target bigint,p_source_policy_version text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; terms jsonb;
begin
 actor:=app.challenge_session_v1();
 terms:=app.challenge_real_health_personal_terms_v1(
   actor,p_policy,p_config,p_target,p_source_policy_version
 );
 return jsonb_build_object('terms',terms,'digest',encode(extensions.digest(terms::text,'sha256'),'hex'));
end $$;

-- Personal is committed in one consent operation.  This replacement keeps the
-- historical payload and terms path intact, and adds a strictly separate
-- source-bearing path whose agreement digest includes the chosen policy before
-- the consent row is written.
create or replace function app.challenge_personal_commit_v1(a uuid,p jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare
 terms jsonb; cfg jsonb; pol jsonb; cid uuid:=extensions.gen_random_uuid();
 c app.challenge_lobbies_v1; digest text; n timestamptz;
 source_version text:=p->>'source_policy_version'; real boolean:=p ? 'source_policy_version';
begin
 if real then
  if jsonb_typeof(p->'source_policy_version') is distinct from 'string' then
   raise exception 'challenge_invalid_real_health_source' using errcode='22023';
  end if;
  perform app.challenge_real_health_steps_policy_v1(source_version);
  perform set_config('app.challenge_real_health_command_v1','on',true);
  n:=app.challenge_real_health_now_v1();
 else
  perform set_config('app.challenge_real_health_command_v1','off',true);
  n:=app.challenge_now_v1();
 end if;
 perform app.challenge_admit_v1(a);
 if p-(case when real then array['op','policy','config','target','digest','consent','source_policy_version']
            else array['op','policy','config','target','digest','consent'] end)<>'{}'
    or not (p ?& array['op','policy','config','target','digest','consent'])
    or p->'consent' is distinct from 'true'::jsonb
    or jsonb_typeof(p->'target') is distinct from 'number'
    or p->>'target' !~ '^[0-9]+$'
 then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
 if real then
  terms:=app.challenge_real_health_personal_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint,source_version);
 else
  terms:=app.challenge_personal_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint);
 end if;
 digest:=encode(extensions.digest(terms::text,'sha256'),'hex');
 cfg:=terms->'config'; pol:=app.challenge_policy_v1(p->>'policy');
 if p->>'digest' is distinct from digest then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
 if real then
  if not exists(select 1 from app.challenge_real_health_readiness_v1 readiness
    where readiness.actor_id=a and readiness.source_policy_version=source_version
      and readiness.observed_at between n-interval '30 days' and n)
  then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 elsif not exists(select 1 from app.challenge_readiness_v1 readiness
   where readiness.actor_id=a and readiness.metric=pol->>'metric'
     and readiness.recorded_at between n-(case when pol->>'metric'='timed' then interval '90 days' else interval '30 days' end) and n)
 then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 perform id from public.profiles where id=a for update;
 perform app.challenge_session_v1();
 perform app.challenge_admit_v1(a);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_lobbies_v1(
   id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,
   agreement_version,real_source_policy_version
 ) values (
   cid,a,p->>'policy',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,
   'scheduled',n,1,1,1,case when real then source_version else null end
 ) returning * into c;
 perform app.challenge_slot_v1(a,c);
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
 values(cid,a,true,(p->>'target')::bigint);
 insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
 values(cid,a,'personal',pol->>'metric',c.starts_at,c.ends_at);
 insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
 values(cid,1,terms,n);
 insert into app.challenge_consents_v1 values(cid,1,a,digest,n);
 return jsonb_build_object('id',cid,'revision',c.revision,'status','scheduled');
end $$;

-- Real community publication is service-operated like the existing community
-- publisher.  It has a separate name and exact receipt shape, does not loosen
-- the historical fixture publisher, and creates an agreement before anyone can
-- join it.
create function public.challenge_publish_community_real_health_v1(
  p_request_id uuid,p_operator uuid,p_config jsonb,p_target bigint,
  p_minimum integer,p_capacity integer,p_source_policy_version text
) returns uuid language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare n timestamptz; cfg jsonb; cid uuid; terms jsonb; payload jsonb; saved app.challenge_requests_v1;
begin
 perform app.duel_require_service_v1();
 perform app.challenge_gate_v1();
 if p_request_id is null or p_operator is null or p_target is null or p_target not between 1 and 1000000000
    or p_minimum is null or p_capacity is null or p_minimum not between 2 and 250 or p_capacity not between p_minimum and 250
 then raise exception 'challenge_community_configuration_disabled' using errcode='42501'; end if;
 perform app.challenge_real_health_steps_policy_v1(p_source_policy_version);
 payload:=jsonb_build_object('op','publish_community_real_health','operator',p_operator,
   'config',p_config,'target',p_target,'minimum',p_minimum,'capacity',p_capacity,
   'source_policy_version',p_source_policy_version);
 perform app.challenge_lock_v1('actor',p_operator);
 if not exists(select 1 from public.profiles where id=p_operator and not app.challenge_actor_unavailable_v1(id)) then
  raise exception 'challenge_community_configuration_disabled' using errcode='42501';
 end if;
 perform id from public.profiles where id=p_operator for update;
 select * into saved from app.challenge_requests_v1 where actor_id=p_operator and request_id=p_request_id;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return (saved.response->>'id')::uuid;
 end if;
 if not exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and admission_enabled) then
  raise exception 'challenge_admission_paused' using errcode='42501';
 end if;
 n:=app.challenge_real_health_now_v1(); cfg:=app.challenge_window_v1(p_config,n);
 if cfg ? 'distance_mm' then raise exception 'challenge_invalid_distance' using errcode='22023'; end if;
 if exists(select 1 from app.challenge_lobbies_v1 where policy='community_steps_goal_v1' and status not in ('final','void','cancelled')) then
  raise exception 'challenge_one_community' using errcode='23505';
 end if;
 perform set_config('app.challenge_write_v1','on',true); cid:=extensions.gen_random_uuid();
 insert into app.challenge_lobbies_v1(
   id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,
   agreement_version,real_source_policy_version
 ) values (
   cid,p_operator,'community_steps_goal_v1',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,
   'published_open',n,p_minimum,p_capacity,1,p_source_policy_version
 );
 terms:=jsonb_build_object('policy','community_steps_goal_v1','source',p_source_policy_version,
  'source_policy_version',p_source_policy_version,'mode','community','competition','goal','metric','steps','unit','whole_counts',
  'config',cfg,'common_target',p_target,'minimum',p_minimum,'capacity',p_capacity,
  'simulation','nonredeemable','review_hours',48,'resolution_hours',72,
  'missing_rule','exclude_refund_minimum','exit_rule','exclude_refund_minimum',
  'allocation_rule','return_qualifiers_split_misses_remainder_unallocated');
 insert into app.challenge_agreements_v1 values(cid,1,terms,default,n);
 insert into app.challenge_community_publications_v1 values(cid,p_operator,'operator',n);
 insert into app.challenge_community_capacity_v1 values(cid,0);
 insert into app.challenge_requests_v1 values(p_operator,p_request_id,payload,jsonb_build_object('id',cid),n);
 return cid;
end $$;

-- Community discovery keeps its privacy, eligibility and bounded-read rules.
-- A real entry appears only under the separately enabled real admission gate;
-- fixture communities retain their original fixture/discovery gate.
create or replace function public.challenge_community_catalog_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.challenge_session_v1(); result jsonb;
begin
 if not app.challenge_quota_v1(actor,'discovery',30,interval '1 minute') then
  return app.challenge_quota_error_v1('challenge_rate_limited');
 end if;
 if app.challenge_actor_unavailable_v1(actor)
    or not exists(select 1 from app.challenge_age_v1 where actor_id=actor)
 then return '[]'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'terms',ag.terms,'digest',ag.digest,
   'server_time',case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end,
   'joined_count',counts->'joined','counts',counts)),'[]') into result
 from app.challenge_lobbies_v1 c
 join app.challenge_agreements_v1 ag on ag.challenge_id=c.id and ag.version=c.agreement_version
 cross join lateral(select app.challenge_community_counts_v1(c.id) counts) x
 left join app.challenge_runtime_v1 legacy on legacy.singleton
 left join app.challenge_real_health_runtime_v1 real on real.singleton
 where c.policy='community_steps_goal_v1' and c.status='published_open'
   and (case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end)<c.starts_at
   and ((c.real_source_policy_version is null and legacy.discovery and legacy.fixtures and app.challenge_community_eligible_v1(actor))
     or (c.real_source_policy_version='apple_watch_steps_v1' and real.admission_enabled));
 perform app.challenge_session_v1(); return result;
end $$;

-- The public join retains its actor/challenge locks, request recovery, private
-- receipt masking, capacity reservation and safe exit behavior.  Source-aware
-- readiness is checked only after the source-bearing agreement has been read.
create or replace function public.challenge_join_community_v1(p_request_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.challenge_mutation_session_v1(); c app.challenge_lobbies_v1;
 agreement app.challenge_agreements_v1; saved app.challenge_requests_v1; response jsonb;
 n timestamptz; source_version text;
begin
 select * into saved from app.challenge_requests_v1 where actor_id=actor and request_id=p_request_id;
 if found then
  if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return app.challenge_private_receipt_v1(saved.response);
 end if;
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object'
    or p_payload-array['op','id','digest','consent']<>'{}'
    or not(p_payload ?& array['op','id','digest','consent']) or p_payload->>'op'<>'join_community'
    or p_payload->'consent' is distinct from 'true'::jsonb
 then raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 select real_source_policy_version into source_version from app.challenge_lobbies_v1 where id=(p_payload->>'id')::uuid;
 perform set_config('app.challenge_real_health_command_v1',case when source_version is null then 'off' else 'on' end,true);
 perform app.challenge_lock_v1('challenge',(p_payload->>'id')::uuid);
 perform id from public.profiles where id=actor for update;
 perform app.challenge_session_v1();
 perform app.challenge_admit_v1(actor);
 select * into c from app.challenge_lobbies_v1 where id=(p_payload->>'id')::uuid for update;
 n:=case when c.real_source_policy_version is null then app.challenge_now_v1() else app.challenge_real_health_now_v1() end;
 select * into agreement from app.challenge_agreements_v1 where challenge_id=c.id and version=c.agreement_version;
 if c.real_source_policy_version is null then
  if not exists(select 1 from app.challenge_runtime_v1 where singleton and discovery and fixtures) then
   raise exception 'challenge_discovery_disabled' using errcode='42501';
  end if;
 elsif c.real_source_policy_version='apple_watch_steps_v1' then
  if not exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and admission_enabled) then
   raise exception 'challenge_admission_paused' using errcode='42501';
  end if;
 else
  raise exception 'challenge_join_closed' using errcode='55000';
 end if;
 if c.policy is distinct from 'community_steps_goal_v1' or c.status<>'published_open' or n>=c.starts_at
    or p_payload->>'digest' is distinct from agreement.digest
    or exists(select 1 from app.challenge_members_v1 where challenge_id=c.id and actor_id=actor)
 then raise exception 'challenge_join_closed' using errcode='55000'; end if;
 if (select reserved from app.challenge_community_capacity_v1 where challenge_id=c.id for update)>=c.capacity then
  raise exception 'challenge_join_closed' using errcode='P0001';
 end if;
 if c.real_source_policy_version is null then
  if not exists(select 1 from app.challenge_readiness_v1 readiness where readiness.actor_id=actor and readiness.metric='steps'
    and readiness.recorded_at between n-interval '30 days' and n) then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 else
  if not exists(select 1 from app.challenge_real_health_readiness_v1 readiness where readiness.actor_id=actor
    and readiness.source_policy_version=c.real_source_policy_version
    and readiness.observed_at between n-interval '30 days' and n) then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 end if;
 perform app.challenge_slot_v1(actor,c);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
 values(c.id,actor,true,(agreement.terms->>'common_target')::bigint);
 insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
 values(c.id,actor,'community','steps',c.starts_at,c.ends_at);
 insert into app.challenge_consents_v1 values(c.id,c.agreement_version,actor,agreement.digest,n);
 update app.challenge_lobbies_v1 set revision=revision+1 where id=c.id;
 response:=jsonb_build_object('id',c.id,'status','published_open','revision_scope','member',
   'revision',app.challenge_community_revision_v1(c.id,actor));
 insert into app.challenge_requests_v1 values(actor,p_request_id,p_payload,response,n);
 return app.challenge_private_receipt_v1(response);
end $$;

revoke all on function app.challenge_real_health_steps_policy_v1(text),
  app.challenge_real_health_personal_terms_v1(uuid,text,jsonb,bigint,text),
  app.challenge_personal_commit_v1(uuid,jsonb),
  public.challenge_personal_preview_v1(text,jsonb,bigint,text)
from public,anon,authenticated,service_role;
grant execute on function public.challenge_personal_preview_v1(text,jsonb,bigint,text) to authenticated;
revoke all on function public.challenge_publish_community_real_health_v1(uuid,uuid,jsonb,bigint,integer,integer,text)
from public,anon,authenticated,service_role;
grant execute on function public.challenge_publish_community_real_health_v1(uuid,uuid,jsonb,bigint,integer,integer,text) to service_role;
revoke all on function public.challenge_join_community_v1(uuid,jsonb),public.challenge_community_catalog_v1() from public,anon,authenticated,service_role;
grant execute on function public.challenge_join_community_v1(uuid,jsonb),public.challenge_community_catalog_v1() to authenticated;
