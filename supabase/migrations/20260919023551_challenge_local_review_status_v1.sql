-- Local service-only monitoring. No assignments, decisions, grants or worker
-- state are changed. Counts span all saved cases, not the worker fixture scope.
create function public.challenge_local_review_status_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 server_now timestamptz := clock_timestamp();
 n timestamptz := app.challenge_now_v1();
 worker jsonb;
 response jsonb;
begin
 perform app.duel_require_service_v1();
 worker := public.challenge_local_worker_status_v1();
 with operators as materialized (
  -- Mirror account/session admission without impersonating an operator or
  -- writing the human read audit. A live session is not staffed availability
  -- or proof that a particular token will authorize a subsequent request.
  select g.actor_id as id from (
   select actor_id from app.challenge_operator_grants_v1 where capability='review' and expires_at>n
   union select actor_id from app.challenge_support_grants_v1 where expires_at>n
  ) g
  where not app.challenge_actor_unavailable_v1(g.actor_id)
   and exists(select 1 from auth.sessions s where s.user_id=g.actor_id
    and (s.not_after is null or s.not_after>server_now))
 ), reviews as materialized (
  select r.id,r.challenge_id,r.resolve_by
  from app.challenge_reviews_v1 r
  where not exists(select 1 from app.challenge_resolutions_v1 d where d.review_id=r.id)
   and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=r.challenge_id)
 ), review_grants as materialized (
  select r.id,g.expires_at from reviews r
  join app.challenge_operator_grants_v1 g on g.challenge_id=r.challenge_id and g.capability='review'
  join operators o on o.id=g.actor_id
  where g.expires_at>n and r.resolve_by>n
   -- Any membership disqualifies, including unselected or exited membership.
   and not exists(select 1 from app.challenge_members_v1 m
    where m.challenge_id=r.challenge_id and m.actor_id=g.actor_id)
 ), appeals as materialized (
  select a.id,a.actor_id,a.suspension_at,a.filed_at from app.challenge_appeals_v1 a
  where not exists(select 1 from app.challenge_appeal_decisions_v1 d where d.appeal_id=a.id)
 ), appeal_grants as materialized (
  select a.id,g.expires_at from appeals a
  join app.challenge_suspensions_v1 s on s.actor_id=a.actor_id
   and s.suspended and s.recorded_at=a.suspension_at
  join app.challenge_support_grants_v1 g on g.actor_id<>a.actor_id and g.actor_id<>s.operator_id
  join operators o on o.id=g.actor_id
  where g.expires_at>n
 )
 select jsonb_build_object(
  'server_time',server_now,
  'evaluated_at',n,
  -- Do not inherit healthy_empty when runtime/fixture scope hides work.
  'monitoring_state',case
   when n is null or worker->>'fixtures_enabled' is null or worker->>'processing_paused' is null then 'unavailable'
   when (worker->>'fixtures_enabled')::boolean=false then 'disabled'
   when (worker->>'processing_paused')::boolean then 'paused'
   else 'available' end,
  'outstanding_review_count',(select count(*) from reviews),
  'reviews_without_eligible_operator_count',case when n is not null then
   (select count(*) from reviews r where not exists(select 1 from review_grants g where g.id=r.id)) end,
  'earliest_review_resolve_by',(select min(resolve_by) from reviews),
  'next_review_grant_expires_at',(select min(expires_at) from review_grants),
  'pending_appeal_count',(select count(*) from appeals),
  'appeals_without_eligible_operator_count',case when n is not null then
   (select count(*) from appeals a where not exists(select 1 from appeal_grants g where g.id=a.id)) end,
  'oldest_pending_appeal_at',(select min(filed_at) from appeals),
  'next_appeal_grant_expires_at',(select min(expires_at) from appeal_grants)
 ) into response;
 return response;
end $$;

revoke all on function public.challenge_local_review_status_v1() from public,anon,authenticated,service_role;
grant execute on function public.challenge_local_review_status_v1() to service_role;
comment on function public.challenge_local_review_status_v1() is
 'Aggregate local authorization eligibility only, not staffed support. Undecided nonfinal reviews include elapsed resolution windows (no eligible decider); all undecided appeals remain visible, including unmatched suspensions. Expirations cover only currently eligible grants for pending cases. Read alongside existing worker and overdue monitoring. No appeal response deadline is defined.';
