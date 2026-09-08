-- D134's finite thirteen-policy matrix. Existing steps and historical contracts
-- retain their frozen terms. Every source remains fictional and default-off.
create function app.challenge_policy_v1(p text) returns jsonb language plpgsql immutable set search_path='' as $$
declare mode text:=split_part(p,'_',1); metric text:=split_part(p,'_',2); competition text:=split_part(p,'_',3); begin
 if p is null or p<>mode||'_'||metric||'_'||competition||'_v1'
 or metric not in ('steps','exercise','distance','timed')
 or not ((mode='friend' and competition in ('goal','leaderboard')) or (mode='personal' and competition='goal') or (p='community_steps_goal_v1')) then
  raise exception 'challenge_invalid_policy' using errcode='22023'; end if;
 return jsonb_build_object('version',p,'mode',mode,'metric',metric,'competition',competition,
  'source','fictional_'||metric||'_v1','unit',case metric when 'steps' then 'whole_counts' when 'exercise' then 'integer_seconds' when 'distance' then 'integer_millimetres' else 'whole_elapsed_seconds' end,
  'comparator',case when competition='leaderboard' then case when metric='timed' then 'minimum' else 'maximum' end when metric='timed' then 'strict_less_than' else 'greater_or_equal' end);
end $$;
alter table app.challenge_lobbies_v1 drop constraint challenge_lobbies_v1_policy_check;
alter table app.challenge_lobbies_v1 add constraint challenge_lobbies_v1_policy_check check(app.challenge_policy_v1(policy) is not null);
alter table app.challenge_lobbies_v1 add column minimum integer not null default 2 check(minimum between 1 and 100);
alter table app.challenge_lobbies_v1 add column capacity integer not null default 6 check(capacity between 1 and 100 and capacity>=minimum);
alter table app.challenge_lobbies_v1 drop constraint challenge_lobbies_v1_status_check;
alter table app.challenge_lobbies_v1 add constraint challenge_lobbies_v1_status_check check(status in ('lobby_open','published_open','consent_pending','scheduled','active','syncing','review','final','cancelled','void'));
alter table app.challenge_readiness_v1 drop constraint challenge_readiness_v1_pkey;
alter table app.challenge_readiness_v1 drop constraint challenge_readiness_v1_source_check;
alter table app.challenge_readiness_v1 add column metric text not null default 'steps' check(metric in ('steps','exercise','distance','timed'));
alter table app.challenge_readiness_v1 add primary key(actor_id,metric);
alter table app.challenge_readiness_v1 add constraint challenge_readiness_source_v1 check(source='fictional_'||metric||'_v1');

create function public.challenge_readiness_metric_fixture_v1(p_actor uuid,p_metric text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and p_actor=any(actors)) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_readiness_v1(actor_id,recorded_at,source,metric) values(p_actor,app.challenge_now_v1(),'fictional_'||p_metric||'_v1',p_metric)
 on conflict(actor_id,metric) do update set recorded_at=excluded.recorded_at;
end $$;
create or replace function public.challenge_readiness_fixture_v1(p_actor uuid) returns void language sql security definer set search_path='' as $$
 select public.challenge_readiness_metric_fixture_v1(p_actor,'steps')
$$;
create or replace function app.challenge_slot_v1(a uuid,c app.challenge_lobbies_v1) returns void language plpgsql set search_path='' as $$
declare pol jsonb:=app.challenge_policy_v1(c.policy); begin
 if (select count(*) from app.challenge_slots_v1 where actor_id=a and challenge_id<>c.id)>=3 then raise exception 'challenge_unsettled_limit' using errcode='23505'; end if;
 if exists(select 1 from app.challenge_slots_v1 where actor_id=a and challenge_id<>c.id
  and ((pol->>'mode'='friend' and mode='friend' and metric=pol->>'metric') or (pol->>'mode'='community' and mode='community'))
  and tstzrange(starts_at,ends_at,'[)') && tstzrange(c.starts_at,c.ends_at,'[)')) then raise exception 'challenge_metric_overlap' using errcode='23505'; end if;
end $$;

create function app.challenge_evaluate_policy_v1(p_policy text,p_people jsonb,p_amount integer,p_minimum integer,p_force_void boolean default false)
returns jsonb language plpgsql immutable set search_path='' as $$
declare pol jsonb:=app.challenge_policy_v1(p_policy); x jsonb; people jsonb:='{}'; known integer:=0; winners integer:=0; misses integer:=0;
 active integer:=0; count_people integer; amount integer; total integer; unallocated integer; all_void boolean; status text; best bigint; qualifies boolean;
begin
 if jsonb_typeof(p_people) is distinct from 'array' or p_amount not between 100 and 50000 or p_amount%100<>0 then raise exception 'challenge_invalid_evaluation' using errcode='22023'; end if;
 count_people:=jsonb_array_length(p_people);
 if count_people>100 or (select count(distinct value->>'actor_id') from jsonb_array_elements(p_people))<>count_people
 or exists(select 1 from jsonb_array_elements(p_people) item where jsonb_typeof(item->'excluded') is distinct from 'boolean'
  or (pol->>'competition'='leaderboard' and item->'target' is distinct from 'null'::jsonb)
  or (pol->>'competition'='goal' and (item->>'target' is null or (item->>'target')::bigint<=0))
  or (item->>'state'='complete' and (item->>'value' is null or (item->>'value')::bigint<0))) then raise exception 'challenge_invalid_evaluation' using errcode='22023'; end if;
 for x in select value from jsonb_array_elements(p_people) loop
  if not (x->>'excluded')::boolean then
   active:=active+1;
   if x->>'state'='complete' then
    known:=known+1;
    if pol->>'competition'='leaderboard' then
     if best is null or (pol->>'metric'='timed' and (x->>'value')::bigint<best) or (pol->>'metric'<>'timed' and (x->>'value')::bigint>best) then best:=(x->>'value')::bigint; end if;
    else
     qualifies:=case when pol->>'metric'='timed' then (x->>'value')::bigint<(x->>'target')::bigint else (x->>'value')::bigint>=(x->>'target')::bigint end;
     if qualifies then winners:=winners+1; else misses:=misses+1; end if;
    end if;
   end if;
  end if;
 end loop;
 if pol->>'competition'='leaderboard' then
  select count(*) into winners from jsonb_array_elements(p_people) item where not (item->>'excluded')::boolean and item->>'state'='complete' and (item->>'value')::bigint=best;
 end if;
 all_void:=p_force_void or known<p_minimum or (pol->>'competition'='leaderboard' and active<>known);
 total:=p_amount*count_people;
 unallocated:=case when all_void then 0 when pol->>'competition'='leaderboard' then (known*p_amount)%winners when winners=0 then misses*p_amount else (misses*p_amount)%winners end;
 for x in select value from jsonb_array_elements(p_people) loop
  qualifies:=case when pol->>'competition'='leaderboard' then (x->>'value')::bigint=best when pol->>'metric'='timed' then (x->>'value')::bigint<(x->>'target')::bigint else (x->>'value')::bigint>=(x->>'target')::bigint end;
  if all_void then status:='void'; amount:=p_amount;
  elsif (x->>'excluded')::boolean or x->>'state' is distinct from 'complete' then status:='excluded'; amount:=p_amount;
  elsif qualifies then
   status:=case when pol->>'competition'='leaderboard' then 'winner' else 'met' end;
   amount:=case when pol->>'competition'='leaderboard' then known*p_amount/winners else p_amount+(misses*p_amount)/winners end;
  else status:=case when pol->>'competition'='leaderboard' then 'placed' else 'missed' end; amount:=0; end if;
  people:=people||jsonb_build_object(x->>'actor_id',jsonb_build_object('status',status,'returned_cents',amount));
 end loop;
 return jsonb_build_object('outcome',case when all_void then 'void' else 'scored' end,'participants',people,'entry_cents',total,'unallocated_cents',unallocated,'simulation','nonredeemable');
end $$;
create or replace function app.challenge_evaluate_v1(p_id uuid,p_force_void boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare c app.challenge_lobbies_v1; people jsonb; begin
 select * into c from app.challenge_lobbies_v1 where id=p_id;
 select coalesce(jsonb_agg(jsonb_build_object('actor_id',p.actor_id,'target',p.target,
  'excluded',p.exited_at is not null or not app.is_active_actor(p.actor_id) or exists(select 1 from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=p_id and r.actor_id=p.actor_id and (s.decision='exclude' or (s.review_id is null and app.challenge_now_v1()>=r.resolve_by))),
  'state',f.state,'value',f.value) order by p.actor_id),'[]') into people
 from app.challenge_slots_v1 slot join app.challenge_members_v1 p using(challenge_id,actor_id)
 left join lateral(select * from app.challenge_facts_v1 where challenge_id=p_id and actor_id=p.actor_id order by revision desc limit 1) f on true
 where slot.challenge_id=p_id;
 return app.challenge_evaluate_policy_v1(c.policy,people,(c.config->>'amount_cents')::integer,c.minimum,p_force_void);
end $$;

create or replace function app.challenge_window_v1(j jsonb,n timestamptz) returns jsonb language plpgsql set search_path='' set timezone='UTC' as $$
declare d date; count_days integer; z text; amount integer; s timestamptz; e timestamptz; begin
 if jsonb_typeof(j) is distinct from 'object' or j-array['start_date','days','timezone','amount_cents','distance_mm']<>'{}'
  or not(j ?& array['start_date','days','timezone','amount_cents'])
  or j->>'days' !~ '^[0-9]+$' or j->>'amount_cents' !~ '^[0-9]+$'
  or j->>'start_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'challenge_invalid_window' using errcode='22023'; end if;
 if j ? 'distance_mm' and (jsonb_typeof(j->'distance_mm') is distinct from 'number' or j->>'distance_mm' !~ '^[0-9]+$' or (j->>'distance_mm')::numeric not between 1 and 1000000000) then raise exception 'challenge_invalid_distance' using errcode='22023'; end if;
 d:=(j->>'start_date')::date; count_days:=(j->>'days')::integer; z:=j->>'timezone'; amount:=(j->>'amount_cents')::integer;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=z) or count_days not between 1 and 30
 or amount not between 100 and 50000 or amount%100<>0 then raise exception 'challenge_invalid_window' using errcode='22023'; end if;
 if d-(n at time zone z)::date not between 2 and 30 then raise exception 'challenge_invalid_lead' using errcode='22023'; end if;
 s:=d::timestamp at time zone z; e:=(d+count_days)::timestamp at time zone z;
 return j||jsonb_build_object('starts_at',s,'ends_at',e,'sync_by',e+interval '24 hours','corrections_by',e+interval '48 hours','notice_due',e+interval '72 hours');
end $$;

create or replace function public.challenge_mutate_v1(p_request_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare a uuid; op text; c app.challenge_lobbies_v1; member app.challenge_members_v1; saved app.challenge_requests_v1;
 n timestamptz; target_actor uuid; cid uuid; result jsonb; cfg jsonb; terms jsonb; ag app.challenge_agreements_v1;
 roster uuid[]; x uuid; notice app.challenge_notices_v1; allowed text[]; pol jsonb; policy_name text;
begin
 if p_request_id is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>16384 then
  raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 a:=app.challenge_session_v1(); op:=p_payload->>'op';
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then
  if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return saved.response;
 end if;
 allowed:=case op
 when 'create' then array['op','config','policy']
 when 'configure' then array['op','id','revision','config']
 when 'invite' then array['op','id','revision','username']
 when 'target' then array['op','id','revision','target']
 when 'select' then array['op','id','revision','actor_id','selected']
 when 'freeze' then array['op','id','revision']
 when 'reopen' then array['op','id','revision']
 when 'consent' then array['op','id','revision','digest','consent']
 when 'leave' then array['op','id','revision']
 when 'cancel' then array['op','id','revision']
 when 'review' then array['op','id','revision','notice_revision','reason'] end;
 if allowed is null or p_payload-allowed<>'{}' or not(p_payload ?& (case when op='create' then array['op','config'] else allowed end)) then raise exception 'challenge_invalid_request' using errcode='22023'; end if;
 perform set_config('app.challenge_write_v1','on',true); n:=app.challenge_now_v1();
 if op='create' then
  perform app.challenge_admit_v1(a);
  if (select count(*) from app.challenge_lobbies_v1 where creator_id=a and status='lobby_open')>=10 then raise exception 'challenge_lobby_limit' using errcode='23505'; end if;
  policy_name:=coalesce(p_payload->>'policy','friend_steps_goal_v1'); pol:=app.challenge_policy_v1(policy_name);
  if pol->>'mode'='community' then raise exception 'challenge_operator_required' using errcode='42501'; end if;
  cfg:=app.challenge_window_v1(p_payload->'config',n); cid:=extensions.gen_random_uuid();
  if (pol->>'metric'='timed')<>(cfg ? 'distance_mm') then raise exception 'challenge_distance_required_for_timed' using errcode='22023'; end if;
  insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity)
   values(cid,a,policy_name,cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,'lobby_open',n,case when pol->>'mode'='personal' then 1 else 2 end,case when pol->>'mode'='personal' then 1 else 6 end);
  insert into app.challenge_members_v1(challenge_id,actor_id,selected) values(cid,a,true);
 else
  cid:=(p_payload->>'id')::uuid;
  -- Bound participants are known only from persisted membership, never a caller roster.
  perform id from public.profiles where id in(select actor_id from app.challenge_members_v1 where challenge_id=cid) order by id for update;
  a:=app.challenge_session_v1();
  select * into c from app.challenge_lobbies_v1 where id=cid for update;
  select * into member from app.challenge_members_v1 where challenge_id=cid and actor_id=a;
  if c.id is null or member.actor_id is null then raise exception 'challenge_unavailable' using errcode='42501'; end if;
  if c.revision is distinct from (p_payload->>'revision')::bigint then raise exception 'challenge_stale' using errcode='40001'; end if;
  n:=app.challenge_now_v1(); pol:=app.challenge_policy_v1(c.policy);
  if op in ('invite','select') and pol->>'mode'<>'friend' then raise exception 'challenge_friend_only' using errcode='22023'; end if;
  if op not in ('leave','cancel','review') then
   perform app.challenge_admit_v1(a);
   if member.exited_at is not null or not app.is_active_actor(c.creator_id)
    or exists(select 1 from app.challenge_members_v1 p where p.challenge_id=cid and p.exited_at is null and app.is_blocked_either_way(a,p.actor_id)) then
     raise exception 'challenge_unavailable' using errcode='42501'; end if;
  end if;
  if op in ('configure','invite','target','select','freeze') and (c.status<>'lobby_open' or n>=c.starts_at) then raise exception 'challenge_lobby_closed' using errcode='55000'; end if;
  if op in ('configure','invite','select','freeze','reopen','cancel') and a<>c.creator_id then raise exception 'challenge_creator_required' using errcode='42501'; end if;
  if op='configure' then
   cfg:=app.challenge_window_v1(p_payload->'config',c.created_at);
   update app.challenge_lobbies_v1 set config=cfg,starts_at=(cfg->>'starts_at')::timestamptz,ends_at=(cfg->>'ends_at')::timestamptz where id=cid;
  elsif op='invite' then
   select id into target_actor from public.profiles where lower(handle)=lower(p_payload->>'username') and app.is_active_actor(id);
   if target_actor is null or not app.is_friend(a,target_actor) or app.is_blocked_either_way(a,target_actor) then raise exception 'challenge_friend_unavailable' using errcode='42501'; end if;
   if (select count(*) from app.challenge_members_v1 where challenge_id=cid)>=30 then raise exception 'challenge_entrant_limit' using errcode='23505'; end if;
   insert into app.challenge_members_v1(challenge_id,actor_id) values(cid,target_actor) on conflict do nothing;
  elsif op='target' then
   if pol->>'competition'='leaderboard' then raise exception 'challenge_leaderboard_has_no_target' using errcode='22023'; end if;
   if jsonb_typeof(p_payload->'target') is distinct from 'number' or p_payload->>'target' !~ '^[0-9]+$'
    or (p_payload->>'target')::numeric not between 1 and 1000000000 then raise exception 'challenge_invalid_target' using errcode='22023'; end if;
   update app.challenge_members_v1 set target=(p_payload->>'target')::bigint where challenge_id=cid and actor_id=a;
  elsif op='select' then
   target_actor:=(p_payload->>'actor_id')::uuid;
   if jsonb_typeof(p_payload->'selected') is distinct from 'boolean' or target_actor=a then raise exception 'challenge_invalid_selection' using errcode='22023'; end if;
   update app.challenge_members_v1 set selected=(p_payload->>'selected')::boolean where challenge_id=cid and actor_id=target_actor and exited_at is null;
   if not found then raise exception 'challenge_entrant_unavailable' using errcode='22023'; end if;
   if (select count(*) from app.challenge_members_v1 where challenge_id=cid and selected and exited_at is null)>6 then raise exception 'challenge_capacity' using errcode='23505'; end if;
  elsif op='freeze' then
   select array_agg(actor_id order by actor_id) into roster from app.challenge_members_v1 where challenge_id=cid and selected and exited_at is null;
   if cardinality(roster) not between c.minimum and c.capacity or not(a=any(roster)) or exists(select 1 from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster) and ((pol->>'competition'='goal' and target is null) or (pol->>'competition'='leaderboard' and target is not null))) then raise exception 'challenge_incomplete_roster' using errcode='22023'; end if;
   foreach x in array roster loop
    perform app.challenge_admit_v1(x);
    if not app.is_active_actor(x) or exists(select 1 from unnest(roster) y where app.is_blocked_either_way(x,y)) then raise exception 'challenge_participant_unavailable' using errcode='42501'; end if;
    perform app.challenge_slot_v1(x,c);
    insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at) values(cid,x,pol->>'mode',pol->>'metric',c.starts_at,c.ends_at);
   end loop;
   select jsonb_build_object('policy',c.policy,'source',pol->>'source','mode',pol->>'mode','competition',pol->>'competition',
    'metric',pol->>'metric','unit',pol->>'unit','config',c.config,'version',c.agreement_version+1,
    'participants',jsonb_agg(jsonb_build_object('actor_id',actor_id,'target',target) order by actor_id),
    'simulation','nonredeemable','review_hours',48,'resolution_hours',72,
    'missing_rule',case when pol->>'competition'='leaderboard' then 'void_if_any_unresolved' else 'exclude_refund_minimum' end,'exit_rule','exclude_refund_minimum','minimum',c.minimum,
    'allocation_rule',case when pol->>'competition'='leaderboard' then 'co_winners_split_active_pool_remainder_unallocated' else 'return_qualifiers_split_misses_remainder_unallocated' end) into terms
    from app.challenge_members_v1 where challenge_id=cid and actor_id=any(roster);
   insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at) values(cid,c.agreement_version+1,terms,n);
   update app.challenge_lobbies_v1 set status='consent_pending',agreement_version=agreement_version+1 where id=cid;
  elsif op='reopen' then
   if c.status not in ('consent_pending','scheduled') or n>=c.starts_at then raise exception 'challenge_cannot_reopen' using errcode='55000'; end if;
   delete from app.challenge_slots_v1 where challenge_id=cid;
   update app.challenge_lobbies_v1 set status='lobby_open' where id=cid;
  elsif op='consent' then
   select * into ag from app.challenge_agreements_v1 where challenge_id=cid and version=c.agreement_version;
   if c.status<>'consent_pending' or n>=c.starts_at or not member.selected or member.exited_at is not null
    or p_payload->'consent' is distinct from 'true'::jsonb or p_payload->>'digest' is distinct from ag.digest then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
   if not exists(select 1 from app.challenge_readiness_v1 where actor_id=a and metric=pol->>'metric' and recorded_at between n-(case when pol->>'metric'='timed' then interval '90 days' else interval '30 days' end) and n) then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
   insert into app.challenge_consents_v1 values(cid,c.agreement_version,a,ag.digest,n) on conflict do nothing;
   if not exists(select 1 from app.challenge_slots_v1 p where p.challenge_id=cid and not exists(select 1 from app.challenge_consents_v1 s where s.challenge_id=cid and s.version=c.agreement_version and s.actor_id=p.actor_id)) then
    update app.challenge_lobbies_v1 set status='scheduled' where id=cid;
   end if;
  elsif op in ('leave','cancel') then
   if c.status in ('final','cancelled','void') then raise exception 'challenge_already_closed' using errcode='55000'; end if;
   if op='cancel' and n>=c.starts_at then raise exception 'challenge_use_leave' using errcode='55000'; end if;
   insert into app.challenge_exits_v1 values(p_request_id,cid,a,op,n);
   update app.challenge_members_v1 set exited_at=n where challenge_id=cid and actor_id=a;
   if op='cancel' then
    update app.challenge_lobbies_v1 set status='cancelled' where id=cid;
   elsif c.status='lobby_open' then
    update app.challenge_members_v1 set selected=false where challenge_id=cid and actor_id=a;
    if a=c.creator_id then update app.challenge_lobbies_v1 set status='cancelled' where id=cid; end if;
   end if;
  elsif op='review' then
   select * into notice from app.challenge_notices_v1 where challenge_id=cid order by revision desc limit 1;
   if c.status<>'review' or n>=notice.review_by or (p_payload->>'notice_revision')::integer is distinct from notice.revision
    or not exists(select 1 from app.challenge_slots_v1 where challenge_id=cid and actor_id=a)
    or p_payload->>'reason' not in ('wrong_total','missing_activity','wrong_result') then raise exception 'challenge_review_closed' using errcode='55000'; end if;
   insert into app.challenge_reviews_v1 values(p_request_id,cid,notice.revision,a,p_payload->>'reason',n,n+interval '72 hours');
  end if;
  update app.challenge_lobbies_v1 set revision=revision+1 where id=cid;
 end if;
 select jsonb_build_object('id',id,'revision',revision,'status',status) into result from app.challenge_lobbies_v1 where id=cid;
 insert into app.challenge_requests_v1 values(a,p_request_id,p_payload,result,n);
 return result;
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

revoke all on function app.challenge_policy_v1(text),app.challenge_evaluate_policy_v1(text,jsonb,integer,integer,boolean) from public,anon,authenticated,service_role;
revoke all on function public.challenge_readiness_metric_fixture_v1(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.challenge_readiness_metric_fixture_v1(uuid,text) to service_role;
