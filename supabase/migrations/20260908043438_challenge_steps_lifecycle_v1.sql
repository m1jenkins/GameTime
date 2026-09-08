-- Local fictional source and service-only worker. Gates cannot enable real ingestion.
create function public.challenge_runtime_v1(p_admission boolean,p_fixtures boolean,p_processing boolean,p_actors uuid[],p_now timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1();
 if p_admission is null or p_fixtures is null or p_processing is null or p_actors is null
 or cardinality(p_actors)>100 or array_position(p_actors,null) is not null or (p_now is not null and (not p_fixtures or not isfinite(p_now))) then
  raise exception 'challenge_invalid_runtime' using errcode='22023'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 update app.challenge_runtime_v1 set admission=p_admission,fixtures=p_fixtures,processing=p_processing,actors=p_actors,fictional_now=p_now where singleton;
end $$;
create function public.challenge_readiness_fixture_v1(p_actor uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and p_actor=any(actors)) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_readiness_v1 values(p_actor,app.challenge_now_v1(),'fictional_steps_v1')
 on conflict(actor_id) do update set recorded_at=excluded.recorded_at;
end $$;
create function public.challenge_capture_fixture_v1(p_request_id uuid,p_id uuid,p_actor uuid,p_value bigint,p_state text)
returns integer language plpgsql security definer set search_path='' as $$
declare c app.challenge_lobbies_v1; prior app.challenge_facts_v1; r integer; n timestamptz; begin
 perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;
 select * into prior from app.challenge_facts_v1 where request_id=p_request_id;
 if found then
  if (prior.challenge_id,prior.actor_id,prior.value,prior.state) is distinct from (p_id,p_actor,p_value,p_state) then raise exception 'challenge_request_conflict' using errcode='22023'; end if;
  return prior.revision;
 end if;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures and p_actor=any(actors)) then raise exception 'challenge_fixture_disabled' using errcode='42501'; end if;
 select * into c from app.challenge_lobbies_v1 where id=p_id for update; n:=app.challenge_now_v1();
 select coalesce(max(revision),0)+1 into r from app.challenge_facts_v1 where challenge_id=p_id and actor_id=p_actor;
 if p_request_id is null or p_state is null or p_state not in ('complete','unresolved','deleted') or (p_state='complete')<>(p_value is not null)
 or p_value<0 or p_value>1000000000 or r>128 or c.status not in ('scheduled','active','syncing') or n<c.starts_at
 or n>c.ends_at+(case when r=1 then interval '24 hours' else interval '48 hours' end)
 or not exists(select 1 from app.challenge_slots_v1 where challenge_id=p_id and actor_id=p_actor) then raise exception 'challenge_invalid_fact' using errcode='22023'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_facts_v1 values(p_id,p_actor,r,p_value,p_state,n,p_request_id);
 update app.challenge_lobbies_v1 set revision=revision+1 where id=p_id;
 return r;
end $$;

-- Pure policy evaluator: supplied facts are fictional server records only.
-- No client completeness assertion or inferred miss enters this function.
create function app.challenge_evaluate_steps_v1(p_people jsonb,p_amount integer,p_force_void boolean default false)
returns jsonb language plpgsql immutable set search_path='' as $$
declare x jsonb; people jsonb:='{}'; known integer:=0; met integer:=0; misses integer:=0;
 count_people integer; amount integer; total integer; unallocated integer; all_void boolean; status text; begin
 count_people:=jsonb_array_length(p_people);
 if count_people not between 2 and 6 or p_amount not between 100 and 50000 or p_amount%100<>0
  or (select count(distinct value->>'actor_id') from jsonb_array_elements(p_people))<>count_people then raise exception 'challenge_invalid_evaluation' using errcode='22023'; end if;
 for x in select value from jsonb_array_elements(p_people) loop
  if x->>'state'='complete' and not (x->>'excluded')::boolean then
   known:=known+1;
   if (x->>'value')::bigint >= (x->>'target')::bigint then met:=met+1; else misses:=misses+1; end if;
  end if;
 end loop;
 all_void:=p_force_void or known<2; total:=p_amount*count_people;
 unallocated:=case when all_void then 0 when met=0 then misses*p_amount else (misses*p_amount)%met end;
 for x in select value from jsonb_array_elements(p_people) loop
  if all_void then status:='void'; amount:=p_amount;
  elsif (x->>'excluded')::boolean or x->>'state' is distinct from 'complete' then status:='excluded'; amount:=p_amount;
  elsif (x->>'value')::bigint >= (x->>'target')::bigint then status:='met'; amount:=p_amount+(misses*p_amount)/met;
  else status:='missed'; amount:=0; end if;
  people:=people||jsonb_build_object(x->>'actor_id',jsonb_build_object('status',status,'returned_cents',amount));
 end loop;
 return jsonb_build_object('outcome',case when all_void then 'void' else 'scored' end,'participants',people,'entry_cents',total,'unallocated_cents',unallocated,'simulation','nonredeemable');
end $$;
create function app.challenge_evaluate_v1(p_id uuid,p_force_void boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare c app.challenge_lobbies_v1; people jsonb; begin
 select * into c from app.challenge_lobbies_v1 where id=p_id;
 select jsonb_agg(jsonb_build_object('actor_id',p.actor_id,'target',(t->>'target')::bigint,
  'excluded',p.exited_at is not null or not app.is_active_actor(p.actor_id) or exists(select 1 from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id
    where r.challenge_id=p_id and r.actor_id=p.actor_id and (s.decision='exclude' or (s.review_id is null and app.challenge_now_v1()>=r.resolve_by))),
  'state',f.state,'value',f.value) order by p.actor_id) into people
 from app.challenge_agreements_v1 ag cross join lateral jsonb_array_elements(ag.terms->'participants') t
 join app.challenge_members_v1 p on p.challenge_id=p_id and p.actor_id=(t->>'actor_id')::uuid
 left join lateral(select * from app.challenge_facts_v1 where challenge_id=p_id and actor_id=p.actor_id order by revision desc limit 1) f on true
 where ag.challenge_id=p_id and ag.version=c.agreement_version;
 return app.challenge_evaluate_steps_v1(people,(c.config->>'amount_cents')::integer,p_force_void);
end $$;
create function app.challenge_finish_v1(p_id uuid,p_result jsonb,p_status text) returns void language plpgsql set search_path='' as $$
begin
 if exists(select 1 from app.challenge_finals_v1 where challenge_id=p_id) then return; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_finals_v1 select id,p_result,app.challenge_now_v1(),revision from app.challenge_lobbies_v1 where id=p_id;
 delete from app.challenge_slots_v1 where challenge_id=p_id;
 update app.challenge_lobbies_v1 set status=p_status,revision=revision+1 where id=p_id;
end $$;

create function app.challenge_tick_v1(p_id uuid,p_safe_only boolean default false) returns text language plpgsql set search_path='' as $$
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
 if c.status='cancelled' or remaining<2 or (c.status='consent_pending' and n>=c.starts_at) then
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
create function public.challenge_process_v1(p_id uuid) returns text language plpgsql security definer set search_path='' as $$
begin perform app.duel_require_service_v1(); return app.challenge_tick_v1(p_id); end $$;

-- A resolution needs an explicitly named, independent local operator. Assignment
-- and authenticated operator workflows are added in M6; this RPC is service only.
create function public.challenge_resolve_v1(p_review_id uuid,p_operator uuid,p_decision text) returns void language plpgsql security definer set search_path='' as $$
declare r app.challenge_reviews_v1; saved app.challenge_resolutions_v1; begin
 perform app.duel_require_service_v1(); perform 1 from app.challenge_runtime_v1 where singleton for update;
 select * into r from app.challenge_reviews_v1 where id=p_review_id;
 select * into saved from app.challenge_resolutions_v1 where review_id=p_review_id;
 if found then
  if (saved.operator_id,saved.decision) is distinct from (p_operator,p_decision) then raise exception 'challenge_resolution_conflict' using errcode='22023'; end if;
  return;
 end if;
 if r.id is null or p_operator is null or p_decision is null or p_decision not in ('upheld','exclude')
 or app.challenge_now_v1()>=r.resolve_by or exists(select 1 from app.challenge_members_v1 where challenge_id=r.challenge_id and actor_id=p_operator)
 or exists(select 1 from app.challenge_finals_v1 where challenge_id=r.challenge_id) then raise exception 'challenge_invalid_resolution' using errcode='22023'; end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_resolutions_v1 values(p_review_id,p_decision,p_operator,app.challenge_now_v1());
 update app.challenge_lobbies_v1 set revision=revision+1 where id=r.challenge_id;
end $$;

-- Exits trigger their own safe closure even when processing/admission is paused.
create function app.challenge_exit_reconcile_v1() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='challenge_exits_v1' then perform app.challenge_tick_v1(new.challenge_id,true); end if;
 return new;
end $$;
-- Deferred until the mutation's member/status updates have completed.
create constraint trigger challenge_exit_reconcile after insert on app.challenge_exits_v1
 deferrable initially deferred for each row execute function app.challenge_exit_reconcile_v1();

do $$ declare f regprocedure; begin
 for f in select oid::regprocedure from pg_proc where pronamespace='app'::regnamespace and proname like 'challenge_%_v1' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f); end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in ('challenge_runtime_v1','challenge_readiness_fixture_v1','challenge_capture_fixture_v1','challenge_process_v1','challenge_resolve_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
  execute format('grant execute on function %s to service_role',f);
 end loop;
end $$;
