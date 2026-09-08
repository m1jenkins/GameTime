create table app.challenge_age_v1(actor_id uuid primary key references public.profiles(id),policy text not null check(policy='age_21_v1'),confirmed_at timestamptz not null);
create table app.challenge_access_v1(actor_id uuid primary key references public.profiles(id),granted_at timestamptz not null);
create table app.challenge_links_v1(id uuid primary key,challenge_id uuid not null references app.challenge_lobbies_v1(id),issuer uuid not null references public.profiles(id),token_hash text unique not null,issued_at timestamptz not null,expires_at timestamptz not null,revoked_at timestamptz,check(expires_at=issued_at+interval '30 days'));
create index challenge_links_challenge_v1 on app.challenge_links_v1(challenge_id);
create table app.challenge_redemptions_v1(link_id uuid not null references app.challenge_links_v1(id),actor_id uuid not null references public.profiles(id),redeemed_at timestamptz not null,primary key(link_id,actor_id));
create index challenge_redemptions_actor_v1 on app.challenge_redemptions_v1(actor_id);
create table app.challenge_reports_v1(id uuid primary key,reporter uuid not null references public.profiles(id),subject uuid not null references public.profiles(id),reason text not null check(reason in ('username','unwanted_contact','unsafe_behavior')),created_at timestamptz not null);
create table app.challenge_suspensions_v1(actor_id uuid primary key references public.profiles(id),suspended boolean not null,operator_id uuid not null,reason text not null,recorded_at timestamptz not null);
create table app.challenge_operator_grants_v1(actor_id uuid not null references public.profiles(id),challenge_id uuid not null references app.challenge_lobbies_v1(id),capability text not null check(capability in ('review','moderate')),expires_at timestamptz not null,primary key(actor_id,challenge_id,capability));
create table app.challenge_operator_audit_v1(id uuid primary key,operator_id uuid not null,payload jsonb not null,recorded_at timestamptz not null);
-- Private rows plus explicit mutation grants; no raw Health, freeform review
-- narratives, birthdates or identity documents are stored by these interfaces.
do $$ declare t text;begin
 foreach t in array array['age','access','links','redemptions','reports','suspensions','operator_grants','operator_audit'] loop
  execute format('alter table app.challenge_%s_v1 enable row level security',t);
  execute format('revoke all on app.challenge_%s_v1 from public,anon,authenticated,service_role',t);
 end loop;
end $$;
create function app.challenge_entry_guard_v1() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid)) or coalesce(current_setting('app.challenge_write_v1',true),'')<>'on' then raise exception 'challenge_rpc_required' using errcode='42501';end if;
 if tg_op='INSERT' then return new;end if;
 if tg_op='UPDATE' and tg_table_name in ('challenge_links_v1','challenge_suspensions_v1','challenge_operator_grants_v1') then return new;end if;
 raise exception 'challenge_immutable' using errcode='23001';
end $$;
do $$ declare t text;begin
 foreach t in array array['age','access','links','redemptions','reports','suspensions','operator_grants','operator_audit'] loop
  execute format('create trigger challenge_entry_guard before insert or update or delete on app.challenge_%s_v1 for each row execute function app.challenge_entry_guard_v1()',t);
  execute format('create trigger challenge_entry_no_truncate before truncate on app.challenge_%s_v1 for each statement execute function app.challenge_entry_guard_v1()',t);
 end loop;
end $$;
create or replace function app.challenge_admit_v1(a uuid) returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from app.challenge_runtime_v1 where singleton and admission and fixtures and (a=any(actors) or exists(select 1 from app.challenge_access_v1 where actor_id=a)))
 or exists(select 1 from app.challenge_suspensions_v1 where actor_id=a and suspended) then raise exception 'challenge_admission_paused' using errcode='42501';end if;
 if not exists(select 1 from app.challenge_age_v1 where actor_id=a) then raise exception 'challenge_age_required' using errcode='42501';end if;
end $$;
create function public.challenge_confirm_age_v1(p_request_id uuid,p_confirmed boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;payload jsonb; saved app.challenge_requests_v1; response jsonb;begin
 a:=app.challenge_session_v1();payload:=jsonb_build_object('op','confirm_age','confirmed',p_confirmed);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or p_confirmed is distinct from true then raise exception 'challenge_age_required' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_age_v1 values(a,'age_21_v1',app.challenge_now_v1()) on conflict do nothing;
 response:='{"confirmed":true,"policy":"age_21_v1"}';
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,response,app.challenge_now_v1());return response;
end $$;
create function public.challenge_access_status_v1() returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;begin
 a:=app.challenge_session_v1();return jsonb_build_object('age_confirmed',exists(select 1 from app.challenge_age_v1 where actor_id=a),'beta_access',exists(select 1 from app.challenge_access_v1 where actor_id=a) or exists(select 1 from app.challenge_runtime_v1 where a=any(actors)),'suspended',exists(select 1 from app.challenge_suspensions_v1 where actor_id=a and suspended));
end $$;
create function public.challenge_issue_link_v1(p_request_id uuid,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;c app.challenge_lobbies_v1;saved app.challenge_requests_v1;payload jsonb;token text;result jsonb;n timestamptz;lid uuid;begin
 a:=app.challenge_session_v1();payload:=jsonb_build_object('op','issue_link','id',p_id);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 perform app.challenge_admit_v1(a);n:=app.challenge_now_v1();select * into c from app.challenge_lobbies_v1 where id=p_id for update;
 if p_request_id is null or c.creator_id is distinct from a or split_part(c.policy,'_',1)<>'friend' or c.status<>'lobby_open' or n>=c.starts_at then raise exception 'challenge_link_unavailable' using errcode='42501';end if;
 if (select count(*) from app.challenge_links_v1 where challenge_id=p_id and revoked_at is null)>=5 then raise exception 'challenge_link_limit' using errcode='23505';end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');lid:=extensions.gen_random_uuid();perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_links_v1 values(lid,p_id,a,encode(extensions.digest(token,'sha256'),'hex'),n,n+interval '30 days',null);
 result:=jsonb_build_object('id',lid,'token',token,'expires_at',n+interval '30 days','unique_account_limit',20);
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,result,n);return result;
end $$;
create function public.challenge_redeem_link_v1(p_request_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;l app.challenge_links_v1;c app.challenge_lobbies_v1;saved app.challenge_requests_v1;payload jsonb;result jsonb;n timestamptz;begin
 a:=app.challenge_session_v1();
 if p_request_id is null or p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'challenge_link_unavailable' using errcode='42501';end if;
 payload:=jsonb_build_object('op','redeem_link','token_hash',encode(extensions.digest(p_token,'sha256'),'hex'));
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if not exists(select 1 from app.challenge_age_v1 where actor_id=a) then raise exception 'challenge_age_required' using errcode='42501';end if;
 select * into l from app.challenge_links_v1 where token_hash=payload->>'token_hash' for update;
 select * into c from app.challenge_lobbies_v1 where id=l.challenge_id;n:=app.challenge_now_v1();
 -- Repeat account redemption is idempotent after closure; it cannot create new
 -- contact or membership, and never revokes already granted Beta access.
 if not exists(select 1 from app.challenge_redemptions_v1 where link_id=l.id and actor_id=a) then
  if l.id is null or l.revoked_at is not null or n>=l.expires_at or c.status<>'lobby_open' or n>=c.starts_at or not app.is_active_actor(c.creator_id)
  or exists(select 1 from app.challenge_suspensions_v1 where actor_id in (a,c.creator_id) and suspended)
  or app.is_blocked_either_way(a,c.creator_id) or (select count(*) from app.challenge_redemptions_v1 where link_id=l.id)>=20
  or not exists(select 1 from app.challenge_runtime_v1 where singleton and admission and fixtures) then raise exception 'challenge_link_unavailable' using errcode='42501';end if;
  perform set_config('app.challenge_write_v1','on',true);
  insert into app.challenge_redemptions_v1 values(l.id,a,n);
  insert into app.challenge_access_v1 values(a,n) on conflict do nothing;
  insert into app.challenge_members_v1(challenge_id,actor_id) values(c.id,a) on conflict do nothing;
  update app.challenge_lobbies_v1 set revision=revision+1 where id=c.id;
 end if;
 result:=jsonb_build_object('id',c.id,'status','pending_request','beta_access',true);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,result,n);return result;
end $$;
create function public.challenge_revoke_link_v1(p_request_id uuid,p_link_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;saved app.challenge_requests_v1;payload jsonb;begin
 a:=app.challenge_session_v1();payload:=jsonb_build_object('op','revoke_link','id',p_link_id);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or not exists(select 1 from app.challenge_links_v1 where id=p_link_id and issuer=a) then raise exception 'challenge_link_unavailable' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);update app.challenge_links_v1 set revoked_at=coalesce(revoked_at,app.challenge_now_v1()) where id=p_link_id;
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"revoked":true}',app.challenge_now_v1());return '{"revoked":true}';
end $$;
create function public.challenge_report_v1(p_request_id uuid,p_subject uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;saved app.challenge_requests_v1;payload jsonb;begin
 a:=app.challenge_session_v1();payload:=jsonb_build_object('op','report','subject',p_subject,'reason',p_reason);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or p_subject is null or p_reason is null or p_reason not in ('username','unwanted_contact','unsafe_behavior')
 or not exists(select 1 from app.challenge_members_v1 me join app.challenge_members_v1 other using(challenge_id) where me.actor_id=a and other.actor_id=p_subject) then raise exception 'challenge_report_unavailable' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);insert into app.challenge_reports_v1 values(p_request_id,a,p_subject,p_reason,app.challenge_now_v1());
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"saved":true}',app.challenge_now_v1());return '{"saved":true}';
end $$;
-- Only a service administrator can assign a bounded operator scope. Operators
-- authenticate normally and cannot resolve challenges they participate in.
create function public.challenge_grant_operator_v1(p_actor uuid,p_id uuid,p_capability text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.duel_require_service_v1();perform 1 from app.challenge_runtime_v1 where singleton for update;
 if not app.is_active_actor(p_actor) or p_expires<=app.challenge_now_v1() or p_expires>app.challenge_now_v1()+interval '7 days' or p_capability not in ('review','moderate')
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=p_actor) then raise exception 'challenge_invalid_grant' using errcode='22023';end if;
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_operator_grants_v1 values(p_actor,p_id,p_capability,p_expires) on conflict(actor_id,challenge_id,capability) do update set expires_at=excluded.expires_at;
 insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),p_actor,jsonb_build_object('action','grant','id',p_id,'capability',p_capability,'expires',p_expires),app.challenge_now_v1());
end $$;
create function public.challenge_operator_action_v1(p_request_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid;cid uuid;op text;cap text;target uuid;r app.challenge_reviews_v1;saved app.challenge_requests_v1;response jsonb:='{"saved":true}';begin
 actor:=app.challenge_session_v1();op:=p_payload->>'op';cid:=(p_payload->>'id')::uuid;
 select * into saved from app.challenge_requests_v1 where actor_id=actor and request_id=p_request_id;
 if found then if saved.payload is distinct from p_payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 cap:=case when op='resolve' then 'review' else 'moderate' end;
 if p_request_id is null or op is null or op not in ('resolve','remove','suspend') or octet_length(p_payload::text)>4096
 or not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=actor and challenge_id=cid and capability=cap and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=cid and actor_id=actor)
 or exists(select 1 from app.challenge_suspensions_v1 where actor_id=actor and suspended) then raise exception 'challenge_operator_required' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);
 if op='resolve' then
  if p_payload-array['op','id','review_id','decision']<>'{}' or p_payload->>'decision' is null or p_payload->>'decision' not in ('upheld','exclude') then raise exception 'challenge_invalid_resolution' using errcode='22023';end if;
  select * into r from app.challenge_reviews_v1 where id=(p_payload->>'review_id')::uuid and challenge_id=cid;
  if r.id is null or app.challenge_now_v1()>=r.resolve_by or exists(select 1 from app.challenge_resolutions_v1 where review_id=r.id)
   or exists(select 1 from app.challenge_finals_v1 where challenge_id=cid) then raise exception 'challenge_invalid_resolution' using errcode='22023';end if;
  insert into app.challenge_resolutions_v1 values(r.id,p_payload->>'decision',actor,app.challenge_now_v1());
 elsif op in ('remove','suspend') then
  target:=(p_payload->>'actor_id')::uuid;
  if p_payload-array['op','id','actor_id','reason']<>'{}' or p_payload->>'reason' is null or p_payload->>'reason' not in ('unsafe_behavior','unwanted_contact','username')
   or not exists(select 1 from app.challenge_members_v1 where challenge_id=cid and actor_id=target) then raise exception 'challenge_invalid_moderation' using errcode='22023';end if;
  if op='suspend' then
   insert into app.challenge_suspensions_v1 values(target,true,actor,p_payload->>'reason',app.challenge_now_v1()) on conflict(actor_id) do update set suspended=true,operator_id=excluded.operator_id,reason=excluded.reason,recorded_at=excluded.recorded_at;
  end if;
  if not exists(select 1 from app.challenge_finals_v1 where challenge_id=cid) then
   update app.challenge_members_v1 set exited_at=coalesce(exited_at,app.challenge_now_v1()) where challenge_id=cid and actor_id=target;
   insert into app.challenge_exits_v1 values(p_request_id,cid,target,'operator_removal',app.challenge_now_v1());
  end if;
 end if;
 update app.challenge_lobbies_v1 set revision=revision+1 where id=cid and not exists(select 1 from app.challenge_finals_v1 where challenge_id=cid);
 insert into app.challenge_operator_audit_v1 values(p_request_id,actor,p_payload,app.challenge_now_v1());
 insert into app.challenge_requests_v1 values(actor,p_request_id,p_payload,response,app.challenge_now_v1());return response;
end $$;
create function public.challenge_operator_cases_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;begin
 a:=app.challenge_session_v1();
 if not exists(select 1 from app.challenge_operator_grants_v1 where actor_id=a and challenge_id=p_id and capability='review' and expires_at>app.challenge_now_v1())
 or exists(select 1 from app.challenge_members_v1 where challenge_id=p_id and actor_id=a) then raise exception 'challenge_operator_required' using errcode='42501';end if;
 perform set_config('app.challenge_write_v1','on',true);insert into app.challenge_operator_audit_v1 values(extensions.gen_random_uuid(),a,jsonb_build_object('op','read_cases','id',p_id),app.challenge_now_v1());
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'actor_id',r.actor_id,'reason',r.reason,'filed_at',r.filed_at,'resolve_by',r.resolve_by,'decision',s.decision)),'[]') from app.challenge_reviews_v1 r left join app.challenge_resolutions_v1 s on s.review_id=r.id where r.challenge_id=p_id);
end $$;
create function public.challenge_block_v1(p_request_id uuid,p_subject uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;c uuid;saved app.challenge_requests_v1;payload jsonb;begin
 a:=app.challenge_session_v1();payload:=jsonb_build_object('op','block','subject',p_subject);
 select * into saved from app.challenge_requests_v1 where actor_id=a and request_id=p_request_id;
 if found then if saved.payload is distinct from payload then raise exception 'challenge_request_conflict' using errcode='22023';end if;return saved.response;end if;
 if p_request_id is null or p_subject is null or a=p_subject or not exists(select 1 from app.challenge_members_v1 me join app.challenge_members_v1 other using(challenge_id) where me.actor_id=a and other.actor_id=p_subject) then raise exception 'challenge_block_unavailable' using errcode='42501';end if;
 perform id from public.profiles where id in(a,p_subject) order by id for update;
 perform set_config('app.challenge_write_v1','on',true);
 insert into public.blocks(blocker_id,blocked_id) values(a,p_subject) on conflict do nothing;
 for c in select me.challenge_id from app.challenge_members_v1 me join app.challenge_members_v1 other using(challenge_id) where me.actor_id=a and other.actor_id=p_subject loop
  perform app.challenge_tick_v1(c,true);
 end loop;
 insert into app.challenge_requests_v1 values(a,p_request_id,payload,'{"blocked":true}',app.challenge_now_v1());return '{"blocked":true}';
end $$;
create function app.challenge_actor_unavailable_v1(a uuid) returns boolean language sql stable set search_path='' as $$
 select not app.is_active_actor(a) or exists(select 1 from app.challenge_suspensions_v1 where actor_id=a and suspended)
$$;
-- Operator and entry functions have explicit grants; no wildcard grants.
revoke all on function app.challenge_entry_guard_v1(),app.challenge_actor_unavailable_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function public.challenge_grant_operator_v1(uuid,uuid,text,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.challenge_grant_operator_v1(uuid,uuid,text,timestamptz) to service_role;
do $$ declare f regprocedure;begin
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in ('challenge_confirm_age_v1','challenge_access_status_v1','challenge_issue_link_v1','challenge_redeem_link_v1','challenge_revoke_link_v1','challenge_report_v1','challenge_operator_action_v1','challenge_operator_cases_v1','challenge_block_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
-- Apply the same active/suspended predicate to new-contract projections and
-- lifecycle only. No historical app.is_active_actor or weekly function changes.
do $$ declare name text;f regprocedure;definition text;begin
 foreach name in array array['app.challenge_tick_v1(uuid,boolean)','app.challenge_evaluate_v1(uuid,boolean)','public.challenge_detail_v1(uuid)','public.challenge_mutate_v1(uuid,jsonb)'] loop
  f:=name::regprocedure;definition:=pg_get_functiondef(f);
  definition:=replace(definition,'not app.is_active_actor(','app.challenge_actor_unavailable_v1(');
  if name='public.challenge_detail_v1(uuid)' then definition:=replace(definition,'hidden:=','hidden:=app.challenge_actor_unavailable_v1(a) or ');end if;
  execute definition;
 end loop;
end $$;
