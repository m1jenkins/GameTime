-- Explicit selected-friend display-only progress sharing; never enrollment,
-- qualification, proof, results, financial state or community roster access.
create table app.weekly_sharing (
 challenge_id uuid not null references app.weekly_agreements(id), owner_id uuid not null references public.profiles(id),
 friend_id uuid not null references public.profiles(id), enabled boolean not null,
 offer_id uuid not null, state text not null default 'pending' check(state in ('pending','accepted','declined','ended')),
 policy_version text not null default 'weekly-display-sharing-v1' check(policy_version='weekly-display-sharing-v1'),
 primary key(challenge_id,owner_id,friend_id), check(owner_id<>friend_id)
);
create index weekly_sharing_owner_idx on app.weekly_sharing(owner_id);
create index weekly_sharing_friend_idx on app.weekly_sharing(friend_id);
alter table app.weekly_sharing enable row level security;
revoke all on app.weekly_sharing from public,anon,authenticated,service_role;
create function app.weekly_sharing_guard_v1() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
  or coalesce(current_setting('app.weekly_write_v1',true),'')<>'on' then raise exception 'weekly_rpc_required' using errcode='42501'; end if;
 if tg_op='INSERT' then return new; end if;
 if tg_op='UPDATE' and (to_jsonb(new)-array['enabled','offer_id','state'])=(to_jsonb(old)-array['enabled','offer_id','state']) then return new; end if;
 raise exception 'weekly_immutable' using errcode='23001';
end; $$;
create trigger weekly_sharing_guard before insert or update or delete on app.weekly_sharing for each row execute function app.weekly_sharing_guard_v1();
create trigger weekly_sharing_no_truncate before truncate on app.weekly_sharing for each statement execute function app.weekly_sharing_guard_v1();
create function public.set_weekly_sharing_v1(p_request_id uuid,p_challenge_id uuid,p_friend_id uuid,p_enabled boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; begin
 a:=app.weekly_session_v1(array[p_friend_id]); p:=jsonb_build_object('op','weekly-display-sharing-v1','id',p_challenge_id,'friend',p_friend_id,'enabled',p_enabled);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 if p_enabled is null or p_friend_id is null or p_friend_id=a or not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a and accepted_at is not null) then
  raise exception 'weekly_sharing_unavailable' using errcode='42501'; end if;
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
create function public.list_weekly_sharing_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; begin
 a:=app.weekly_session_v1();
 if not exists(select 1 from app.weekly_participants where challenge_id=p_challenge_id and actor_id=a and accepted_at is not null) then
  raise exception 'weekly_sharing_unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('friend_id',s.friend_id,'display_name',p.display_name,'enabled',s.enabled,'offer_id',s.offer_id,'state',s.state) order by s.friend_id),'[]'::jsonb)
 into r from app.weekly_sharing s join public.profiles p on p.id=s.friend_id
 where s.challenge_id=p_challenge_id and s.owner_id=a and app.is_active_actor(s.friend_id) and app.is_friend(a,s.friend_id) and not app.is_blocked_either_way(a,s.friend_id);
 return r;
end; $$;
create function public.list_shared_weekly_progress_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; begin
 a:=app.weekly_session_v1();
 select coalesce(jsonb_agg(jsonb_build_object('challenge_id',c.id,'owner_id',s.owner_id,'display_name',p.display_name,
  'starts_at',c.starts_at,'ends_at',c.ends_at,'timezone',c.terms->>'timezone','target_steps',q.target_steps,
  'observed_steps',(select sum(x.steps) from (select distinct on(day) steps from app.weekly_progress where challenge_id=c.id and actor_id=s.owner_id order by day,recorded_at desc,id desc) x),
  'updated_at',(select max(recorded_at) from app.weekly_progress where challenge_id=c.id and actor_id=s.owner_id),
  'source','client_progress_only','policy_version',s.policy_version,'offer_id',s.offer_id) order by c.starts_at desc,c.id,s.owner_id),'[]'::jsonb)
 into r from (select * from app.weekly_sharing where friend_id=a and enabled and state='accepted' order by challenge_id,owner_id limit 100) s
 join app.weekly_agreements c on c.id=s.challenge_id join public.profiles p on p.id=s.owner_id
 join app.weekly_participants q on q.challenge_id=c.id and q.actor_id=s.owner_id
 where app.is_active_actor(s.owner_id) and app.is_friend(a,s.owner_id) and not app.is_blocked_either_way(a,s.owner_id);
 return r;
end; $$;
create function app.weekly_sharing_delete_v1() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.deleted_at is null and new.deleted_at is not null then
  perform set_config('app.weekly_write_v1','on',true);
  update app.weekly_sharing set enabled=false,state=case when state='declined' then state else 'ended' end where owner_id=new.id or friend_id=new.id;
 end if;
 return new;
end; $$;
create trigger profiles_weekly_sharing_delete after update of deleted_at on public.profiles for each row execute function app.weekly_sharing_delete_v1();
revoke all on function app.weekly_sharing_guard_v1(),app.weekly_sharing_delete_v1(),public.set_weekly_sharing_v1(uuid,uuid,uuid,boolean),
 public.list_weekly_sharing_v1(uuid),public.list_shared_weekly_progress_v1() from public,anon,authenticated,service_role;
grant execute on function public.set_weekly_sharing_v1(uuid,uuid,uuid,boolean),public.list_weekly_sharing_v1(uuid),public.list_shared_weekly_progress_v1() to authenticated;

-- Ending a social relationship permanently retires this grant. A later unblock
-- or new friendship never revives it without a new owner offer and acceptance.
create function app.weekly_sharing_social_end_v1() returns trigger language plpgsql security definer set search_path='' as $$
declare a uuid; b uuid; begin
 if tg_table_name='friendships' then a:=old.user_a; b:=old.user_b;
 else a:=new.blocker_id; b:=new.blocked_id; end if;
 perform set_config('app.weekly_write_v1','on',true);
 update app.weekly_sharing set enabled=false,state=case when state='declined' then state else 'ended' end
 where (owner_id=a and friend_id=b) or (owner_id=b and friend_id=a);
 return coalesce(new,old);
end; $$;
create trigger friendships_weekly_sharing_end after delete on public.friendships for each row execute function app.weekly_sharing_social_end_v1();
create trigger blocks_weekly_sharing_end after insert on public.blocks for each row execute function app.weekly_sharing_social_end_v1();
create function public.list_weekly_follow_requests_v1() returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; r jsonb; begin
 a:=app.weekly_session_v1();
 select coalesce(jsonb_agg(jsonb_build_object('challenge_id',s.challenge_id,'owner_id',s.owner_id,'display_name',p.display_name,
  'offer_id',s.offer_id,'policy_version',s.policy_version,'state',s.state) order by s.challenge_id,s.owner_id),'[]'::jsonb)
 into r from app.weekly_sharing s join public.profiles p on p.id=s.owner_id
 where s.friend_id=a and s.enabled and s.state='pending' and app.is_active_actor(s.owner_id)
  and app.is_friend(a,s.owner_id) and not app.is_blocked_either_way(a,s.owner_id);
 return r;
end; $$;
create function public.respond_weekly_follow_v1(p_request_id uuid,p_challenge_id uuid,p_owner_id uuid,p_offer_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; p jsonb; v uuid; s app.weekly_sharing; begin
 a:=app.weekly_session_v1(array[p_owner_id]);
 p:=jsonb_build_object('op','weekly-display-follow-v1','id',p_challenge_id,'owner',p_owner_id,'offer',p_offer_id,'decision',p_decision);
 v:=app.weekly_recover_v1(a,p_request_id,p); if v is not null then return v; end if;
 select * into s from app.weekly_sharing where challenge_id=p_challenge_id and owner_id=p_owner_id and friend_id=a for update;
 perform app.weekly_require_session_v1();
 if s.challenge_id is null or p_decision is null or p_decision not in ('accept','decline','unfollow') or p_offer_id is distinct from s.offer_id then
  raise exception 'weekly_follow_unavailable' using errcode='42501'; end if;
 if p_decision='accept' and (not s.enabled or s.state<>'pending' or not app.is_active_actor(p_owner_id)
  or not app.is_friend(a,p_owner_id) or app.is_blocked_either_way(a,p_owner_id)) then raise exception 'weekly_follow_unavailable' using errcode='42501'; end if;
 perform set_config('app.weekly_write_v1','on',true);
 update app.weekly_sharing set enabled=p_decision='accept',state=case when p_decision='accept' then 'accepted' else 'declined' end
 where challenge_id=p_challenge_id and owner_id=p_owner_id and friend_id=a;
 insert into app.weekly_requests values(a,p_request_id,p,p_request_id,clock_timestamp()); return p_request_id;
end; $$;
revoke all on function app.weekly_sharing_social_end_v1(),public.list_weekly_follow_requests_v1(),public.respond_weekly_follow_v1(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.list_weekly_follow_requests_v1(),public.respond_weekly_follow_v1(uuid,uuid,uuid,uuid,text) to authenticated;
