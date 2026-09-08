-- Narrow, audited case context for an explicitly assigned independent reviewer.
-- Only normalized challenge facts, never Health samples, routes or source IDs.
create or replace function public.challenge_operator_cases_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;begin
 a:=app.challenge_session_v1();
 if app.challenge_actor_unavailable_v1(a) or not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='review' and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_operator_required' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,jsonb_build_object('op','read_cases','id',p_id),app.challenge_now_v1());
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'id',r.id,'actor_id',r.actor_id,'reason',r.reason,'filed_at',r.filed_at,'resolve_by',r.resolve_by,'decision',s.decision,
  'context',jsonb_strip_nulls(jsonb_build_object('policy',c.policy,'config',c.config,'digest',ag.digest,
   'target',case when c.policy not like '%leaderboard%' then m.target end,
   'fact',(select jsonb_build_object('value',f.value,'state',f.state,'revision',f.revision,'recorded_at',f.recorded_at) from app.challenge_facts_v1 f where f.challenge_id=p_id and f.actor_id=r.actor_id order by f.revision desc limit 1),
   'notice_revision',r.notice_revision,'provisional',n.result->'participants'->r.actor_id::text,
   'simulation','nonredeemable'))) order by r.filed_at,r.id),'[]')
 from app.challenge_reviews_v1 r join app.challenge_lobbies_v1 c on c.id=r.challenge_id
 join app.challenge_members_v1 m on m.challenge_id=c.id and m.actor_id=r.actor_id
 join app.challenge_agreements_v1 ag on ag.challenge_id=c.id and ag.version=c.agreement_version
 join app.challenge_notices_v1 n on n.challenge_id=c.id and n.revision=r.notice_revision
 left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=p_id);
end $$;
revoke all on function public.challenge_operator_cases_v1(uuid) from public,anon,service_role;
grant execute on function public.challenge_operator_cases_v1(uuid) to authenticated;
