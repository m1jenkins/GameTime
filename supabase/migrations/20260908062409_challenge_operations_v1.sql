-- Default-off local operations: minimum-data overdue monitoring, idempotent
-- bounded scheduler passes, scoped report reads and explicit operator closure.
create table app.challenge_worker_runs_v1(id uuid primary key,payload jsonb not null,result jsonb not null,recorded_at timestamptz not null);
alter table app.challenge_worker_runs_v1 enable row level security;
revoke all on app.challenge_worker_runs_v1 from public,anon,authenticated,service_role;
create trigger challenge_worker_runs_immutable before insert or update or delete on app.challenge_worker_runs_v1 for each row execute function app.challenge_entry_guard_v1();
create trigger challenge_worker_runs_no_truncate before truncate on app.challenge_worker_runs_v1 for each statement execute function app.challenge_entry_guard_v1();
create function app.challenge_work_v1() returns table(id uuid,status text,due_at timestamptz,notice_overdue boolean,review_overdue boolean) language sql stable set search_path='' as $$
 select c.id,c.status,
 case when exists(select 1 from app.challenge_members_v1 p where p.challenge_id=c.id and p.selected and p.exited_at is null and
  (app.challenge_actor_unavailable_v1(p.actor_id) or exists(select 1 from app.challenge_members_v1 other where other.challenge_id=c.id and other.selected and other.exited_at is null and app.is_blocked_either_way(p.actor_id,other.actor_id)))) then app.challenge_now_v1()
 when c.status in ('lobby_open','published_open','consent_pending','scheduled') then c.starts_at
 when c.status='active' then c.ends_at
 when c.status='syncing' then c.ends_at+interval '48 hours 1 microsecond'
 when c.status='review' then case when exists(select 1 from app.challenge_reviews_v1 r join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.decision='exclude' and s.recorded_at>n.recorded_at) then app.challenge_now_v1()
 else greatest(n.review_by,(select max(r.resolve_by) from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.review_id is null)) end
 else app.challenge_now_v1() end,
 n.challenge_id is null and app.challenge_now_v1()>c.ends_at+interval '72 hours',
 exists(select 1 from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=c.id and s.review_id is null and app.challenge_now_v1()>=r.resolve_by)
 from app.challenge_lobbies_v1 c left join lateral(select * from app.challenge_notices_v1 where challenge_id=c.id order by revision desc limit 1)n on true
 where not exists(select 1 from app.challenge_finals_v1 where challenge_id=c.id)
 and c.status not in ('final','void')
 and exists(select 1 from app.challenge_runtime_v1 r where r.singleton and r.fixtures and c.creator_id=any(r.actors))
$$;
create function public.challenge_operations_status_v1() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1();
 return jsonb_build_object('server_time',app.challenge_now_v1(),
 'gates',(select to_jsonb(r)-'actors'-'fictional_now' from app.challenge_runtime_v1 r where singleton),
 'due_count',(select count(*) from app.challenge_work_v1() where due_at<=app.challenge_now_v1()),
 'notice_overdue_count',(select count(*) from app.challenge_work_v1() where notice_overdue),
 'review_overdue_count',(select count(*) from app.challenge_work_v1() where review_overdue),
 'oldest_due',(select min(due_at) from app.challenge_work_v1()),
 'recent_failures',(select coalesce(sum((result->>'failed_count')::integer),0) from app.challenge_worker_runs_v1 where recorded_at>=app.challenge_now_v1()-interval '24 hours'));
end $$;
create function public.challenge_run_batch_v1(p_run_id uuid,p_limit integer default 20) returns jsonb language plpgsql security definer set search_path='' as $$
declare saved app.challenge_worker_runs_v1;payload jsonb:=jsonb_build_object('version','challenge_batch_v1','limit',p_limit);item record;processed jsonb:='[]';failed integer:=0;outcome text;response jsonb;begin
 perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;
 select * into saved from app.challenge_worker_runs_v1 where id=p_run_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.result;end if;
 if p_run_id is null or p_limit is null or p_limit not between 1 and 50 then raise exception 'challenge_invalid_batch' using errcode='22023';end if;
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and fixtures) then raise exception 'challenge_fixture_disabled' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);
 for item in select * from app.challenge_work_v1() where due_at<=app.challenge_now_v1() order by due_at,id limit p_limit loop
  begin
   outcome:=app.challenge_tick_v1(item.id,not (select processing from app.challenge_runtime_v1 where singleton));
   processed:=processed||jsonb_build_array(jsonb_build_object('id',item.id,'status',outcome));
  exception when others then
   failed:=failed+1;
   -- SQLSTATE only. Never persist SQLERRM, raw records or request contents.
   processed:=processed||jsonb_build_array(jsonb_build_object('id',item.id,'error_code',sqlstate));
  end;
 end loop;
 response:=jsonb_build_object('run_id',p_run_id,'processed',processed,'failed_count',failed,'server_time',app.challenge_now_v1());
 insert into app.challenge_worker_runs_v1 values(p_run_id,payload,response,app.challenge_now_v1());return response;
end $$;
create function public.challenge_operator_reports_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;begin
 a:=app.challenge_session_v1();
 if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='moderate' and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_operator_required' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,jsonb_build_object('op','read_reports','id',p_id),app.challenge_now_v1());
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'subject',r.subject,'reason',r.reason,'created_at',r.created_at) order by r.created_at),'[]') from app.challenge_reports_v1 r
 where exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=r.reporter)
 and exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=r.subject));
end $$;
create function public.challenge_operator_close_v1(p_request_id uuid,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;c app.challenge_lobbies_v1;saved app.challenge_requests_v1;payload jsonb:=jsonb_build_object('op','close_community','id',p_id);response jsonb;begin
 a:=app.challenge_session_v1();
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='moderate' and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_operator_required' using errcode='42501';end if;
 select * into c from app.challenge_lobbies_v1 where id=p_id;
 if c.policy is distinct from 'community_steps_goal_v1' or c.status in ('final','void','cancelled') then raise exception 'challenge_already_closed' using errcode='55000';end if;
 perform set_config('app.challenge_write_v1','on',true);
 perform app.challenge_finish_v1(p_id,app.challenge_evaluate_v1(p_id,true),'cancelled');
 response:=jsonb_build_object('id',p_id,'status','cancelled');
 insert into app.challenge_operator_audit_v1 values(p_request_id,a,payload,app.challenge_now_v1());
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,response,app.challenge_now_v1());return response;
end $$;
revoke all on function app.challenge_work_v1(),public.challenge_operations_status_v1(),public.challenge_run_batch_v1(uuid,integer),public.challenge_operator_reports_v1(uuid),public.challenge_operator_close_v1(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.challenge_operations_status_v1(),public.challenge_run_batch_v1(uuid,integer) to service_role;
grant execute on function public.challenge_operator_reports_v1(uuid),public.challenge_operator_close_v1(uuid,uuid) to authenticated;
