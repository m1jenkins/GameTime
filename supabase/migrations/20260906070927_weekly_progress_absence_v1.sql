-- An absent service observation basis is null, distinct from a service basis
-- that currently contains zero complete days. Client display totals never create
-- completeness authority. Preserve the existing private projection/privileges.
create or replace function app.weekly_projection_v1(c app.weekly_agreements,a uuid) returns jsonb
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
   'complete_day_count',case when exists(select 1 from app.weekly_revisions where challenge_id=c.id and actor_id=a) then (select count(*) from (select distinct on(day) document from app.weekly_revisions where challenge_id=c.id and actor_id=a order by day,revision desc) x where x.document->>'status'='complete') else null end,
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
