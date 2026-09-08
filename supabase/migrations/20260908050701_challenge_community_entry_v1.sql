-- One configurable community fixture; publication never accepts real settings.
create function public.challenge_publish_community_fixture_v1(p_request_id uuid,p_operator uuid,p_config jsonb,p_target bigint,p_minimum integer,p_capacity integer,p_fixture_only boolean)
returns uuid language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare n timestamptz; cfg jsonb; c uuid; terms jsonb; payload jsonb; saved app.challenge_requests_v1; begin
 perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;
 payload:=jsonb_build_object('op','publish_community_fixture','operator',p_operator,'config',p_config,'target',p_target,'minimum',p_minimum,'capacity',p_capacity,'fixture_only',p_fixture_only);
 select * into saved from app.challenge_requests_v1 where actor_id=p_operator and request_id=p_request_id;
 if found then
  if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;
  return (saved.response->>'id')::uuid;
 end if;
 if p_request_id is null or p_operator is null or p_fixture_only is distinct from true or p_target is null or p_target not between 1 and 1000000000
 or p_minimum is null or p_capacity is null or p_minimum not between 2 and 100 or p_capacity not between p_minimum and 100
 or not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and p_operator=any(actors)) then raise exception 'challenge_community_configuration_disabled' using errcode='42501';end if;
 n:=app.challenge_now_v1();cfg:=app.challenge_window_v1(p_config,n);
 if cfg ? 'distance_mm' then raise exception 'challenge_invalid_distance' using errcode='22023';end if;
 if exists(select 1 from app.challenge_lobbies_v1 where policy='community_steps_goal_v1' and status not in ('final','void','cancelled')) then raise exception 'challenge_one_community' using errcode='23505';end if;
 perform set_config('app.challenge_write_v1','on',true);c:=extensions.gen_random_uuid();
 insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,agreement_version)
 values(c,p_operator,'community_steps_goal_v1',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,'published_open',n,p_minimum,p_capacity,1);
 terms:=jsonb_build_object('policy','community_steps_goal_v1','source','fictional_steps_v1','mode','community','competition','goal','metric','steps','unit','whole_counts','config',cfg,
 'common_target',p_target,'minimum',p_minimum,'capacity',p_capacity,'settings_status','unapproved_fixture_only','simulation','nonredeemable','review_hours',48,'resolution_hours',72,
 'missing_rule','exclude_refund_minimum','exit_rule','exclude_refund_minimum','allocation_rule','return_qualifiers_split_misses_remainder_unallocated');
 insert into app.challenge_agreements_v1 values(c,1,terms,default,n);
 insert into app.challenge_requests_v1 values(p_operator,p_request_id,payload,jsonb_build_object('id',c),n);
 return c;
end $$;
create function public.challenge_discovery_fixture_v1(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;
 if p_enabled is null or (p_enabled and not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures)) then raise exception 'challenge_fixture_disabled' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);update app.challenge_runtime_v1 set discovery=p_enabled where singleton;
end $$;
create function public.challenge_community_catalog_v1() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app.challenge_session_v1();
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and discovery and fixtures) then return '[]';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'terms',a.terms,'digest',a.digest,'server_time',app.challenge_now_v1(),
 'joined_count',(select count(*) from app.challenge_members_v1 where challenge_id=c.id and exited_at is null))),'[]')
 from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 a on a.challenge_id=c.id and a.version=c.agreement_version
 where c.policy='community_steps_goal_v1' and c.status='published_open' and app.challenge_now_v1()<c.starts_at);
end $$;
create function public.challenge_join_community_v1(p_request_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; c app.challenge_lobbies_v1; a app.challenge_agreements_v1; saved app.challenge_requests_v1; response jsonb; n timestamptz; begin
 actor:=app.challenge_session_v1();
 select * into saved from app.challenge_requests_v1 where actor_id=actor and request_id=p_request_id;
 if found then if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object' or p_payload-array['op','id','digest','consent']<>'{}'
 or not(p_payload ?& array['op','id','digest','consent']) or p_payload->>'op'<>'join_community' or p_payload->'consent' is distinct from 'true'::jsonb then raise exception 'challenge_invalid_request' using errcode='22023';end if;
 perform app.challenge_admit_v1(actor);n:=app.challenge_now_v1();
 select * into c from app.challenge_lobbies_v1 where id=(p_payload->>'id')::uuid for update;
 select * into a from app.challenge_agreements_v1 where challenge_id=c.id and version=c.agreement_version;
 if c.policy is distinct from 'community_steps_goal_v1' or c.status<>'published_open' or n>=c.starts_at or p_payload->>'digest' is distinct from a.digest
 or exists(select 1 from app.challenge_members_v1 where challenge_id=c.id and actor_id=actor) then raise exception 'challenge_join_closed' using errcode='55000';end if;
 if (select count(*) from app.challenge_members_v1 where challenge_id=c.id and exited_at is null)>=c.capacity then raise exception 'challenge_capacity' using errcode='23505';end if;
 if not exists(select 1 from app.challenge_readiness_v1 where actor_id=actor and metric='steps' and recorded_at between n-interval '30 days' and n) then raise exception 'challenge_readiness_required' using errcode='42501';end if;
 perform app.challenge_slot_v1(actor,c);perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target) values(c.id,actor,true,(a.terms->>'common_target')::bigint);
 insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at) values(c.id,actor,'community','steps',c.starts_at,c.ends_at);
 insert into app.challenge_consents_v1 values(c.id,c.agreement_version,actor,a.digest,n);
 update app.challenge_lobbies_v1 set revision=revision+1 where id=c.id;
 response:=jsonb_build_object('id',c.id,'status','published_open','revision',c.revision+1);
 insert into app.challenge_requests_v1 values(actor,p_request_id,p_payload,response,n);return response;
end $$;

create or replace function public.challenge_detail_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; c app.challenge_lobbies_v1; hidden boolean; projection jsonb; begin
 a:=app.challenge_session_v1(); select * into c from app.challenge_lobbies_v1 where id=p_id;
 if not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_unavailable' using errcode='42501'; end if;
 hidden:=c.policy='community_steps_goal_v1' or not exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a and selected and exited_at is null) or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id<>a and (not app.is_active_actor(actor_id) or app.is_blocked_either_way(a,actor_id)));
 projection:=jsonb_build_object('id',c.id,'creator_id',case when c.policy<>'community_steps_goal_v1' and (not hidden or c.creator_id=a) then c.creator_id end,'policy',c.policy,'config',c.config,
  'counts',case when c.policy='community_steps_goal_v1' then jsonb_build_object('joined',(select count(*) from app.challenge_members_v1 where challenge_id=p_id and exited_at is null)) end,'status',c.status,'revision',c.revision,'agreement_version',c.agreement_version,'server_time',app.challenge_now_v1(),'social_hidden',hidden,
  'agreement',(select jsonb_build_object('digest',digest,'terms',case when not hidden or c.policy='community_steps_goal_v1' then terms end) from app.challenge_agreements_v1 where challenge_id=p_id and version=c.agreement_version),
  'members',(select coalesce(jsonb_agg(jsonb_build_object('actor_id',m.actor_id,'username',p.handle,'target',m.target,'selected',m.selected,'exited',m.exited_at is not null,
    'consented',exists(select 1 from app.challenge_consents_v1 where challenge_id=p_id and version=c.agreement_version and actor_id=m.actor_id),
    'fact',(select jsonb_build_object('value',value,'state',state,'recorded_at',recorded_at,'revision',revision) from app.challenge_facts_v1 where challenge_id=p_id and actor_id=m.actor_id order by revision desc limit 1)) order by m.actor_id),'[]')
    from app.challenge_members_v1 m join public.profiles p on p.id=m.actor_id where m.challenge_id=p_id and (not hidden or m.actor_id=a)),
  'notice',(select jsonb_build_object('revision',revision,'recorded_at',recorded_at,'review_by',review_by,'result',case when not hidden then result end) from app.challenge_notices_v1 where challenge_id=p_id order by revision desc limit 1),
  'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'reason',r.reason,'filed_at',r.filed_at,'resolve_by',r.resolve_by,'decision',s.decision) order by r.filed_at),'[]') from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=p_id and r.actor_id=a),
  'final',(select jsonb_build_object('recorded_at',recorded_at,'result',case when not hidden then result else jsonb_build_object('own',result->'participants'->a::text) end) from app.challenge_finals_v1 where challenge_id=p_id));
 return projection;
end $$;

create or replace function app.challenge_tick_v1(p_id uuid,p_safe_only boolean default false) returns text language plpgsql set search_path='' as $$
declare c app.challenge_lobbies_v1; n timestamptz; notice app.challenge_notices_v1; result jsonb; remaining integer; begin
 perform 1 from app.challenge_runtime_v1 where singleton for update;
 perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id=p_id) order by id for update;
 select * into c from app.challenge_lobbies_v1 where id=p_id for update; n:=app.challenge_now_v1();
 if c.id is null then raise exception 'challenge_unavailable' using errcode='22023'; end if;
 if exists(select 1 from app.challenge_finals_v1 where challenge_id=p_id) then return c.status; end if;
 perform set_config('app.challenge_write_v1','on',true);
 -- External legacy block/deletion may precede a Beta operation. End contact and
 -- participation conservatively before scoring; post-final records never change.
 update app.challenge_members_v1 m set exited_at=n where challenge_id=p_id and exited_at is null
  and (not app.is_active_actor(actor_id) or exists(select 1 from app.challenge_members_v1 other where other.challenge_id=p_id and app.is_blocked_either_way(m.actor_id,other.actor_id)));
 if c.agreement_version=0 then
  if c.status='cancelled' or n>=c.starts_at or not app.is_active_actor(c.creator_id) then
   update app.challenge_lobbies_v1 set status='cancelled',revision=revision+1 where id=p_id;
  end if;
  return (select status from app.challenge_lobbies_v1 where id=p_id);
 end if;
 select count(*) into remaining from app.challenge_slots_v1 s join app.challenge_members_v1 m using(challenge_id,actor_id) where s.challenge_id=p_id and m.exited_at is null;
 if c.status='published_open' and n<c.starts_at then return c.status;end if;
 if c.status='published_open' and remaining>=c.minimum then update app.challenge_lobbies_v1 set status='scheduled',revision=revision+1 where id=p_id;c.status:='scheduled';end if;
 if c.status='cancelled' or remaining<c.minimum or (c.status='consent_pending' and n>=c.starts_at) then
  perform app.challenge_finish_v1(p_id,app.challenge_evaluate_v1(p_id,true),case when c.status='cancelled' or c.status='consent_pending' then 'cancelled' else 'void' end);
  return (select status from app.challenge_lobbies_v1 where id=p_id);
 end if;
 if p_safe_only then return c.status; end if;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and processing and fixtures) then raise exception 'challenge_processing_paused' using errcode='42501'; end if;
 if c.status='scheduled' and n>=c.starts_at then update app.challenge_lobbies_v1 set status='active',revision=revision+1 where id=p_id; end if;
 if n>=c.ends_at and c.status in ('scheduled','active') then update app.challenge_lobbies_v1 set status='syncing',revision=revision+1 where id=p_id; end if;
 if n>c.ends_at+interval '48 hours' then
  result:=app.challenge_evaluate_v1(p_id);
  select * into notice from app.challenge_notices_v1 where challenge_id=p_id order by revision desc limit 1;
  if notice.challenge_id is null then
   insert into app.challenge_notices_v1 values(p_id,1,result,n,n+interval '48 hours');
   update app.challenge_lobbies_v1 set status='review',revision=revision+1 where id=p_id;
  elsif n>=notice.review_by and not exists(select 1 from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id
    where r.challenge_id=p_id and s.review_id is null and n<r.resolve_by) then
   perform app.challenge_finish_v1(p_id,result,case when result->>'outcome'='void' then 'void' else 'final' end);
  end if;
 end if;
 return (select status from app.challenge_lobbies_v1 where id=p_id);
end $$;

revoke all on function public.challenge_publish_community_fixture_v1(uuid,uuid,jsonb,bigint,integer,integer,boolean),public.challenge_discovery_fixture_v1(boolean) from public,anon,authenticated,service_role;
grant execute on function public.challenge_publish_community_fixture_v1(uuid,uuid,jsonb,bigint,integer,integer,boolean),public.challenge_discovery_fixture_v1(boolean) to service_role;
revoke all on function public.challenge_join_community_v1(uuid,jsonb),public.challenge_community_catalog_v1() from public,anon,authenticated,service_role;
grant execute on function public.challenge_join_community_v1(uuid,jsonb),public.challenge_community_catalog_v1() to authenticated;
