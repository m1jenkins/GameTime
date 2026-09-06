-- Sharing is explicitly limited to the selected week. Public calls always use
-- server time; private injected clocks exist solely for rollback-only acceptance
-- checks. Exact committed receipts and safe revoke/decline/unfollow remain usable.


create function app.weekly_set_sharing_at_v1(p_request_id uuid,p_challenge_id uuid,p_friend_id uuid,p_enabled boolean,p_now timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; n timestamptz; begin
 a:=app.weekly_session_v1(array[p_friend_id]); p:=jsonb_build_object('op','weekly-display-sharing-v1','id',p_challenge_id,'friend',p_friend_id,'enabled',p_enabled);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if p_enabled is null or p_friend_id is null or p_friend_id=a or not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a and accepted_at is not null) then
  raise exception 'weekly_sharing_unavailable' using errcode='42501'; end if;
 n:=coalesce(p_now,clock_timestamp());
 if p_enabled and not exists(select 1 from app.weekly_agreements where id=p_challenge_id and ends_at>n) then
  raise exception 'weekly_sharing_expired' using errcode='55000'; end if;
 if p_enabled and (not app.is_active_actor(p_friend_id) or not app.is_friend(a,p_friend_id) or app.is_blocked_either_way(a,p_friend_id)) then
  raise exception 'weekly_sharing_unavailable' using errcode='42501'; end if;
 if p_enabled and (select count(*) from app.weekly_sharing where challenge_id=p_challenge_id and owner_id=a and enabled)>=5
  and not exists(select 1 from app.weekly_sharing where challenge_id=p_challenge_id and owner_id=a and friend_id=p_friend_id and enabled) then
  raise exception 'weekly_sharing_limit' using errcode='23505'; end if;
 if p_enabled and exists(select 1 from app.weekly_sharing where challenge_id=p_challenge_id and owner_id=a and friend_id=p_friend_id and state='declined') then raise exception 'weekly_follow_declined' using errcode='55000'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 insert into app.weekly_sharing(challenge_id,owner_id,friend_id,enabled,offer_id,state) values(p_challenge_id,a,p_friend_id,p_enabled,p_request_id,case when p_enabled then 'pending' else 'ended' end)
  on conflict(challenge_id,owner_id,friend_id) do update set enabled=excluded.enabled,offer_id=case when excluded.enabled then excluded.offer_id else app.weekly_sharing.offer_id end,
   state=case when app.weekly_sharing.state='declined' then 'declined' else excluded.state end;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;

create function app.weekly_respond_follow_at_v1(p_request_id uuid,p_challenge_id uuid,p_owner_id uuid,p_offer_id uuid,p_decision text,p_now timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; s app.weekly_sharing; n timestamptz; begin
 a:=app.weekly_session_v1(array[p_owner_id]);
 p:=jsonb_build_object('op','weekly-display-follow-v1','id',p_challenge_id,'owner',p_owner_id,'offer',p_offer_id,'decision',p_decision);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 select * into s from app.weekly_sharing where challenge_id=p_challenge_id and owner_id=p_owner_id and friend_id=a for update;
 perform app.weekly_require_session_v1();
 if s.challenge_id is null or p_decision is null or p_decision not in ('accept','decline','unfollow') or p_offer_id is distinct from s.offer_id then
  raise exception 'weekly_follow_unavailable' using errcode='42501'; end if;
 n:=coalesce(p_now,clock_timestamp());
 if p_decision='accept' and not exists(select 1 from app.weekly_agreements where id=p_challenge_id and ends_at>n) then
  raise exception 'weekly_sharing_expired' using errcode='55000'; end if;
 if p_decision='accept' and (not s.enabled or s.state<>'pending' or not app.is_active_actor(p_owner_id)
  or not app.is_friend(a,p_owner_id) or app.is_blocked_either_way(a,p_owner_id)) then raise exception 'weekly_follow_unavailable' using errcode='42501'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 update app.weekly_sharing set enabled=p_decision='accept',state=case when p_decision='accept' then 'accepted' else 'declined' end
 where challenge_id=p_challenge_id and owner_id=p_owner_id and friend_id=a;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;

create function app.weekly_shared_progress_at_v1(p_now timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; n timestamptz; begin
 a:=app.weekly_session_v1(); n:=coalesce(p_now,clock_timestamp());
 select coalesce(jsonb_agg(jsonb_build_object('challenge_id',c.id,'owner_id',s.owner_id,'display_name',p.display_name,
  'starts_at',c.starts_at,'ends_at',c.ends_at,'timezone',c.terms->>'timezone','target_steps',q.target_steps,
  'observed_steps',(select sum(x.steps) from (select distinct on(day) steps from app.weekly_progress where challenge_id=c.id and actor_id=s.owner_id order by day,recorded_at desc,id desc) x),
  'updated_at',(select max(recorded_at) from app.weekly_progress where challenge_id=c.id and actor_id=s.owner_id),
  'source','client_progress_only','policy_version',s.policy_version,'offer_id',s.offer_id) order by c.starts_at desc,c.id,s.owner_id),'[]'::jsonb)
 into r from (select * from app.weekly_sharing s0 where friend_id=a and enabled and state='accepted'
  and exists(select 1 from app.weekly_agreements c0 where c0.id=s0.challenge_id and c0.ends_at>n) order by challenge_id,owner_id limit 100) s
 join app.weekly_agreements c on c.id=s.challenge_id join public.profiles p on p.id=s.owner_id
 join app.weekly_participants q on q.challenge_id=c.id and q.actor_id=s.owner_id
 where app.is_active_actor(s.owner_id) and app.is_friend(a,s.owner_id) and not app.is_blocked_either_way(a,s.owner_id);
 return r;
end; $$;

create function app.weekly_follow_requests_at_v1(p_now timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; n timestamptz; begin
 a:=app.weekly_session_v1(); n:=coalesce(p_now,clock_timestamp());
 select coalesce(jsonb_agg(jsonb_build_object('challenge_id',s.challenge_id,'owner_id',s.owner_id,'display_name',p.display_name,
  'offer_id',s.offer_id,'policy_version',s.policy_version,'state',s.state) order by s.challenge_id,s.owner_id),'[]'::jsonb)
 into r from app.weekly_sharing s join public.profiles p on p.id=s.owner_id
 join app.weekly_agreements c on c.id=s.challenge_id
 where c.ends_at>n and s.friend_id=a and s.enabled and s.state='pending' and app.is_active_actor(s.owner_id)
  and app.is_friend(a,s.owner_id) and not app.is_blocked_either_way(a,s.owner_id);
 return r;
end; $$;

create or replace function public.list_weekly_sharing_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; n timestamptz; begin
 a:=app.weekly_session_v1(); n:=clock_timestamp();
 if not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a and accepted_at is not null) then
  raise exception 'weekly_sharing_unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('friend_id',s.friend_id,'display_name',p.display_name,'enabled',s.enabled and c.ends_at>n,'offer_id',s.offer_id,
  'state',case when c.ends_at<=n and s.state in ('pending','accepted') then 'ended' else s.state end) order by s.friend_id),'[]'::jsonb)
 into r from app.weekly_sharing s join public.profiles p on p.id=s.friend_id join app.weekly_agreements c on c.id=s.challenge_id
 where s.challenge_id=p_challenge_id and s.owner_id=a and app.is_active_actor(s.friend_id) and app.is_friend(a,s.friend_id) and not app.is_blocked_either_way(a,s.friend_id);
 return r;
end; $$;

create or replace function public.set_weekly_sharing_v1(p_request_id uuid,p_challenge_id uuid,p_friend_id uuid,p_enabled boolean)
returns uuid language sql security definer set search_path='' as $$
 select app.weekly_set_sharing_at_v1(p_request_id,p_challenge_id,p_friend_id,p_enabled,null)
$$;
create or replace function public.respond_weekly_follow_v1(p_request_id uuid,p_challenge_id uuid,p_owner_id uuid,p_offer_id uuid,p_decision text)
returns uuid language sql security definer set search_path='' as $$
 select app.weekly_respond_follow_at_v1(p_request_id,p_challenge_id,p_owner_id,p_offer_id,p_decision,null)
$$;
create or replace function public.list_shared_weekly_progress_v1() returns jsonb
language sql security definer set search_path='' as $$select app.weekly_shared_progress_at_v1(null)$$;
create or replace function public.list_weekly_follow_requests_v1() returns jsonb
language sql security definer set search_path='' as $$select app.weekly_follow_requests_at_v1(null)$$;
revoke all on function app.weekly_set_sharing_at_v1(uuid,uuid,uuid,boolean,timestamptz),
 app.weekly_respond_follow_at_v1(uuid,uuid,uuid,uuid,text,timestamptz),app.weekly_shared_progress_at_v1(timestamptz),
 app.weekly_follow_requests_at_v1(timestamptz) from public,anon,authenticated,service_role;
