-- Separate, default-off W1/W2 fictional local contracts. No legacy policy or slot changes.
create table app.weekly_runtime (
 singleton boolean primary key default true check(singleton), enabled boolean not null default false,
 fixture_enabled boolean not null default false, worker_enabled boolean not null default false,
 actor_ids uuid[] not null default '{}'
);
insert into app.weekly_runtime default values;
create table app.weekly_pauses (actor_id uuid primary key references public.profiles(id), paused boolean not null);
create table app.weekly_agreements (
 id uuid primary key default extensions.gen_random_uuid(), mode text not null check(mode in ('friend','community')),
 creator_id uuid references public.profiles(id), terms jsonb not null,
 terms_digest text generated always as (encode(extensions.digest(terms::text,'sha256'),'hex')) stored,
 starts_at timestamptz not null, ends_at timestamptz not null, join_by timestamptz not null,
 capacity integer not null check(capacity between 2 and 30),
 status text not null default 'invited' check(status in ('invited','scheduled','active','review','closed','final')),
 version bigint not null default 1, created_at timestamptz not null,
 check(starts_at<ends_at and join_by<=starts_at), check((mode='friend')=(creator_id is not null))
);
create table app.weekly_participants (
 challenge_id uuid not null references app.weekly_agreements(id), actor_id uuid not null references public.profiles(id),
 target_steps integer not null check(target_steps between 1 and 1000000), accepted_at timestamptz,
 consent_digest text, declined_at timestamptz, exited_at timestamptz,
 primary key(challenge_id,actor_id), check((accepted_at is null)=(consent_digest is null))
);
create index weekly_participants_actor_idx on app.weekly_participants(actor_id);
create table app.weekly_requests (
 actor_id uuid not null references public.profiles(id), request_id uuid not null, payload jsonb not null,
 response_id uuid not null, recorded_at timestamptz not null, primary key(actor_id,request_id)
);
create table app.weekly_revisions (
 challenge_id uuid not null references app.weekly_agreements(id), actor_id uuid not null references public.profiles(id),
 day date not null, revision integer not null check(revision between 1 and 128), source_request uuid not null unique,
 received_at timestamptz not null, document jsonb not null, primary key(challenge_id,actor_id,day,revision)
);
create index weekly_revisions_actor_idx on app.weekly_revisions(actor_id);
create table app.weekly_progress (
 id uuid primary key, challenge_id uuid not null references app.weekly_agreements(id),
 actor_id uuid not null references public.profiles(id), day date not null, steps integer not null check(steps between 0 and 1000000),
 recorded_at timestamptz not null
);
create index weekly_progress_challenge_actor_idx on app.weekly_progress(challenge_id,actor_id);
create index weekly_progress_actor_idx on app.weekly_progress(actor_id);
create table app.weekly_notices (
 challenge_id uuid not null references app.weekly_agreements(id), revision integer not null,
 qualifications jsonb not null, source_count integer not null, recorded_at timestamptz not null, file_by timestamptz not null, resolve_by timestamptz not null,
 primary key(challenge_id,revision), check(file_by=recorded_at+interval '48 hours'), check(resolve_by=file_by+interval '72 hours')
);
create table app.weekly_cases (
 id uuid primary key, challenge_id uuid not null, actor_id uuid not null references public.profiles(id),
 notice_revision integer not null, reason text not null check(reason in ('wrong_total','source_problem','wrong_result')),
 recorded_at timestamptz not null, unique(challenge_id,actor_id,notice_revision),
 foreign key(challenge_id,notice_revision) references app.weekly_notices(challenge_id,revision)
);
create index weekly_cases_actor_idx on app.weekly_cases(actor_id);
create table app.weekly_resolutions (
 case_id uuid primary key references app.weekly_cases(id), decision text not null check(decision in ('upheld','void')),
 recorded_at timestamptz not null
);
create table app.weekly_exits (
 id uuid primary key, challenge_id uuid not null references app.weekly_agreements(id), actor_id uuid not null references public.profiles(id),
 kind text not null check(kind in ('decline','cancel','withdrawal','injury','account_deleted')),
 recorded_at timestamptz not null, unique(challenge_id,actor_id)
);
create index weekly_exits_actor_idx on app.weekly_exits(actor_id);
create table app.weekly_results (
 challenge_id uuid primary key references app.weekly_agreements(id), qualifications jsonb not null,
 reason text not null, input_version bigint not null, recorded_at timestamptz not null
);
create table app.weekly_allocations (
 challenge_id uuid primary key references app.weekly_results(challenge_id), allocations jsonb not null,
 total_entry_cents integer not null, unallocated_cents integer not null check(unallocated_cents>=0),
 recorded_at timestamptz not null, mode text not null default 'fictional_nonredeemable' check(mode='fictional_nonredeemable'),
 redeemable boolean not null default false check(not redeemable)
);
create table app.weekly_support (
 id uuid primary key, challenge_id uuid not null references app.weekly_agreements(id), actor_id uuid not null references public.profiles(id),
 reason text not null check(reason in ('correction','privacy','unwanted_contact','exit_help')), recorded_at timestamptz not null
);
create index weekly_support_challenge_actor_idx on app.weekly_support(challenge_id,actor_id);
create index weekly_support_actor_idx on app.weekly_support(actor_id);

create table app.weekly_pilot_consents (actor_id uuid primary key references public.profiles(id), enabled boolean not null);
create table app.weekly_pilot_events (
 id uuid primary key, actor_id uuid not null references public.profiles(id), challenge_id uuid references app.weekly_agreements(id),
 event text not null check(event in ('rule_preview','consent','invitation','cohort_join','progress_refresh','result_view','review','withdrawal','next_week','sharing')),
 phase text not null check(phase in ('intent','exposure','outcome')), policy_version text not null default 'weekly-pilot-fixture-v1' check(policy_version='weekly-pilot-fixture-v1'), recorded_at timestamptz not null
);
create index weekly_pilot_events_actor_idx on app.weekly_pilot_events(actor_id);
create index weekly_pilot_events_challenge_idx on app.weekly_pilot_events(challenge_id);
create function app.weekly_guard_v1() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
   or coalesce(current_setting('app.weekly_write_v1',true),'')<>'on' then
  raise exception 'weekly_rpc_required' using errcode='42501'; end if;
 if tg_op='INSERT' then return new; end if;
 if tg_op='DELETE' and tg_table_name='weekly_pilot_events' then return old; end if;
 if tg_op='UPDATE' then
  if tg_table_name='weekly_requests' and to_jsonb(old)->'payload'->>'op'='pilot_event'
   and to_jsonb(new)->'payload'=jsonb_build_object('op','pilot_erased')
   and (to_jsonb(new)-'payload')=(to_jsonb(old)-'payload') then return new; end if;
  if tg_table_name in ('weekly_runtime','weekly_pauses','weekly_pilot_consents') then return new; end if;
  if tg_table_name='weekly_agreements' and (to_jsonb(new)-array['status','version','terms_digest'])=(to_jsonb(old)-array['status','version','terms_digest'])
    and (to_jsonb(new)->>'version')::bigint>(to_jsonb(old)->>'version')::bigint and to_jsonb(old)->>'status'<>'final' then return new; end if;
  if tg_table_name='weekly_participants' and (to_jsonb(new)-array['accepted_at','consent_digest','declined_at','exited_at'])=(to_jsonb(old)-array['accepted_at','consent_digest','declined_at','exited_at'])
    and (to_jsonb(old)->>'accepted_at' is null or (to_jsonb(new)->'accepted_at',to_jsonb(new)->'consent_digest') is not distinct from (to_jsonb(old)->'accepted_at',to_jsonb(old)->'consent_digest'))
    and (to_jsonb(old)->>'declined_at' is null or to_jsonb(new)->'declined_at'=to_jsonb(old)->'declined_at')
    and (to_jsonb(old)->>'exited_at' is null or to_jsonb(new)->'exited_at'=to_jsonb(old)->'exited_at') then return new; end if;
 end if;
 raise exception 'weekly_immutable' using errcode='23001';
end; $$;
do $$ declare t text; begin
 foreach t in array array['runtime','pauses','agreements','participants','requests','revisions','progress','notices','cases','resolutions','exits','results','allocations','support','pilot_consents','pilot_events'] loop
  execute format('alter table app.weekly_%I enable row level security',t);
  execute format('revoke all on app.weekly_%I from public,anon,authenticated,service_role',t);
  execute format('create trigger weekly_guard before insert or update or delete on app.weekly_%I for each row execute function app.weekly_guard_v1()',t);
  execute format('create trigger weekly_no_truncate before truncate on app.weekly_%I for each statement execute function app.weekly_guard_v1()',t);
 end loop;
end; $$;

create function app.weekly_require_session_v1() returns void language plpgsql set search_path='' as $$
begin
 if current_setting('role')<>'authenticated' or not app.is_active_actor(auth.uid())
  or not exists(select 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=auth.uid()
   and (not_after is null or not_after>clock_timestamp())) then raise exception 'weekly_session_required' using errcode='42501'; end if;
end; $$;
create function app.weekly_session_v1(p_actors uuid[] default '{}') returns uuid
language plpgsql set search_path='' as $$
declare a uuid:=auth.uid(); begin
 if current_setting('role')<>'authenticated' or a is null then raise exception 'weekly_session_required' using errcode='42501'; end if;
 -- Profile -> session -> runtime -> agreement; block/delete share profile locks.
 perform id from public.profiles where id=any(array_append(p_actors,a)) order by id for update;
 if not app.is_active_actor(a) then raise exception 'weekly_session_required' using errcode='42501'; end if;
 perform 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=a
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'weekly_session_required' using errcode='42501'; end if;
 perform app.weekly_require_session_v1(); return a;
end; $$;
create function app.weekly_recover_v1(a uuid,r uuid,p jsonb) returns uuid language plpgsql set search_path='' as $$
declare v app.weekly_requests; begin
 if r is null then raise exception 'weekly_request_required' using errcode='22023'; end if;
 select * into v from app.weekly_requests where actor_id=a and request_id=r;
 if found then
  if v.payload->>'op' in ('retired','pilot_erased') then raise exception 'weekly_request_retired' using errcode='55000'; end if;
  if v.payload is distinct from p then raise exception 'weekly_request_conflict' using errcode='22023'; end if;
  return v.response_id;
 end if;
 return null;
end; $$;
create function app.weekly_admit_v1(a uuid) returns void language plpgsql set search_path='' as $$
begin
 perform 1 from app.weekly_runtime where singleton and enabled and a=any(actor_ids) for share;
 if not found or exists(select 1 from app.weekly_pauses where actor_id=a and paused) then
  raise exception 'weekly_admission_closed' using errcode='42501'; end if;
 perform app.weekly_require_session_v1();
end; $$;
create function app.weekly_slot_v1(a uuid,s timestamptz,e timestamptz) returns void language plpgsql set search_path='' as $$
begin
 if exists(select 1 from app.weekly_participants p join app.weekly_agreements c on c.id=p.challenge_id
  where p.actor_id=a and p.accepted_at is not null and p.exited_at is null and c.status not in ('closed','final')
  and tstzrange(c.starts_at,c.ends_at,'[)') && tstzrange(s,e,'[)')) then
  raise exception 'weekly_overlap' using errcode='23505'; end if;
 -- All unsettled accepted entries count, including safe exits pending recorded allocation.
 if (select count(*) from app.weekly_participants p where p.actor_id=a and p.accepted_at is not null
  and not exists(select 1 from app.weekly_allocations x where x.challenge_id=p.challenge_id))>=3 then
  raise exception 'weekly_pending_limit' using errcode='23505'; end if;
end; $$;
create function public.set_weekly_runtime_v1(p_enabled boolean,p_fixture_enabled boolean,p_worker_enabled boolean,p_actor_ids uuid[])
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1();
 if p_enabled is null or p_fixture_enabled is null or p_worker_enabled is null or p_actor_ids is null
   or cardinality(p_actor_ids)>100 or array_position(p_actor_ids,null) is not null then raise exception 'weekly_invalid_runtime' using errcode='22023'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 update app.weekly_runtime set enabled=p_enabled,fixture_enabled=p_fixture_enabled,worker_enabled=p_worker_enabled,actor_ids=p_actor_ids where singleton;
 return p_enabled;
end; $$;
create function app.weekly_canonical_v1(j jsonb) returns text language plpgsql immutable set search_path='' as $$
declare v text; begin
 if jsonb_typeof(j)='object' then select '{'||coalesce(string_agg(to_jsonb(key)::text||':'||app.weekly_canonical_v1(value),',' order by key collate "C"),'')||'}' into v from jsonb_each(j); return v; end if;
 if jsonb_typeof(j)='array' then select '['||coalesce(string_agg(app.weekly_canonical_v1(value),',' order by ord),'')||']' into v from jsonb_array_elements(j) with ordinality as x(value,ord); return v; end if;
 return j::text;
end; $$;
create function app.weekly_policy_v1() returns jsonb language sql immutable set search_path='' as $$
select '{"version":"weekly-friend-steps-fixture-v1","source":"fixture_weekly_steps_v1","metric":"steps","unit":"whole_steps","mode":"fictional_nonredeemable","minParticipants":2,"maxParticipants":5,"participantCapacityAssumption":"includes_creator_unconfirmed","minimumTarget":1,"maximumTarget":1000000,"maximumDailySteps":1000000,"maximumRevisionsPerDay":128,"uploadHoursAfterEnd":24,"correctionHoursAfterEnd":48,"simulatedCentsEach":2000,"feeCentsEach":0,"outcomeRule":"individual_cumulative_gte_all_may_qualify","unresolvedRule":"group_void_no_simulated_loss","safeExitRule":"group_void_no_simulated_loss","finalityRule":"separate_notices_and_full_review_required"}'::jsonb
$$;
create function app.weekly_terms_v1(p_participants jsonb,p_week_start date,p_timezone text,p_creator uuid,p_created timestamptz)
returns jsonb language plpgsql set search_path='' set timezone='UTC' as $$
declare s timestamptz; e timestamptz; days jsonb; people jsonb;
begin
 if p_created is null or not isfinite(p_created) or p_week_start is null or not isfinite(p_week_start)
  or extract(isodow from p_week_start)<>1 or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone)
  or jsonb_typeof(p_participants) is distinct from 'array' or jsonb_array_length(p_participants) not between 2 and 5 then
  raise exception 'weekly_invalid_terms' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_participants) x where jsonb_typeof(x) is distinct from 'object'
  or x-array['actor_id','target_steps']<>'{}'::jsonb or (x->>'actor_id') is null
  or jsonb_typeof(x->'target_steps') is distinct from 'number' or (x->>'target_steps') !~ '^[0-9]+$'
  or (x->>'target_steps')::numeric not between 1 and 1000000)
  or (select count(distinct (x->>'actor_id')::uuid) from jsonb_array_elements(p_participants) x)<>jsonb_array_length(p_participants)
  or not exists(select 1 from jsonb_array_elements(p_participants) x where (x->>'actor_id')::uuid=p_creator) then
  raise exception 'weekly_invalid_participants' using errcode='22023'; end if;
 s:=p_week_start::timestamp at time zone p_timezone; e:=(p_week_start+7)::timestamp at time zone p_timezone;
 select jsonb_agg(jsonb_build_object('date',(p_week_start+n)::text,'startsAt',(p_week_start+n)::timestamp at time zone p_timezone,
  'endsAt',(p_week_start+n+1)::timestamp at time zone p_timezone) order by n) into days from generate_series(0,6) n;
 select jsonb_agg(jsonb_build_object('participantId',(x->>'actor_id')::uuid,'targetSteps',(x->>'target_steps')::integer) order by (x->>'actor_id')::uuid)
  into people from jsonb_array_elements(p_participants) x;
 return jsonb_build_object('agreementVersion',1,'policy',app.weekly_policy_v1(),'creatorId',p_creator,'createdAt',p_created,
  'timezone',p_timezone,'startsAt',s,'endsAt',e,'uploadClosesAt',e+interval '24 hours','correctionsCloseAt',e+interval '48 hours',
  'days',days,'participants',people,'lifecycle',jsonb_build_object('noticeBy',e+interval '72 hours','filingWindowHours',48,
  'resolutionWindowHours',72,'finalityBy',e+interval '216 hours','simulationEntryCents',2000,'feeCents',0,
  'exitPolicy','void_friend_refund_community_v1','retentionPolicy','private_fictional_receipts_v1'));
end; $$;
create function public.preview_weekly_friend_v1(p_participants jsonb,p_week_start date,p_timezone text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; t jsonb; begin
 a:=app.weekly_session_v1(); t:=app.weekly_terms_v1(p_participants,p_week_start,p_timezone,a,clock_timestamp());
 return jsonb_build_object('terms',t,'terms_digest',encode(extensions.digest(t::text,'sha256'),'hex'));
end; $$;
create function app.weekly_create_at_v1(p_request_id uuid,p_terms jsonb,p_expected_terms_digest text,p_consent boolean,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; ids uuid[]; people jsonb; t jsonb; p jsonb; recovered uuid; v_id uuid; n timestamptz;
 s timestamptz; e timestamptz; x uuid;
begin
 -- Bound untrusted roster/terms before acquiring ANY referenced profile lock.
 if jsonb_typeof(p_terms) is distinct from 'object' or octet_length(p_terms::text)>32768
  or jsonb_typeof(p_terms->'participants') is distinct from 'array'
  or jsonb_array_length(p_terms->'participants') not between 2 and 5 then
  raise exception 'weekly_invalid_terms' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_terms->'participants') item where jsonb_typeof(item) is distinct from 'object'
  or item->>'participantId' is null or item->>'participantId' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
  raise exception 'weekly_invalid_participants' using errcode='22023'; end if;
 select array_agg((v->>'participantId')::uuid),jsonb_agg(jsonb_build_object('actor_id',v->'participantId','target_steps',v->'targetSteps')) into ids,people from jsonb_array_elements(p_terms->'participants') v;
 a:=app.weekly_session_v1(ids);
 p:=jsonb_build_object('op','create','terms',p_terms,'digest',p_expected_terms_digest,'consent',p_consent);
 recovered:=app.weekly_recover_v1(a,p_request_id,p); if recovered is not null then return recovered; end if;
 perform app.weekly_admit_v1(a); n:=coalesce(p_now,clock_timestamp());
 t:=app.weekly_terms_v1(people,(p_terms->'days'->0->>'date')::date,p_terms->>'timezone',a,(p_terms->>'createdAt')::timestamptz);
 s:=(t->>'startsAt')::timestamptz; e:=(t->>'endsAt')::timestamptz;
 if p_consent is distinct from true or t is distinct from p_terms
  or p_expected_terms_digest is distinct from encode(extensions.digest(t::text,'sha256'),'hex')
  or not isfinite(n) or (t->>'createdAt')::timestamptz>n or (t->>'createdAt')::timestamptz<n-interval '24 hours'
  or s<=n+interval '1 hour' or s>n+interval '28 days' then raise exception 'weekly_consent_mismatch' using errcode='22023'; end if;
 foreach x in array ids loop
  if not app.is_active_actor(x) or (x<>a and (not app.is_friend(a,x) or app.is_blocked_either_way(a,x)))
   or exists(select 1 from unnest(ids) b where b<>x and app.is_blocked_either_way(x,b)) then raise exception 'weekly_friend_unavailable' using errcode='42501'; end if;
 end loop;
 perform app.weekly_slot_v1(a,s,e);
 -- Outstanding invitations are bounded too, preventing target-bound invitation spam.
 if (select count(*) from app.weekly_participants q join app.weekly_agreements c on c.id=q.challenge_id
  where q.actor_id=any(ids) and q.accepted_at is null and c.status='invited' and c.join_by>n)>=10 then raise exception 'weekly_invitation_limit' using errcode='23505'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_agreements(mode,creator_id,terms,starts_at,ends_at,join_by,capacity,created_at)
  values('friend',a,t,s,e,s-interval '1 hour',cardinality(ids),n) returning id into v_id;
 insert into app.weekly_participants(challenge_id,actor_id,target_steps,accepted_at,consent_digest)
  select v_id,(v->>'participantId')::uuid,(v->>'targetSteps')::integer,case when (v->>'participantId')::uuid=a then n end,
   case when (v->>'participantId')::uuid=a then p_expected_terms_digest end from jsonb_array_elements(t->'participants') v;
 insert into app.weekly_requests values(a,p_request_id,p,v_id,n); return v_id;
end; $$;
create function public.create_weekly_friend_v1(p_request_id uuid,p_terms jsonb,p_expected_terms_digest text,p_consent boolean)
returns uuid language sql security definer set search_path='' as $$select app.weekly_create_at_v1(p_request_id,p_terms,p_expected_terms_digest,p_consent)$$;

-- Official local cohort curation is service-owned, never participant-created.
create function app.weekly_curate_at_v1(p_id uuid,p_week_start date,p_timezone text,p_common_target integer,p_capacity integer,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare t jsonb; n timestamptz:=coalesce(p_now,clock_timestamp()); c app.weekly_agreements; s timestamptz; e timestamptz;
begin
 perform app.duel_require_service_v1();
 if p_id is null or p_capacity is null or p_capacity not between 2 and 30 or p_common_target is null or p_common_target not between 1 and 1000000 then
  raise exception 'weekly_invalid_cohort' using errcode='22023'; end if;
 -- Reuse calendar generation only; community is a distinct versioned contract.
 t:=app.weekly_terms_v1(jsonb_build_array(jsonb_build_object('actor_id','00000000-0000-0000-0000-000000000001','target_steps',p_common_target),
  jsonb_build_object('actor_id','00000000-0000-0000-0000-000000000002','target_steps',p_common_target)),p_week_start,p_timezone,'00000000-0000-0000-0000-000000000001',n);
 t:=(t-array['creatorId','participants'])||jsonb_build_object('policyVersion','weekly-community-steps-fixture-v1','commonTargetSteps',p_common_target,
  'capacity',p_capacity,'minimumParticipants',2,'targetStatus','fixture_not_launch_target','projection','counts_and_own_only');
 t:=jsonb_set(t,'{policy}',(t->'policy')||'{"version":"weekly-community-steps-fixture-v1","maxParticipants":30,"unresolvedRule":"refund_uncertain_individual","safeExitRule":"refund_withdrawn_individual"}'::jsonb);
 s:=(t->>'startsAt')::timestamptz; e:=(t->>'endsAt')::timestamptz;
 select * into c from app.weekly_agreements where id=p_id;
 if found then
  if c.mode<>'community' or (c.terms-'createdAt') is distinct from (t-'createdAt') then raise exception 'weekly_cohort_conflict' using errcode='22023'; end if;
  return p_id;
 end if;
 if not isfinite(n) or s<=n+interval '1 hour' or s>n+interval '28 days' then raise exception 'weekly_cohort_window' using errcode='22023'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_agreements(id,mode,terms,starts_at,ends_at,join_by,capacity,created_at)
 values(p_id,'community',t,s,e,s-interval '1 hour',p_capacity,n); return p_id;
end; $$;
create function public.curate_weekly_cohort_v1(p_id uuid,p_week_start date,p_timezone text,p_common_target integer,p_capacity integer)
returns uuid language sql security definer set search_path='' as $$select app.weekly_curate_at_v1(p_id,p_week_start,p_timezone,p_common_target,p_capacity)$$;

create function app.weekly_join_at_v1(p_request_id uuid,p_challenge_id uuid,p_expected_terms_digest text,p_consent boolean,p_mode text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; ids uuid[]; c app.weekly_agreements; n timestamptz; p jsonb; v uuid; count_accepted integer;
begin
 select array_agg(actor_id) into ids from app.weekly_participants where challenge_id=p_challenge_id
  and exists(select 1 from app.weekly_agreements where id=p_challenge_id and mode='friend');
 a:=app.weekly_session_v1(coalesce(ids,'{}'));
 p:=jsonb_build_object('op','join','id',p_challenge_id,'digest',p_expected_terms_digest,'consent',p_consent,'mode',p_mode);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 perform app.weekly_admit_v1(a);
 select * into c from app.weekly_agreements where id=p_challenge_id for update;
 perform app.weekly_require_session_v1(); n:=coalesce(p_now,clock_timestamp());
 if not found or c.mode<>p_mode or c.status not in ('invited','scheduled') or not isfinite(n) or n>=c.join_by
  or n<c.created_at then raise exception 'weekly_join_unavailable' using errcode='55000'; end if;
 if p_consent is distinct from true or p_expected_terms_digest is distinct from c.terms_digest then raise exception 'weekly_consent_mismatch' using errcode='22023'; end if;
 if exists(select 1 from app.weekly_participants where challenge_id=c.id and actor_id=a and (accepted_at is not null or declined_at is not null or exited_at is not null)) then
  raise exception 'weekly_already_responded' using errcode='55000'; end if;
 if c.mode='friend' then
  if not a=any(ids) or exists(select 1 from unnest(ids) x where not app.is_active_actor(x)
   or (x<>c.creator_id and not app.is_friend(c.creator_id,x))
   or exists(select 1 from unnest(ids) y where y<>x and app.is_blocked_either_way(x,y))) then
   raise exception 'weekly_friend_unavailable' using errcode='42501'; end if;
 end if;
 select count(*) into count_accepted from app.weekly_participants where challenge_id=c.id and accepted_at is not null;
 if count_accepted>=c.capacity then raise exception 'weekly_capacity' using errcode='23505'; end if;
 perform app.weekly_slot_v1(a,c.starts_at,c.ends_at);
 perform set_config('app.weekly_write_v1','on',true);
 if c.mode='community' then insert into app.weekly_participants(challenge_id,actor_id,target_steps,accepted_at,consent_digest)
  values(c.id,a,(c.terms->>'commonTargetSteps')::integer,n,c.terms_digest);
 else update app.weekly_participants set accepted_at=n,consent_digest=c.terms_digest where challenge_id=c.id and actor_id=a; end if;
 update app.weekly_agreements set version=version+1,status=case when count_accepted+1>=case when mode='community' then 2 else capacity end then 'scheduled' else status end where id=c.id;
 insert into app.weekly_requests values(a,p_request_id,p,c.id,n); return c.id;
end; $$;
create function public.accept_weekly_v1(p_request_id uuid,p_challenge_id uuid,p_expected_terms_digest text,p_consent boolean)
returns uuid language sql security definer set search_path='' as $$select app.weekly_join_at_v1(p_request_id,p_challenge_id,p_expected_terms_digest,p_consent,'friend')$$;
create function public.join_weekly_cohort_v1(p_request_id uuid,p_challenge_id uuid,p_expected_terms_digest text,p_consent boolean)
returns uuid language sql security definer set search_path='' as $$select app.weekly_join_at_v1(p_request_id,p_challenge_id,p_expected_terms_digest,p_consent,'community')$$;

create function app.weekly_exit_at_v1(p_request_id uuid,p_challenge_id uuid,p_kind text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; c app.weekly_agreements; q app.weekly_participants; p jsonb; v uuid; n timestamptz;
begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','exit','id',p_challenge_id,'kind',p_kind);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 select * into c from app.weekly_agreements where id=p_challenge_id for update;
 select * into q from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a;
 perform app.weekly_require_session_v1(); n:=coalesce(p_now,clock_timestamp());
 if c.id is null or q.actor_id is null or c.status='final' or q.exited_at is not null then raise exception 'weekly_exit_unavailable' using errcode='55000'; end if;
 if p_kind is null or p_kind not in ('decline','cancel','withdrawal','injury') or not isfinite(n) or n<c.created_at
  or (p_kind='decline' and (q.accepted_at is not null or n>=c.join_by))
  or (p_kind='cancel' and (c.creator_id is distinct from a or n>=c.starts_at))
  or (p_kind in ('withdrawal','injury') and q.accepted_at is null) then raise exception 'weekly_invalid_exit' using errcode='22023'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_exits values(p_request_id,c.id,a,p_kind,n);
 update app.weekly_participants set exited_at=n,declined_at=case when p_kind='decline' then n else declined_at end where challenge_id=c.id and actor_id=a;
 update app.weekly_agreements set status=case when mode='friend' then 'closed' else status end,version=version+1 where id=c.id;
 insert into app.weekly_requests values(a,p_request_id,p,c.id,n); return c.id;
end; $$;
create function public.exit_weekly_v1(p_request_id uuid,p_challenge_id uuid,p_kind text)
returns uuid language sql security definer set search_path='' as $$select app.weekly_exit_at_v1(p_request_id,p_challenge_id,p_kind)$$;
create function public.set_weekly_entry_pause_v1(p_request_id uuid,p_paused boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','pause','paused',p_paused);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if p_paused is null then raise exception 'weekly_pause_required' using errcode='22023'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_pauses values(a,p_paused) on conflict(actor_id) do update set paused=excluded.paused;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;

-- Client refreshes are progress only: there is deliberately no completeness parameter.
create function public.record_weekly_progress_v1(p_request_id uuid,p_challenge_id uuid,p_day date,p_steps integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; c app.weekly_agreements; p jsonb; v uuid; n timestamptz; begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','progress','id',p_challenge_id,'day',p_day,'steps',p_steps);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 select * into c from app.weekly_agreements where id=p_challenge_id for update; perform app.weekly_require_session_v1(); n:=clock_timestamp();
 if c.id is null or c.status in ('closed','final') or not exists(select 1 from app.weekly_participants where challenge_id=c.id and actor_id=a and accepted_at is not null and exited_at is null)
  or p_steps is null or p_steps not between 0 and 1000000 or not exists(select 1 from jsonb_array_elements(c.terms->'days') d where d->>'date'=p_day::text and (d->>'startsAt')::timestamptz<=n)
  or n>(c.terms->>'correctionsCloseAt')::timestamptz then raise exception 'weekly_progress_unavailable' using errcode='22023'; end if;
 if (select count(*) from app.weekly_progress where challenge_id=c.id and actor_id=a and day=p_day)>=128 then raise exception 'weekly_progress_limit' using errcode='23505'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_progress values(p_request_id,c.id,a,p_day,p_steps,n);
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,n); return p_request_id;
end; $$;

create function app.weekly_fixture_at_v1(p_request_id uuid,p_challenge_id uuid,p_actor_id uuid,p_day date,p_status text,p_steps integer,p_now timestamptz default null)
returns integer language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.weekly_agreements; old app.weekly_revisions; n timestamptz; rev integer; d jsonb;
begin
 perform app.duel_require_service_v1();
 select * into c from app.weekly_agreements where id=p_challenge_id for update; n:=coalesce(p_now,clock_timestamp());
 select * into old from app.weekly_revisions where source_request=p_request_id;
 if found then
  if (old.challenge_id,old.actor_id,old.day,old.document->>'status',(old.document->>'steps')::integer) is distinct from (p_challenge_id,p_actor_id,p_day,p_status,p_steps) then
   raise exception 'weekly_fixture_conflict' using errcode='22023'; end if;
  return old.revision;
 end if;
 if c.id is null or not (select fixture_enabled from app.weekly_runtime where singleton) or c.status in ('closed','final')
  or not exists(select 1 from app.weekly_participants where challenge_id=c.id and actor_id=p_actor_id and accepted_at is not null and exited_at is null)
  or not app.is_active_actor(p_actor_id) or not isfinite(n) or n<c.created_at
  or p_status is null or p_status not in ('complete','incomplete','missing','revoked','query_failed')
  or ((p_status in ('complete','incomplete')) is distinct from (p_steps is not null))
  or (p_steps is not null and p_steps not between 0 and 1000000)
  or not exists(select 1 from jsonb_array_elements(c.terms->'days') x where x->>'date'=p_day::text and (x->>'endsAt')::timestamptz<=n)
  or n>=(c.terms->>'correctionsCloseAt')::timestamptz then raise exception 'weekly_fixture_unavailable' using errcode='22023'; end if;
 select coalesce(max(revision),0)+1 into rev from app.weekly_revisions where challenge_id=c.id and actor_id=p_actor_id and day=p_day;
 if rev>128 or (rev=1 and n>=(c.terms->>'uploadClosesAt')::timestamptz) then raise exception 'weekly_fixture_cutoff' using errcode='22023'; end if;
 d:=jsonb_build_object('agreementId',c.id,'participantId',p_actor_id,'termsDigest',c.terms_digest,
  'policyVersion',c.terms->'policy'->>'version','sourceVersion','fixture_weekly_steps_v1','date',p_day,'revision',rev,
  'previousRevision',case when rev>1 then rev-1 end,'receivedAt',n,'status',p_status,'steps',p_steps);
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_revisions values(c.id,p_actor_id,p_day,rev,p_request_id,n,d);
 update app.weekly_agreements set version=version+1 where id=c.id; return rev;
end; $$;
create function public.capture_weekly_fixture_v1(p_request_id uuid,p_challenge_id uuid,p_actor_id uuid,p_day date,p_status text,p_steps integer)
returns integer language sql security definer set search_path='' as $$select app.weekly_fixture_at_v1(p_request_id,p_challenge_id,p_actor_id,p_day,p_status,p_steps)$$;

create function app.weekly_snapshot_v1(c app.weekly_agreements,n timestamptz) returns jsonb
language sql set search_path='' set timezone='UTC' as $$
 select jsonb_build_object('agreement',jsonb_build_object('id',c.id,'termsDigest',c.terms_digest,'terms',c.terms),
  'mode',c.mode,'version',c.version,'status',c.status,'joinBy',c.join_by,'capacity',c.capacity,'now',n,
  'participants',coalesce((select jsonb_agg(to_jsonb(p) order by actor_id) from app.weekly_participants p where challenge_id=c.id),'[]'::jsonb),
  'consents',coalesce((select jsonb_agg(jsonb_build_object('agreementId',c.id,'participantId',actor_id,'termsDigest',consent_digest,
   'policyVersion',c.terms->'policy'->>'version','termsBinding',app.weekly_canonical_v1(c.terms),'acceptedAt',accepted_at) order by actor_id)
   from app.weekly_participants where challenge_id=c.id and accepted_at is not null),'[]'::jsonb),
  'revisions',coalesce((select jsonb_agg(document order by actor_id,day,revision) from app.weekly_revisions where challenge_id=c.id),'[]'::jsonb),
  'notices',coalesce((select jsonb_agg(to_jsonb(x) order by revision) from app.weekly_notices x where challenge_id=c.id),'[]'::jsonb),
  'cases',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('resolution',(select to_jsonb(r) from app.weekly_resolutions r where case_id=x.id)) order by x.id)
   from app.weekly_cases x where challenge_id=c.id),'[]'::jsonb),
  'exits',coalesce((select jsonb_agg(to_jsonb(x) order by actor_id) from app.weekly_exits x where challenge_id=c.id),'[]'::jsonb),
  'result',(select to_jsonb(x) from app.weekly_results x where challenge_id=c.id))
$$;
create function app.weekly_load_at_v1(p_challenge_id uuid,p_now timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app.weekly_agreements; n timestamptz; begin
 perform app.duel_require_service_v1();
 if not (select worker_enabled from app.weekly_runtime where singleton) then return null; end if;
 select * into c from app.weekly_agreements where id=p_challenge_id for update; n:=coalesce(p_now,clock_timestamp());
 if not found or not isfinite(n) or n<c.created_at then raise exception 'weekly_worker_unavailable' using errcode='22023'; end if;
 return app.weekly_snapshot_v1(c,n);
end; $$;
create function public.load_weekly_lifecycle_v1(p_challenge_id uuid) returns jsonb language sql security definer set search_path='' as $$select app.weekly_load_at_v1(p_challenge_id)$$;

create function app.weekly_file_at_v1(p_request_id uuid,p_challenge_id uuid,p_notice_revision integer,p_reason text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; c app.weekly_agreements; t app.weekly_notices; p jsonb; v uuid; n timestamptz;
begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','review','id',p_challenge_id,'revision',p_notice_revision,'reason',p_reason);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 select * into c from app.weekly_agreements where id=p_challenge_id for update;
 select * into t from app.weekly_notices where challenge_id=p_challenge_id and revision=p_notice_revision;
 perform app.weekly_require_session_v1(); n:=coalesce(p_now,clock_timestamp());
 if c.id is null or c.status='final' or t.challenge_id is null or not isfinite(n) or n<t.recorded_at or n>=t.file_by
  or not exists(select 1 from app.weekly_participants where challenge_id=c.id and actor_id=a and accepted_at is not null)
  or p_reason is null or p_reason not in ('wrong_total','source_problem','wrong_result') then raise exception 'weekly_review_unavailable' using errcode='55000'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_cases values(p_request_id,c.id,a,p_notice_revision,p_reason,n);
 update app.weekly_agreements set version=version+1 where id=c.id;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,n); return p_request_id;
end; $$;
create function public.file_weekly_review_v1(p_request_id uuid,p_challenge_id uuid,p_notice_revision integer,p_reason text)
returns uuid language sql security definer set search_path='' as $$select app.weekly_file_at_v1(p_request_id,p_challenge_id,p_notice_revision,p_reason)$$;
create function app.weekly_resolve_at_v1(p_case_id uuid,p_decision text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c app.weekly_agreements; k app.weekly_cases; r app.weekly_resolutions; n timestamptz;
begin
 perform app.duel_require_service_v1();
 select * into k from app.weekly_cases where id=p_case_id;
 select * into c from app.weekly_agreements where id=k.challenge_id for update;
 select * into r from app.weekly_resolutions where case_id=p_case_id;
 if found then if r.decision is distinct from p_decision then raise exception 'weekly_resolution_conflict' using errcode='22023'; end if; return p_case_id; end if;
 n:=coalesce(p_now,clock_timestamp());
 if c.id is null or c.status='final' or not isfinite(n) or n<k.recorded_at or p_decision is null or p_decision not in ('upheld','void')
  or n>=(select resolve_by from app.weekly_notices where challenge_id=c.id and revision=k.notice_revision) then
  raise exception 'weekly_resolution_unavailable' using errcode='55000'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_resolutions values(p_case_id,p_decision,n);
 update app.weekly_agreements set version=version+1 where id=c.id; return p_case_id;
end; $$;
create function public.resolve_weekly_review_v1(p_case_id uuid,p_decision text) returns uuid language sql security definer set search_path='' as $$select app.weekly_resolve_at_v1(p_case_id,p_decision)$$;
create function public.submit_weekly_support_v1(p_request_id uuid,p_challenge_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; n timestamptz; begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','support','id',p_challenge_id,'reason',p_reason);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a)
  or p_reason is null or p_reason not in ('correction','privacy','unwanted_contact','exit_help') then raise exception 'weekly_support_unavailable' using errcode='42501'; end if;
 if (select count(*) from app.weekly_support where challenge_id=p_challenge_id and actor_id=a)>=32 then raise exception 'weekly_support_limit' using errcode='23505'; end if;
 n:=clock_timestamp(); perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_support values(p_request_id,p_challenge_id,a,p_reason,n);
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,n); return p_request_id;
end; $$;

-- Authorized worker boundary trusts its pure evaluator, never a participant decision.
-- Full snapshot/version compare serializes revisions, consent, deletion, reviews and finality.
create function app.weekly_commit_at_v1(p_input jsonb,p_decision jsonb,p_now timestamptz default null)
returns text language plpgsql security definer set search_path='' as $$
declare c app.weekly_agreements; n timestamptz; oldnow timestamptz; current_input jsonb; deadline timestamptz;
 q jsonb; phase text:=p_decision->>'phase'; revision integer; item jsonb;
begin
 perform app.duel_require_service_v1();
 if not (select worker_enabled from app.weekly_runtime where singleton) then return 'inactive'; end if;
 select * into c from app.weekly_agreements where id=(p_input->'agreement'->>'id')::uuid for update;
 if not found then raise exception 'weekly_worker_unavailable' using errcode='22023'; end if;
 n:=coalesce(p_now,clock_timestamp()); oldnow:=(p_input->>'now')::timestamptz;
 if not isfinite(n) or n<oldnow or n<c.created_at then raise exception 'weekly_invalid_clock' using errcode='22023'; end if;
 current_input:=app.weekly_snapshot_v1(c,oldnow);
 if current_input is distinct from p_input then return 'stale'; end if;
 -- A boundary crossed while evaluation ran must be reconsidered at fresh DB time.
 for deadline in select v from (values(c.join_by),(c.starts_at),(c.ends_at),((c.terms->>'uploadClosesAt')::timestamptz),
  ((c.terms->>'correctionsCloseAt')::timestamptz),((c.terms->'lifecycle'->>'noticeBy')::timestamptz),((c.terms->'lifecycle'->>'finalityBy')::timestamptz)) x(v)
  union select file_by from app.weekly_notices where challenge_id=c.id union select resolve_by from app.weekly_notices where challenge_id=c.id loop
  if oldnow<=deadline and n>deadline then return 'stale'; end if;
 end loop;
 if c.status='final' then return 'final'; end if;
 if p_decision->>'version' is distinct from 'weekly-lifecycle-v1' or p_decision->>'agreementId' is distinct from c.id::text
  or p_decision->>'termsDigest' is distinct from c.terms_digest or phase is null
  or phase not in ('scheduled','active','awaiting_observations','review','notice','final') then raise exception 'weekly_invalid_decision' using errcode='22023'; end if;
 q:=p_decision->'qualifications';
 if phase in ('notice','final') then
  if jsonb_typeof(q) is distinct from 'array' or jsonb_array_length(q)<>(select count(*) from app.weekly_participants where challenge_id=c.id and accepted_at is not null)
   or (select count(distinct x->>'participantId') from jsonb_array_elements(q) x)<>jsonb_array_length(q) then raise exception 'weekly_invalid_qualifications' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(q) loop
   if not exists(select 1 from app.weekly_participants where challenge_id=c.id and accepted_at is not null and actor_id::text=item->>'participantId')
    or item->>'qualification' is null or item->>'qualification' not in ('met','confirmed_miss','unresolved','refund') then raise exception 'weekly_invalid_qualifications' using errcode='22023'; end if;
  end loop;
 end if;
 perform set_config('app.weekly_write_v1','on',true);
 if phase='notice' then
  if n<=(c.terms->>'uploadClosesAt')::timestamptz or n>(c.terms->'lifecycle'->>'noticeBy')::timestamptz then raise exception 'weekly_notice_window' using errcode='22023'; end if;
  select coalesce(max(x.revision),0)+1 into revision from app.weekly_notices x where challenge_id=c.id;
  if revision>896 then raise exception 'weekly_notice_limit' using errcode='23505'; end if;
  insert into app.weekly_notices values(c.id,revision,q,jsonb_array_length(p_input->'revisions'),n,n+interval '48 hours',n+interval '120 hours');
  update app.weekly_agreements set status='review',version=version+1 where id=c.id;
 elsif phase='final' then
  -- Early terminal paths may only refund, never establish a miss. Ordinary finals
  -- require every durable full filing/resolution window to have elapsed.
  if exists(select 1 from jsonb_array_elements(q) x where x->>'qualification' not in ('refund','unresolved')) then
   if n<=(c.terms->>'correctionsCloseAt')::timestamptz
    or not exists(select 1 from app.weekly_notices where challenge_id=c.id)
    or exists(select 1 from app.weekly_notices where challenge_id=c.id and file_by>n)
    or exists(select 1 from app.weekly_cases k join app.weekly_notices t on (t.challenge_id,t.revision)=(k.challenge_id,k.notice_revision)
     where k.challenge_id=c.id and t.resolve_by>n and not exists(select 1 from app.weekly_resolutions where case_id=k.id)) then
    raise exception 'weekly_finality_window' using errcode='22023'; end if;
  end if;
  insert into app.weekly_results values(c.id,q,p_decision->>'reason',c.version,n);
  update app.weekly_agreements set status='final',version=version+1 where id=c.id;
 else
  if not(c.status='invited' and phase='scheduled' and p_decision->>'reason'='acceptance_open') and c.status<>'closed' and (case when phase='scheduled' then 'scheduled' when phase='active' then 'active' else 'review' end)<>c.status then
   update app.weekly_agreements set status=case when phase='scheduled' then 'scheduled' when phase='active' then 'active' else 'review' end,version=version+1 where id=c.id;
  end if;
 end if;
 return phase;
end; $$;
create function public.commit_weekly_lifecycle_v1(p_input jsonb,p_decision jsonb) returns text language sql security definer set search_path='' as $$select app.weekly_commit_at_v1(p_input,p_decision)$$;

create function public.settle_weekly_simulation_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app.weekly_agreements; r app.weekly_results; settled app.weekly_allocations; q jsonb; count_met integer;
 forfeits integer; total integer; remainder integer; allocations jsonb; distributed integer; begin
 perform app.duel_require_service_v1();
 select * into c from app.weekly_agreements where id=p_challenge_id for update;
 select * into settled from app.weekly_allocations where challenge_id=c.id; if found then return to_jsonb(settled); end if;
 select * into r from app.weekly_results where challenge_id=c.id; if not found then raise exception 'weekly_final_required' using errcode='55000'; end if;
 select count(*) filter(where x->>'qualification'='met'),count(*) filter(where x->>'qualification'='confirmed_miss')*2000,count(*)*2000
 into count_met,forfeits,total from jsonb_array_elements(r.qualifications) x;
 remainder:=case when count_met=0 then forfeits else forfeits%count_met end;
 select coalesce(jsonb_agg(jsonb_build_object('participantId',x->>'participantId','returnedCents',case when x->>'qualification'='confirmed_miss' then 0 else 2000 end,
  'bonusCents',case when x->>'qualification'='met' and count_met>0 then forfeits/count_met else 0 end) order by x->>'participantId'),'[]'::jsonb)
 into allocations from jsonb_array_elements(r.qualifications) x;
 select coalesce(sum((x->>'returnedCents')::integer+(x->>'bonusCents')::integer),0) into distributed from jsonb_array_elements(allocations) x;
 if distributed+remainder<>total then raise exception 'weekly_conservation_failed' using errcode='23000'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_allocations values(c.id,allocations,total,remainder,clock_timestamp(),'fictional_nonredeemable',false) returning * into settled;
 return to_jsonb(settled);
end; $$;

create function app.weekly_projection_v1(c app.weekly_agreements,a uuid) returns jsonb
language plpgsql set search_path='' set timezone='UTC' as $$
declare q app.weekly_participants; t jsonb:=c.terms; redacted boolean; roster jsonb; res jsonb; allocation jsonb;
begin
 select * into q from app.weekly_participants where challenge_id=c.id and actor_id=a;
 if not found then raise exception 'weekly_unavailable' using errcode='42501'; end if;
 redacted:=c.mode='community' or exists(select 1 from app.weekly_participants p where p.challenge_id=c.id and p.actor_id<>a
  and (not app.is_active_actor(p.actor_id) or app.is_blocked_either_way(a,p.actor_id)));
 if redacted and c.mode='friend' then t:=jsonb_set(t,'{participants}',jsonb_build_array(jsonb_build_object('participantId',a,'targetSteps',q.target_steps)))-'creatorId'; end if;
 select case when redacted then '[]'::jsonb else coalesce(jsonb_agg(jsonb_build_object('actor_id',actor_id,'display_name',(select display_name from public.profiles where id=actor_id),'target_steps',target_steps,
  'accepted_at',accepted_at,'declined_at',declined_at,'exited_at',exited_at) order by actor_id),'[]'::jsonb) end into roster from app.weekly_participants where challenge_id=c.id;
 select jsonb_build_object('recorded_at',r.recorded_at,'qualification',x->>'qualification','reason',r.reason) into res
  from app.weekly_results r cross join lateral jsonb_array_elements(r.qualifications) x where r.challenge_id=c.id and x->>'participantId'=a::text;
 select jsonb_build_object('recorded_at',r.recorded_at,'returned_cents',(x->>'returnedCents')::integer,'bonus_cents',(x->>'bonusCents')::integer,
  'mode',r.mode,'redeemable',r.redeemable) into allocation from app.weekly_allocations r cross join lateral jsonb_array_elements(r.allocations) x
  where r.challenge_id=c.id and x->>'participantId'=a::text;
 return jsonb_build_object('id',c.id,'mode',c.mode,'status',c.status,'terms',t,'terms_digest',c.terms_digest,'server_now',clock_timestamp(),
  'participant_count',(select count(*) from app.weekly_participants where challenge_id=c.id),
  'accepted_count',(select count(*) from app.weekly_participants where challenge_id=c.id and accepted_at is not null),
  'own',jsonb_build_object('actor_id',a,'target_steps',q.target_steps,'accepted_at',q.accepted_at,'declined_at',q.declined_at,'exited_at',q.exited_at),
  'roster',roster,'contact_suppressed',redacted and c.mode='friend',
  'own_progress',jsonb_build_object('observed_steps',(select coalesce(sum(x.steps),0) from (select distinct on(day) steps from app.weekly_progress where challenge_id=c.id and actor_id=a order by day,recorded_at desc,id desc) x),
   'qualifying_steps',(select sum(case when x.document->>'status'='complete' then (x.document->>'steps')::integer else 0 end) from (select distinct on(day) document from app.weekly_revisions where challenge_id=c.id and actor_id=a order by day,revision desc) x),
   'complete_day_count',(select count(*) from (select distinct on(day) document from app.weekly_revisions where challenge_id=c.id and actor_id=a order by day,revision desc) x where x.document->>'status'='complete'),
   'updated_at',greatest((select max(recorded_at) from app.weekly_progress where challenge_id=c.id and actor_id=a),(select max(received_at) from app.weekly_revisions where challenge_id=c.id and actor_id=a)),
   'status',case when exists(select 1 from app.weekly_revisions where challenge_id=c.id and actor_id=a) then 'fixture_only' else 'client_progress_only' end),
  'progress',coalesce((select jsonb_agg(jsonb_build_object('day',x.day,'steps',x.steps,'recorded_at',x.recorded_at,'qualifying',false) order by x.day)
   from (select distinct on(day) * from app.weekly_progress where challenge_id=c.id and actor_id=a order by day,recorded_at desc,id desc) x),'[]'::jsonb),
  'notices',coalesce((select jsonb_agg(jsonb_build_object('revision',n.revision,'recorded_at',n.recorded_at,'file_by',n.file_by,'resolve_by',n.resolve_by,
   'qualification',(select x->>'qualification' from jsonb_array_elements(n.qualifications) x where x->>'participantId'=a::text)) order by n.revision)
   from app.weekly_notices n where n.challenge_id=c.id),'[]'::jsonb),
  'cases',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'notice_revision',k.notice_revision,'reason',k.reason,'recorded_at',k.recorded_at,
   'resolution',(select decision from app.weekly_resolutions where case_id=k.id)) order by k.recorded_at,k.id) from app.weekly_cases k where k.challenge_id=c.id and k.actor_id=a),'[]'::jsonb),
  'exits',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'recorded_at',x.recorded_at)) from app.weekly_exits x where x.challenge_id=c.id and x.actor_id=a),'[]'::jsonb),
  'support',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'reason',x.reason,'recorded_at',x.recorded_at) order by x.recorded_at,x.id)
   from app.weekly_support x where x.challenge_id=c.id and x.actor_id=a),'[]'::jsonb),'result',res,'allocation',allocation);
end; $$;
create function public.get_weekly_v1(p_challenge_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; c app.weekly_agreements; begin
 a:=app.weekly_session_v1(); select * into c from app.weekly_agreements where id=p_challenge_id;
 if not found then raise exception 'weekly_unavailable' using errcode='42501'; end if;
 return app.weekly_projection_v1(c,a);
end; $$;
create function public.list_my_weekly_v1() returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; begin
 a:=app.weekly_session_v1();
 select coalesce(jsonb_agg(app.weekly_projection_v1(c,a) order by c.created_at desc,c.id desc),'[]'::jsonb) into r
  from (select g.* from app.weekly_agreements g join app.weekly_participants p on p.challenge_id=g.id
   where p.actor_id=a order by g.created_at desc,g.id desc limit 50) c;
 return r;
end; $$;
create function public.list_weekly_cohorts_v1() returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; begin
 a:=app.weekly_session_v1();
 if not exists(select 1 from app.weekly_runtime where singleton and enabled and a=any(actor_ids)) then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'mode',c.mode,'terms',c.terms,'terms_digest',c.terms_digest,'join_by',c.join_by,'capacity',c.capacity,
  'participant_count',(select count(*) from app.weekly_participants where challenge_id=c.id and accepted_at is not null)) order by c.starts_at,c.id),'[]'::jsonb)
 into r from (select * from app.weekly_agreements where mode='community' and status in ('invited','scheduled') and join_by>clock_timestamp() order by starts_at,id limit 10) c;
 return r;
end; $$;

-- Additive deletion hook closes NEW fictional contracts only. Historical receipts
-- remain pseudonymous private records; no names, health blobs or external delivery.
create function app.weekly_delete_v1() returns trigger language plpgsql security definer set search_path='' as $$
declare c app.weekly_agreements; n timestamptz; begin
 if old.deleted_at is not null or new.deleted_at is null then return new; end if;
 n:=new.deleted_at; perform set_config('app.weekly_write_v1','on',true);
 delete from app.weekly_pilot_events where actor_id=new.id;
 update app.weekly_requests set payload=jsonb_build_object('op','pilot_erased') where actor_id=new.id and payload->>'op'='pilot_event';
 update app.weekly_pilot_consents set enabled=false where actor_id=new.id;
 for c in select g.* from app.weekly_agreements g join app.weekly_participants p on p.challenge_id=g.id
  where p.actor_id=new.id and g.status<>'final' order by g.id for update of g loop
  if not exists(select 1 from app.weekly_exits where challenge_id=c.id and actor_id=new.id) then
   insert into app.weekly_exits values(extensions.gen_random_uuid(),c.id,new.id,'account_deleted',n);
   update app.weekly_participants set exited_at=n where challenge_id=c.id and actor_id=new.id;
  end if;
  update app.weekly_agreements set version=version+1,status=case when mode='friend' then 'closed' else status end where id=c.id;
 end loop;
 return new;
end; $$;
create trigger profiles_weekly_delete after update of deleted_at on public.profiles for each row execute function app.weekly_delete_v1();

-- Revoke default EXECUTE from every newly introduced function, then allow only
-- purpose-limited public wrappers. Private test clocks are never API-callable.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('app','public') and (p.proname like 'weekly_%' or p.proname in (
   'set_weekly_runtime_v1','preview_weekly_friend_v1','create_weekly_friend_v1','curate_weekly_cohort_v1','accept_weekly_v1','join_weekly_cohort_v1',
   'exit_weekly_v1','set_weekly_entry_pause_v1','record_weekly_progress_v1','capture_weekly_fixture_v1','load_weekly_lifecycle_v1',
   'file_weekly_review_v1','resolve_weekly_review_v1','submit_weekly_support_v1','commit_weekly_lifecycle_v1','settle_weekly_simulation_v1',
   'get_weekly_v1','list_my_weekly_v1','list_weekly_cohorts_v1')) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
 end loop;
end; $$;
grant execute on function public.preview_weekly_friend_v1(jsonb,date,text),public.create_weekly_friend_v1(uuid,jsonb,text,boolean),
 public.accept_weekly_v1(uuid,uuid,text,boolean),public.join_weekly_cohort_v1(uuid,uuid,text,boolean),public.exit_weekly_v1(uuid,uuid,text),
 public.set_weekly_entry_pause_v1(uuid,boolean),public.record_weekly_progress_v1(uuid,uuid,date,integer),
 public.file_weekly_review_v1(uuid,uuid,integer,text),public.submit_weekly_support_v1(uuid,uuid,text),
 public.get_weekly_v1(uuid),public.list_my_weekly_v1(),public.list_weekly_cohorts_v1() to authenticated;
grant execute on function public.set_weekly_runtime_v1(boolean,boolean,boolean,uuid[]),public.curate_weekly_cohort_v1(uuid,date,text,integer,integer),
 public.capture_weekly_fixture_v1(uuid,uuid,uuid,date,text,integer),public.load_weekly_lifecycle_v1(uuid),
 public.resolve_weekly_review_v1(uuid,text),public.commit_weekly_lifecycle_v1(jsonb,jsonb),public.settle_weekly_simulation_v1(uuid) to service_role;

create function public.get_weekly_preferences_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; begin
 a:=app.weekly_session_v1();
 return jsonb_build_object('entry_paused',coalesce((select paused from app.weekly_pauses where actor_id=a),false),
  'pilot_consent',coalesce((select enabled from app.weekly_pilot_consents where actor_id=a),false));
end; $$;
create function public.set_weekly_pilot_consent_v1(p_request_id uuid,p_enabled boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','pilot_consent','enabled',p_enabled);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if p_enabled is null then raise exception 'weekly_consent_required' using errcode='22023'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_pilot_consents values(a,p_enabled) on conflict(actor_id) do update set enabled=excluded.enabled;
 if not p_enabled then
  delete from app.weekly_pilot_events where actor_id=a;
  update app.weekly_requests set payload=jsonb_build_object('op','pilot_erased') where actor_id=a and payload->>'op'='pilot_event';
 end if;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;
create function public.record_weekly_pilot_event_v1(p_request_id uuid,p_challenge_id uuid,p_event text,p_phase text) returns uuid
language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; begin
 a:=app.weekly_session_v1(); p:=jsonb_build_object('op','pilot_event','id',p_challenge_id,'event',p_event,'phase',p_phase);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if not exists(select 1 from app.weekly_pilot_consents where actor_id=a and enabled)
  or p_event is null or p_event not in ('rule_preview','consent','invitation','cohort_join','progress_refresh','result_view','review','withdrawal','next_week','sharing')
  or p_phase is null or p_phase not in ('intent','exposure','outcome') then raise exception 'weekly_pilot_unavailable' using errcode='42501'; end if;
 if p_challenge_id is not null and not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a)
  and not exists(select 1 from app.weekly_agreements c join app.weekly_runtime r on r.singleton where c.id=p_challenge_id and c.mode='community'
   and c.status in ('invited','scheduled') and c.join_by>clock_timestamp() and r.enabled and a=any(r.actor_ids)) then raise exception 'weekly_pilot_unavailable' using errcode='42501'; end if;
 if (select count(*) from app.weekly_pilot_events where actor_id=a)>=1000 then raise exception 'weekly_pilot_limit' using errcode='23505'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_pilot_events(id,actor_id,challenge_id,event,phase,recorded_at) values(p_request_id,a,p_challenge_id,p_event,p_phase,clock_timestamp());
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;
revoke all on function public.get_weekly_preferences_v1(),public.set_weekly_pilot_consent_v1(uuid,boolean),public.record_weekly_pilot_event_v1(uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.get_weekly_preferences_v1(),public.set_weekly_pilot_consent_v1(uuid,boolean),public.record_weekly_pilot_event_v1(uuid,uuid,text,text) to authenticated;

-- Resolve a response-lost request atomically. Retiring an absent key prevents a
-- delayed original request from committing, without erasing committed receipts.
create function public.resolve_weekly_request_v1(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; r app.weekly_requests; begin
 a:=app.weekly_session_v1();
 if p_request_id is null then raise exception 'weekly_request_required' using errcode='22023'; end if;
 select * into r from app.weekly_requests where actor_id=a and request_id=p_request_id;
 if found and r.payload->>'op' not in ('retired','pilot_erased') then
  return jsonb_build_object('state','committed','receipt_id',r.response_id);
 end if;
 if not found then
  perform set_config('app.weekly_write_v1','on',true);
  insert into app.weekly_requests values(a,p_request_id,'{"op":"retired"}',p_request_id,clock_timestamp());
 end if;
 return jsonb_build_object('state','cancelled','receipt_id',null);
end; $$;
revoke all on function public.resolve_weekly_request_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.resolve_weekly_request_v1(uuid) to authenticated;
