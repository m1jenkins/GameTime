-- P6 private operator community. Existing agreement/request bytes stay immutable.
-- Data-plane lock order remains P4: gate -> caller -> session -> challenge ->
-- profiles -> rows. Join reserves only its caller profile and one capacity row;
-- worker/moderation retain challenge exclusion for lifecycle safety.
create table app.challenge_community_publications_v1 (
 challenge_id uuid primary key references app.challenge_lobbies_v1(id),
 publisher_id uuid not null references public.profiles(id),
 publisher_type text not null check(publisher_type='operator'),
 published_at timestamptz not null
);
create table app.challenge_community_capacity_v1 (
 challenge_id uuid primary key references app.challenge_lobbies_v1(id),
 reserved integer not null check(reserved>=0 and reserved<=250)
);
create table app.challenge_community_members_v1 (
 challenge_id uuid not null, actor_id uuid not null, revision bigint not null default 1,
 primary key(challenge_id,actor_id),
 foreign key(challenge_id,actor_id) references app.challenge_members_v1(challenge_id,actor_id)
);
create table app.challenge_community_snapshots_v1 (
 challenge_id uuid not null references app.challenge_lobbies_v1(id),
 captured_at timestamptz not null, joined integer check(joined>=5),
 primary key(challenge_id,captured_at)
);
-- Separate report scope: historical unscoped reports remain global-support only.
create table app.challenge_report_scopes_v1 (
 report_id uuid primary key references app.challenge_reports_v1(id),
 challenge_id uuid not null references app.challenge_lobbies_v1(id)
);
create table app.challenge_support_grants_v1 (
 actor_id uuid primary key references public.profiles(id), expires_at timestamptz not null
);
create table app.challenge_appeals_v1 (
 id uuid primary key, actor_id uuid not null references public.profiles(id),
 suspension_at timestamptz not null, filed_at timestamptz not null,
 unique(actor_id,suspension_at)
);
create table app.challenge_appeal_decisions_v1 (
 appeal_id uuid primary key references app.challenge_appeals_v1(id),
 operator_id uuid not null references public.profiles(id),
 decision text not null check(decision in ('upheld','reinstate')), recorded_at timestamptz not null
);
create table app.challenge_quotas_v1 (
 actor_id uuid not null references public.profiles(id), bucket text not null,
 window_at timestamptz not null, used integer not null check(used>0),
 primary key(actor_id,bucket)
);
do $$ declare t text; begin
 foreach t in array array['community_publications','community_capacity','community_members','community_snapshots','report_scopes','support_grants','appeals','appeal_decisions','quotas'] loop
  execute format('alter table app.challenge_%s_v1 enable row level security',t);
  execute format('revoke all on app.challenge_%s_v1 from public,anon,authenticated,service_role',t);
 end loop;
end $$;
-- Only new private projections are backfilled; no agreement, receipt or fact changes.
insert into app.challenge_community_publications_v1
 select id,creator_id,'operator',created_at from app.challenge_lobbies_v1 where policy='community_steps_goal_v1';
insert into app.challenge_community_capacity_v1
 select c.id,count(m.actor_id) filter(where m.exited_at is null)
 from app.challenge_lobbies_v1 c left join app.challenge_members_v1 m on m.challenge_id=c.id
 where c.policy='community_steps_goal_v1' group by c.id;
insert into app.challenge_community_members_v1(challenge_id,actor_id)
 select m.challenge_id,m.actor_id from app.challenge_members_v1 m join app.challenge_community_publications_v1 p using(challenge_id);

create function app.challenge_community_member_state_v1() returns trigger
language plpgsql set search_path='' as $$
declare delta integer;
begin
 if not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=new.challenge_id) then return new; end if;
 if tg_table_name='challenge_members_v1' then
  if tg_op='INSERT' then
   delta:=case when new.exited_at is null then 1 else 0 end;
   insert into app.challenge_community_members_v1(challenge_id,actor_id) values(new.challenge_id,new.actor_id);
  else
   delta:=(case when new.exited_at is null then 1 else 0 end)-(case when old.exited_at is null then 1 else 0 end);
   update app.challenge_community_members_v1 set revision=revision+1 where challenge_id=new.challenge_id and actor_id=new.actor_id;
  end if;
  if delta<>0 then update app.challenge_community_capacity_v1 set reserved=reserved+delta where challenge_id=new.challenge_id; end if;
 else
  update app.challenge_community_members_v1 set revision=revision+1 where challenge_id=new.challenge_id and actor_id=new.actor_id;
 end if;
 return new;
end $$;
create trigger challenge_community_member_state after insert or update on app.challenge_members_v1 for each row execute function app.challenge_community_member_state_v1();
create trigger challenge_community_fact_state after insert on app.challenge_facts_v1 for each row execute function app.challenge_community_member_state_v1();
create trigger challenge_community_review_state after insert on app.challenge_reviews_v1 for each row execute function app.challenge_community_member_state_v1();
create function app.challenge_community_status_state_v1() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.policy='community_steps_goal_v1' and new.status is distinct from old.status then
  update app.challenge_community_members_v1 set revision=revision+1 where challenge_id=new.id;
 end if;
 return new;
end $$;
create trigger challenge_community_status_state after update on app.challenge_lobbies_v1 for each row execute function app.challenge_community_status_state_v1();
create function app.challenge_community_revision_v1(c uuid,a uuid) returns bigint
language sql stable set search_path='' as $$
 select revision from app.challenge_community_members_v1 where challenge_id=c and actor_id=a
$$;
create function app.challenge_community_eligible_v1(a uuid) returns boolean
language sql stable set search_path='' as $$
 select not app.challenge_actor_unavailable_v1(a)
 and exists(select 1 from app.challenge_age_v1 where actor_id=a)
 and exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures
  and (a=any(actors) or exists(select 1 from app.challenge_access_v1 where actor_id=a)))
$$;
create function app.challenge_community_counts_v1(c uuid) returns jsonb
language plpgsql set search_path='' as $$
declare s app.challenge_community_snapshots_v1; live integer;
begin
 select count(*) into live from app.challenge_members_v1 m
 where m.challenge_id=c and m.selected and m.exited_at is null and not app.challenge_actor_unavailable_v1(m.actor_id);
 if live<5 then return '{"joined":null,"state":"threshold","as_of":null}'; end if;
 select * into s from app.challenge_community_snapshots_v1 where challenge_id=c and captured_at<=app.challenge_now_v1()-interval '15 minutes' order by captured_at desc limit 1;
 if s.joined is null then return '{"joined":null,"state":"pending","as_of":null}'; end if;
 return jsonb_build_object('joined',s.joined,'state','available','as_of',s.captured_at);
end $$;
-- Capture is service-only, never a read side effect, never backdated. At most one
-- fixed snapshot per 15 minutes; a missed scheduler run simply delays disclosure.
create function public.challenge_capture_community_snapshot_v1(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare n timestamptz; joined integer;
begin
 perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1('challenge',p_id);
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and discovery)
 or not exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 n:=app.challenge_now_v1();
 if exists(select 1 from app.challenge_community_snapshots_v1 where challenge_id=p_id and captured_at>n-interval '15 minutes') then return; end if;
 select count(*) into joined from app.challenge_members_v1 m where m.challenge_id=p_id and m.selected and m.exited_at is null and not app.challenge_actor_unavailable_v1(m.actor_id);
 insert into app.challenge_community_snapshots_v1 values(p_id,n,case when joined>=5 then joined end);
end $$;

-- One counter per actor/category, fixed server minute/hour. Defaults are local
-- abuse-control choices, not approved hosted traffic budgets.
create function app.challenge_quota_v1(a uuid,b text,lim integer,period interval) returns boolean
language plpgsql set search_path='' as $$
declare n timestamptz:=clock_timestamp(); count integer;
begin
 insert into app.challenge_quotas_v1 values(a,b,n,1)
 on conflict(actor_id,bucket) do update set
  window_at=case when challenge_quotas_v1.window_at<=n-period then n else challenge_quotas_v1.window_at end,
  used=case when challenge_quotas_v1.window_at<=n-period then 1 else challenge_quotas_v1.used+1 end
 where challenge_quotas_v1.window_at<=n-period or challenge_quotas_v1.used<lim
 returning used into count;
 return count is not null;
end $$;
create function app.challenge_quota_error_v1(code text,status text default '429') returns jsonb
language plpgsql set search_path='' as $$
begin
 perform set_config('response.status',status,true);
 return jsonb_build_object('message',code);
end $$;
create function app.challenge_request_quota_v1() returns trigger language plpgsql set search_path='' as $$
declare op text:=new.payload->>'op';
begin
 if current_setting('role')<>'authenticated' or op in ('leave','cancel','review','block','revoke_link','appeal','close_community') or new.response->>'status'='cancelled_request' then return new; end if;
 if op in ('report','report_scoped') and not app.challenge_quota_v1(new.actor_id,'reports',10,interval '1 hour') then raise exception 'challenge_rate_limited' using errcode='P0001'; end if;
 if op='join_community' and not app.challenge_quota_v1(new.actor_id,'joins',6,interval '1 hour') then raise exception 'challenge_rate_limited' using errcode='P0001'; end if;
 if not app.challenge_quota_v1(new.actor_id,'mutations',120,interval '1 minute') then raise exception 'challenge_rate_limited' using errcode='P0001'; end if;
 return new;
end $$;
create trigger challenge_request_quota before insert on app.challenge_requests_v1 for each row execute function app.challenge_request_quota_v1();

create or replace function public.challenge_community_catalog_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1(); result jsonb;
begin
 if not app.challenge_quota_v1(a,'discovery',30,interval '1 minute') then return app.challenge_quota_error_v1('challenge_rate_limited'); end if;
 if not app.challenge_community_eligible_v1(a) or not exists(select 1 from app.challenge_runtime_v1 where singleton and discovery and fixtures) then return '[]'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'terms',ag.terms,'digest',ag.digest,'server_time',app.challenge_now_v1(),
 'joined_count',counts->'joined','counts',counts)),'[]') into result
 from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 ag on ag.challenge_id=c.id and ag.version=c.agreement_version
 cross join lateral(select app.challenge_community_counts_v1(c.id) counts) x
 where c.policy='community_steps_goal_v1' and c.status='published_open' and app.challenge_now_v1()<c.starts_at;
 perform app.challenge_session_v1(); return result;
end $$;
-- Preserve mature agreement bytes. New publication also seeds private capacity
-- and publisher metadata, with no user-hosting route or publication gate enabled.
do $$ declare d text; marker text; begin
 d:=pg_get_functiondef('public.challenge_publish_community_fixture_v1(uuid,uuid,jsonb,bigint,integer,integer,boolean)'::regprocedure);
 marker:='insert into app.challenge_agreements_v1 values(c,1,terms,default,n);';
 if position(marker in d)=0 then raise exception 'Unexpected publication'; end if;
 d:=replace(d,marker,marker||E'\n insert into app.challenge_community_publications_v1 values(c,p_operator,''operator'',n);\n insert into app.challenge_community_capacity_v1 values(c,0);');
 execute d;
 d:=pg_get_functiondef('public.challenge_join_community_v1(uuid,jsonb)'::regprocedure);
 marker:='if (select count(*) from app.challenge_members_v1 where challenge_id=c.id and exited_at is null)>=c.capacity';
 if position(marker in d)=0 then raise exception 'Unexpected capacity'; end if;
 d:=replace(d,marker,'if (select reserved from app.challenge_community_capacity_v1 where challenge_id=c.id for update)>=c.capacity');
 d:=replace(d,'perform app.challenge_admit_v1(actor);n:=','if not exists(select 1 from app.challenge_runtime_v1 where singleton and discovery) then raise exception ''challenge_discovery_disabled'' using errcode=''42501''; end if; perform app.challenge_admit_v1(actor);n:=');
 d:=replace(d,'''revision'',c.revision+1','''revision'',app.challenge_community_revision_v1(c.id,actor)');
 -- A rejected join must not identify the live capacity count.
 d:=replace(d,'raise exception ''challenge_capacity'' using errcode=''23505''','raise exception ''challenge_join_closed'' using errcode=''55000''');
 d:=replace(d,'raise exception ''challenge_join_closed'' using errcode=''55000''','raise exception ''challenge_join_closed'' using errcode=''P0001''');
 execute d;
 d:=pg_get_functiondef('app.challenge_detail_for_actor_v1(uuid,uuid)'::regprocedure);
 marker:='jsonb_build_object(''joined'',(select count(*) from app.challenge_members_v1 where challenge_id=p_id and exited_at is null))';
 if position(marker in d)=0 then raise exception 'Unexpected count projection'; end if;
 d:=replace(d,marker,'app.challenge_community_counts_v1(p_id)');
 d:=replace(d,'''revision'',c.revision,','''revision'',case when c.policy=''community_steps_goal_v1'' then app.challenge_community_revision_v1(p_id,a) else c.revision end,');
 execute d;
 d:=pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'if c.revision is distinct from (p_payload->>''revision'')::bigint',
 'if (case when c.policy=''community_steps_goal_v1'' then app.challenge_community_revision_v1(cid,a) else c.revision end) is distinct from (p_payload->>''revision'')::bigint');
 d:=replace(d,'''revision'',revision,''status'',status) into result',
 '''revision'',case when policy=''community_steps_goal_v1'' then app.challenge_community_revision_v1(id,a) else revision end,''status'',status) into result');
 execute d;
end $$;

-- Reports name their scope at filing. Never infer a report's scope later from
-- overlapping rosters. A community report may omit a subject to report the cohort.
create function public.challenge_report_scoped_v1(p_request_id uuid,p_id uuid,p_subject uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_mutation_session_v1(); s app.challenge_requests_v1; resolved_subject uuid;
 payload jsonb:=jsonb_build_object('op','report_scoped','id',p_id,'subject',p_subject,'reason',p_reason);
begin
 select * into s from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if s.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if; return s.response; end if;
 if p_request_id is null or p_reason is null or p_reason not in ('username','unwanted_contact','unsafe_behavior')
 or not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a)
 then raise exception 'challenge_report_unavailable' using errcode='42501'; end if;
 if p_subject is null then
  select publisher_id into resolved_subject from app.challenge_community_publications_v1 where challenge_id=p_id;
 else
  resolved_subject:=p_subject;
  if not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=resolved_subject)
   or (exists(select 1 from app.challenge_community_publications_v1 where challenge_id=p_id) and not app.is_friend(a,resolved_subject))
  then raise exception 'challenge_report_unavailable' using errcode='42501'; end if;
 end if;
 if resolved_subject is null then raise exception 'challenge_report_unavailable' using errcode='42501'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_reports_v1 values(p_request_id,a,resolved_subject,p_reason,app.challenge_now_v1());
 insert into app.challenge_report_scopes_v1 values(p_request_id,p_id);
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"saved":true}',app.challenge_now_v1());
 return '{"saved":true}';
end $$;
create or replace function public.challenge_operator_reports_v1(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1(); result jsonb;
begin
 perform 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='moderate' for share;
 if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='moderate' and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_operator_required' using errcode='42501'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,jsonb_build_object('op','read_reports','id',p_id),app.challenge_now_v1());
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
  select r.id,r.subject,r.reason,r.created_at from app.challenge_reports_v1 r join app.challenge_report_scopes_v1 scope on scope.report_id=r.id
  where scope.challenge_id=p_id order by r.created_at desc,r.id limit 100) q;
 perform app.challenge_session_v1(); return result;
end $$;
create function public.challenge_revoke_operator_v1(p_actor uuid,p_id uuid,p_capability text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1('actor',p_actor);
 perform set_config('app.challenge_write_v1','on',true);
 update app.challenge_operator_grants_v1 set expires_at=least(expires_at,app.challenge_now_v1()) where actor_id=p_actor and challenge_id=p_id and capability=p_capability;
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),p_actor,jsonb_build_object('op','revoke_grant','id',p_id,'capability',p_capability),app.challenge_now_v1());
end $$;
create function public.challenge_grant_support_v1(p_actor uuid,p_expires timestamptz) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1('actor',p_actor);
 if p_actor is null or app.challenge_actor_unavailable_v1(p_actor) or p_expires is null or not isfinite(p_expires) or p_expires<=app.challenge_now_v1() or p_expires>app.challenge_now_v1()+interval '7 days'
 then raise exception 'challenge_invalid_grant' using errcode='22023'; end if;
 insert into app.challenge_support_grants_v1 values(p_actor,p_expires) on conflict(actor_id) do update set expires_at=excluded.expires_at;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),p_actor,jsonb_build_object('op','grant_global_support','expires',p_expires),app.challenge_now_v1());
end $$;
create function public.challenge_revoke_support_v1(p_actor uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1(); perform app.challenge_gate_v1(); perform app.challenge_lock_v1('actor',p_actor);
 update app.challenge_support_grants_v1 set expires_at=least(expires_at,app.challenge_now_v1()) where actor_id=p_actor;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),p_actor,'{"op":"revoke_global_support"}',app.challenge_now_v1());
end $$;
create function app.challenge_require_support_v1(a uuid) returns void
language plpgsql set search_path='' as $$
begin
 perform 1 from app.challenge_support_grants_v1 where actor_id=a for share;
 if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_support_grants_v1 where actor_id=a and expires_at>app.challenge_now_v1())
 then raise exception 'challenge_support_required' using errcode='42501'; end if;
end $$;
create function public.challenge_support_reports_v1(p_before timestamptz default null,p_before_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1(); result jsonb;
begin
 perform app.challenge_require_support_v1(a); perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,'{"op":"read_global_reports"}',app.challenge_now_v1());
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
  select r.id,r.subject,r.reason,r.created_at,scope.challenge_id from app.challenge_reports_v1 r left join app.challenge_report_scopes_v1 scope on scope.report_id=r.id
  where p_before is null or (r.created_at,r.id)<(p_before,p_before_id) order by r.created_at desc,r.id desc limit 100) q;
 perform app.challenge_session_v1(); return result;
end $$;
create function public.challenge_support_suspend_v1(p_request_id uuid,p_subject uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_mutation_session_v1(); s app.challenge_requests_v1; ids uuid[]; cid uuid;
 payload jsonb:=jsonb_build_object('op','support_suspend','subject',p_subject,'reason',p_reason);
begin
 select * into s from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if s.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if; return s.response; end if;
 perform app.challenge_require_support_v1(a);
 if p_request_id is null or p_subject is null or p_subject=a or p_reason is null or p_reason not in ('username','unwanted_contact','unsafe_behavior') or not app.is_active_actor(p_subject)
 then raise exception 'challenge_invalid_moderation' using errcode='22023'; end if;
 -- Lock the complete challenge/profile union before synchronous safe exits.
 select coalesce(array_agg(m.challenge_id order by m.challenge_id),'{}') into ids from app.challenge_members_v1 m
 where m.actor_id=p_subject and m.exited_at is null and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=m.challenge_id);
 foreach cid in array ids loop perform app.challenge_lock_v1('challenge',cid); end loop;
 perform id from public.profiles where id=p_subject or id in(select actor_id from app.challenge_members_v1 where challenge_id=any(ids)) order by id for update;
 perform app.challenge_session_v1(); perform app.challenge_require_support_v1(a);
 if exists(select 1 from app.challenge_members_v1 m where m.actor_id=p_subject and m.exited_at is null and not(m.challenge_id=any(ids)) and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=m.challenge_id)) then
  raise exception 'challenge_retry_safety' using errcode='40001';
 end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_suspensions_v1 values(p_subject,true,a,p_reason,app.challenge_now_v1())
 on conflict(actor_id) do update set suspended=true,operator_id=excluded.operator_id,reason=excluded.reason,recorded_at=greatest(excluded.recorded_at,challenge_suspensions_v1.recorded_at+interval '1 microsecond')
 where not challenge_suspensions_v1.suspended;
 foreach cid in array ids loop perform app.challenge_tick_v1(cid,true); end loop;
 insert into app.challenge_operator_audit_v1 values(p_request_id,a,payload,app.challenge_now_v1());
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"saved":true}',app.challenge_now_v1()); return '{"saved":true}';
end $$;
create function public.challenge_appeal_v1(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_mutation_session_v1(); s app.challenge_requests_v1; suspension app.challenge_suspensions_v1;
 payload jsonb:='{"op":"appeal"}';
begin
 select * into s from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if s.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if; return s.response; end if;
 select * into suspension from app.challenge_suspensions_v1 where actor_id=a for share;
 if p_request_id is null or suspension.suspended is distinct from true then raise exception 'challenge_appeal_unavailable' using errcode='55000'; end if;
 insert into app.challenge_appeals_v1 values(p_request_id,a,suspension.recorded_at,app.challenge_now_v1());
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"saved":true}',app.challenge_now_v1()); return '{"saved":true}';
end $$;
create function public.challenge_support_appeals_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1(); result jsonb;
begin
 perform app.challenge_require_support_v1(a); perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,'{"op":"read_appeals"}',app.challenge_now_v1());
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
 select ap.id,ap.actor_id,ap.filed_at from app.challenge_appeals_v1 ap where not exists(select 1 from app.challenge_appeal_decisions_v1 d where d.appeal_id=ap.id) order by ap.filed_at,ap.id limit 100) q;
 perform app.challenge_session_v1(); return result;
end $$;
create function public.challenge_resolve_appeal_v1(p_request_id uuid,p_appeal uuid,p_decision text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_mutation_session_v1(); ap app.challenge_appeals_v1; s app.challenge_requests_v1;
 payload jsonb:=jsonb_build_object('op','resolve_appeal','appeal',p_appeal,'decision',p_decision);
begin
 select * into s from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if s.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if; return s.response; end if;
 perform app.challenge_require_support_v1(a);
 select * into ap from app.challenge_appeals_v1 where id=p_appeal;
 if p_request_id is null or ap.id is null or a=ap.actor_id or p_decision is null or p_decision not in ('upheld','reinstate') then raise exception 'challenge_appeal_unavailable' using errcode='55000'; end if;
 perform id from public.profiles where id=ap.actor_id for update;
 perform app.challenge_session_v1(); perform app.challenge_require_support_v1(a);
 if exists(select 1 from app.challenge_suspensions_v1 where actor_id=ap.actor_id and operator_id=a)
 or not exists(select 1 from app.challenge_suspensions_v1 where actor_id=ap.actor_id and suspended and recorded_at=ap.suspension_at)
 then raise exception 'challenge_independent_support_required' using errcode='42501'; end if;
 insert into app.challenge_appeal_decisions_v1 values(ap.id,a,p_decision,app.challenge_now_v1());
 perform set_config('app.challenge_write_v1','on',true);
 if p_decision='reinstate' then update app.challenge_suspensions_v1 set suspended=false,operator_id=a,recorded_at=app.challenge_now_v1() where actor_id=ap.actor_id; end if;
 -- Reinstatement permits future admission only; never restore ended participation.
 insert into app.challenge_operator_audit_v1 values(p_request_id,a,payload,app.challenge_now_v1());
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"saved":true}',app.challenge_now_v1()); return '{"saved":true}';
end $$;
create function public.challenge_own_appeals_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_session_v1();
begin
 return (select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (
 select ap.id,ap.filed_at,d.decision,d.recorded_at from app.challenge_appeals_v1 ap left join app.challenge_appeal_decisions_v1 d on d.appeal_id=ap.id where ap.actor_id=a order by ap.filed_at desc,ap.id limit 100) q);
end $$;
-- The shared revision was itself a live membership-count side channel. Older
-- stored receipts are preserved, but their obsolete display revision is masked.
create function app.challenge_private_receipt_v1(r jsonb) returns jsonb
language sql stable set search_path='' as $$
 select case when r ? 'id' and exists(select 1 from app.challenge_community_publications_v1 where challenge_id::text=r->>'id')
 then case when r->>'revision_scope'='member' then r-'revision_scope' else r||'{"revision":1}'::jsonb end else r end
$$;
do $$ declare d text; sig text; marker text; begin
 d:=pg_get_functiondef('public.challenge_join_community_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'''revision'',app.challenge_community_revision_v1(c.id,actor)', '''revision_scope'',''member'',''revision'',app.challenge_community_revision_v1(c.id,actor)');
 d:=replace(d,'return response;','return app.challenge_private_receipt_v1(response);');execute d;
 d:=pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,n);',
 'if c.policy=''community_steps_goal_v1'' then result:=result||''{"revision_scope":"member"}''::jsonb; end if; insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,n);');
 d:=replace(d,'return result;', 'return app.challenge_private_receipt_v1(result);');execute d;
 -- All exact recovery paths use the same redaction, including direct/dispatcher/stop.
 for sig in select oid::regprocedure::text from pg_proc where pronamespace='public'::regnamespace and proname like 'challenge_%' loop
  d:=pg_get_functiondef(sig::regprocedure);
  d:=replace(d,'return saved.response;','return app.challenge_private_receipt_v1(saved.response);');execute d;
 end loop;
 d:=pg_get_functiondef('public.challenge_operator_action_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'op not in (''resolve'',''remove'',''suspend'')','op not in (''resolve'',''remove'')');
 marker:='cap:=case when op=''resolve'' then ''review'' else ''moderate'' end;';
 d:=replace(d,marker,marker||' perform 1 from app.challenge_operator_grants_v1 where actor_id=actor and challenge_id=cid and capability=cap for share;');execute d;
 d:=pg_get_functiondef('public.challenge_operator_cases_v1(uuid)'::regprocedure);
 d:=replace(d,'if not exists(select 1 from app.challenge_operator_grants_v1',
 'perform 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability=''review'' for share; if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1');execute d;
 d:=pg_get_functiondef('public.challenge_operator_close_v1(uuid,uuid)'::regprocedure);
 d:=replace(d,'if p_request_id is null or app.challenge_actor_unavailable_v1(a)',
 'perform 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability=''moderate'' for share; if p_request_id is null or app.challenge_actor_unavailable_v1(a)');execute d;
 d:=pg_get_functiondef('public.challenge_appeal_v1(uuid)'::regprocedure);
 d:=replace(d,'select * into suspension', 'perform id from public.profiles where id=a for update; select * into suspension');execute d;
 -- Legacy account reports/blocking must not be an oracle for a stranger's
 -- membership in the private community. Known friend relationships remain usable.
 foreach sig in array array['public.challenge_report_v1(uuid,uuid,text)','public.challenge_block_v1(uuid,uuid)'] loop
  d:=pg_get_functiondef(sig::regprocedure);
  marker:='where me.actor_id=a and other.actor_id=p_subject';
  d:=replace(d,marker,marker||' and (app.is_friend(a,p_subject) or not exists(select 1 from app.challenge_community_publications_v1 pub where pub.challenge_id=me.challenge_id))');execute d;
 end loop;
 -- Explicit new envelopes. Existing stored report requests keep their meaning.
 d:=pg_get_functiondef('public.challenge_command_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'case op'||chr(10)||' when ''confirm_age''',
 'case op'||chr(10)||' when ''report_scoped'' then result:=public.challenge_report_scoped_v1(p_request_id,(p_payload->>''id'')::uuid,(p_payload->>''subject'')::uuid,p_payload->>''reason'');'||chr(10)||' when ''appeal'' then result:=public.challenge_appeal_v1(p_request_id);'||chr(10)||' when ''confirm_age''');
 d:=replace(d,'when ''report'' then array[''op'',''subject'',''reason'']',
 'when ''report_scoped'' then array[''op'',''id'',''subject'',''reason''] when ''appeal'' then array[''op''] when ''report'' then array[''op'',''subject'',''reason'']');execute d;
end $$;
-- Attempt budgets for guessing-sensitive lookup/redemption. Expected rejections
-- return a normal PostgREST error body/status, so the attempt counter commits.
-- Private implementations retain transactional errors and are not RPC-callable.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.challenge_mutate_v1(uuid,jsonb)'::regprocedure);
 execute replace(d,'public.challenge_mutate_v1(','app.challenge_mutate_unmetered_v1(');
 d:=pg_get_functiondef('public.challenge_redeem_link_v1(uuid,text)'::regprocedure);
 execute replace(d,'public.challenge_redeem_link_v1(','app.challenge_redeem_unmetered_v1(');
end $$;
create or replace function public.challenge_mutate_v1(p_request_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; code text;
begin
 if p_payload->>'op' is distinct from 'invite' then return app.challenge_mutate_unmetered_v1(p_request_id,p_payload); end if;
 a:=app.challenge_mutation_session_v1();
 if exists(select 1 from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id) then return app.challenge_mutate_unmetered_v1(p_request_id,p_payload); end if;
 if not app.challenge_quota_v1(a,'lookup',30,interval '1 minute') then return app.challenge_quota_error_v1('challenge_rate_limited'); end if;
 begin return app.challenge_mutate_unmetered_v1(p_request_id,p_payload);
 exception when sqlstate '42501' or sqlstate '22023' or invalid_text_representation then
  get stacked diagnostics code=message_text;
  return app.challenge_quota_error_v1(case when code like 'challenge_%' then code else 'challenge_invalid_request' end,'400');
 end;
end $$;
create or replace function public.challenge_redeem_link_v1(p_request_id uuid,p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=app.challenge_mutation_session_v1(); code text;
begin
 if exists(select 1 from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id) then return app.challenge_redeem_unmetered_v1(p_request_id,p_token); end if;
 if not app.challenge_quota_v1(a,'redemption',20,interval '1 hour') then return app.challenge_quota_error_v1('challenge_rate_limited'); end if;
 begin return app.challenge_redeem_unmetered_v1(p_request_id,p_token);
 exception when sqlstate '42501' or sqlstate '22023' or sqlstate '23505' then
  get stacked diagnostics code=message_text;
  return app.challenge_quota_error_v1(case when code like 'challenge_%' then code else 'challenge_link_unavailable' end,'400');
 end;
end $$;
-- No implicit public grants for helpers or service/operator operations.
do $$ declare f regprocedure; begin
 for f in select oid::regprocedure from pg_proc where pronamespace='app'::regnamespace and proname in (
 'challenge_community_member_state_v1','challenge_community_status_state_v1','challenge_community_revision_v1','challenge_community_eligible_v1','challenge_community_counts_v1',
 'challenge_quota_v1','challenge_quota_error_v1','challenge_request_quota_v1','challenge_require_support_v1','challenge_private_receipt_v1','challenge_mutate_unmetered_v1','challenge_redeem_unmetered_v1') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f); end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
 'challenge_capture_community_snapshot_v1','challenge_revoke_operator_v1','challenge_grant_support_v1','challenge_revoke_support_v1') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f); execute format('grant execute on function %s to service_role',f); end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
 'challenge_report_scoped_v1','challenge_support_reports_v1','challenge_support_suspend_v1','challenge_appeal_v1','challenge_support_appeals_v1','challenge_resolve_appeal_v1','challenge_own_appeals_v1') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f); execute format('grant execute on function %s to authenticated',f); end loop;
end $$;
-- Capacity limits current participants. Exited members retain their original
-- slots/returns until finality; replacement admission must not make settlement
-- impossible by exceeding the evaluator's former total-history array bound.
do $$ declare d text; marker text:='count_people>250'; begin
 d:=pg_get_functiondef('app.challenge_evaluate_policy_v1(text,jsonb,integer,integer,boolean)'::regprocedure);
 if position(marker in d)=0 then raise exception 'Unexpected community evaluator bound'; end if;
 execute replace(d,marker,'(count_people>250 and (pol->>''mode''<>''community'' or (select count(*) from jsonb_array_elements(p_people) item where item->''excluded''=''false''::jsonb)>250))');
end $$;
-- The account screen can show a durable, actor-only appeal receipt without
-- exposing the support operator or any other account's report/case metadata.
do $$ declare d text; marker text:='return jsonb_build_object('; begin
 d:=pg_get_functiondef('public.challenge_access_status_v1()'::regprocedure);
 if position(marker in d)=0 then raise exception 'Unexpected account status'; end if;
 execute replace(d,marker,marker||'''appeal_filed'',exists(select 1 from app.challenge_appeals_v1 ap join app.challenge_suspensions_v1 s on s.actor_id=ap.actor_id and s.recorded_at=ap.suspension_at where ap.actor_id=a and s.suspended),');
end $$;
