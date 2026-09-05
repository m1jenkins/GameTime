-- Phase 2(e): local simulated rematches and named-recipient invitation links.
-- Existing policy, agreement receipts, lifecycle and settlement are unchanged.
create table app.duel_rematches (
  challenge_id uuid primary key references public.duel_challenges(id),
  previous_challenge_id uuid not null references public.duel_challenges(id),
  check (challenge_id <> previous_challenge_id)
);
create index duel_rematch_previous_idx on app.duel_rematches(previous_challenge_id);
create table app.duel_invitation_links (
  token uuid primary key default extensions.gen_random_uuid(),
  challenge_id uuid not null references public.duel_challenges(id),
  created_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > created_at),
  revoked_at timestamptz check (revoked_at >= created_at)
);
create unique index duel_one_unrevoked_link on app.duel_invitation_links(challenge_id) where revoked_at is null;

create function app.duel_link_guard_v1() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
     or coalesce(current_setting('app.duel_write_v1',true),'') <> 'on' then
    raise exception 'duel_write_requires_rpc' using errcode='42501';
  end if;
  if tg_op in ('DELETE','TRUNCATE') or (tg_op='UPDATE' and
    (tg_table_name='duel_rematches' or to_jsonb(old)->>'revoked_at' is not null or to_jsonb(new)->>'revoked_at' is null or
     (to_jsonb(old)-'revoked_at') is distinct from (to_jsonb(new)-'revoked_at'))) then
    raise exception 'duel_link_history_immutable' using errcode='23001';
  end if;
  return new;
end; $$;
alter table app.duel_rematches enable row level security;
alter table app.duel_invitation_links enable row level security;
revoke all on app.duel_rematches,app.duel_invitation_links from public,anon,authenticated,service_role;
create trigger duel_rematch_guard before insert or update or delete on app.duel_rematches
  for each row execute function app.duel_link_guard_v1();
create trigger duel_link_guard before insert or update or delete on app.duel_invitation_links
  for each row execute function app.duel_link_guard_v1();
create trigger duel_rematch_truncate before truncate on app.duel_rematches
  for each statement execute function app.duel_link_guard_v1();
create trigger duel_link_truncate before truncate on app.duel_invitation_links
  for each statement execute function app.duel_link_guard_v1();

create function app.rematch_duel_at_v1(p_request_id uuid,p_previous_challenge_id uuid,p_event_id uuid,
  p_expected_policy_version text,p_consent boolean,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare a uuid := auth.uid(); v_payload jsonb; v_id uuid; v_now timestamptz;
  previous public.duel_challenges; p_invitee_id uuid; e public.duel_event_fixtures; v_policy jsonb; v_terms jsonb; v_digest text;
begin
  select * into previous from public.duel_challenges where id=p_previous_challenge_id;
  if a is null or not found or a not in (previous.creator_id,previous.invitee_id) then
    raise exception 'duel_unavailable' using errcode='42501';
  end if;
  p_invitee_id := case when a=previous.creator_id then previous.invitee_id else previous.creator_id end;
  perform app.duel_lock_pair_v1(a,p_invitee_id);
  perform app.duel_proof_require_session_v1();
  v_payload := jsonb_build_object('operation','rematch_duel_v1','previous_challenge_id',p_previous_challenge_id,
    'event_id',p_event_id,'policy_version',p_expected_policy_version,'consent',p_consent);
  v_id := app.duel_recover_request_v1(a,p_request_id,v_payload);
  if v_id is not null then return v_id; end if;
  if p_invitee_id is null or p_invitee_id = a or p_consent is distinct from true
      or p_expected_policy_version is distinct from 'duel-fixture-5k-v1' then
    raise exception 'duel_invalid_terms' using errcode = '22023';
  end if;
  perform app.duel_admit_pair_v1(a,p_invitee_id);
  perform 1 from public.duel_challenges where id=previous.id for update;
  if not exists(select 1 from app.duel_lifecycle_results where challenge_id=previous.id) then
    raise exception 'duel_previous_result_required' using errcode='55000';
  end if;
  -- Wall clock is sampled AFTER potentially blocking locks; transaction-start
  -- time must never admit a request that waited past the cutoff.
  v_now := coalesce(p_now,clock_timestamp());
  select * into e from public.duel_event_fixtures where id=p_event_id;
  if not found or not isfinite(v_now) or e.policy_version <> p_expected_policy_version
     or e.ends_at > v_now + interval '720 hours' or e.starts_at - interval '1 hour' <= v_now then
    raise exception 'duel_event_unavailable' using errcode = '22023';
  end if;
  if e.id=previous.event_id or e.starts_at <= (previous.terms->'event'->>'ends_at')::timestamptz then
    raise exception 'duel_fresh_event_required' using errcode='22023';
  end if;
  perform app.duel_release_overdue_v1(a,v_now);
  if exists (select 1 from app.duel_enrollments where actor_id=a and released_at is null) then
    raise exception 'duel_slot_occupied' using errcode = '23505';
  end if;
  select specification into strict v_policy from public.duel_policy_versions where version=e.policy_version;
  v_terms := jsonb_build_object('agreement_version',1,'policy_version',e.policy_version,'policy',v_policy,
    'creator_id',a,'invitee_id',p_invitee_id,'event',to_jsonb(e),'created_at',v_now,
    'accept_by',least(v_now + interval '72 hours',e.starts_at - interval '1 hour'),
    'results_due_at',e.ends_at + interval '72 hours','finality_due_at',e.ends_at + interval '720 hours');
  perform set_config('app.duel_write_v1','on',true);
  insert into public.duel_challenges(creator_id,invitee_id,event_id,policy_version,created_at,starts_at,accept_by,terms)
    values(a,p_invitee_id,e.id,e.policy_version,v_now,e.starts_at,
      least(v_now + interval '72 hours',e.starts_at - interval '1 hour'),v_terms)
    returning id,terms_digest into v_id,v_digest;
  insert into public.duel_participants(challenge_id,actor_id,role,accepted_at,consent_policy_version,consent_terms_digest)
    values(v_id,a,'creator',v_now,e.policy_version,v_digest),(v_id,p_invitee_id,'invitee',null,null,null);
  insert into app.duel_enrollments values(v_id,a,v_now,null);
  insert into app.duel_requests values(a,p_request_id,v_payload,v_id,v_now);
  insert into app.duel_rematches values(v_id,previous.id);
  return v_id;
end;
$$;

create function public.rematch_duel_v1(p_request_id uuid,p_previous_challenge_id uuid,p_event_id uuid,
  p_expected_policy_version text,p_consent boolean)
returns uuid language sql security definer set search_path='' as $$
  select app.rematch_duel_at_v1(p_request_id,p_previous_challenge_id,p_event_id,p_expected_policy_version,p_consent);
$$;

-- All link operations share the original actor/request namespace. Exact retries
-- return their committed duel ID without issuing or reactivating a token.
create function app.change_duel_link_at_v1(p_operation text,p_request_id uuid,p_challenge_id uuid,
  p_token uuid default null,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); c public.duel_challenges; payload jsonb; recovered uuid; t timestamptz;
begin
  select * into c from public.duel_challenges where id=p_challenge_id;
  if not found or a is null or a<>c.creator_id then
    raise exception 'duel_link_unavailable' using errcode='42501';
  end if;
  perform app.duel_lock_pair_v1(c.creator_id,c.invitee_id);
  perform app.duel_proof_require_session_v1();
  payload:=jsonb_build_object('operation',p_operation,'challenge_id',c.id,'token',p_token);
  recovered:=app.duel_recover_request_v1(a,p_request_id,payload);
  if recovered is not null then return recovered; end if;
  if p_operation='issue_duel_link_v1' then perform app.duel_admit_pair_v1(c.creator_id,c.invitee_id); end if;
  select * into strict c from public.duel_challenges where id=c.id for update;
  t:=coalesce(p_now,clock_timestamp());
  if not isfinite(t) or t<c.created_at then raise exception 'duel_invalid_clock' using errcode='22023'; end if;
  perform set_config('app.duel_write_v1','on',true);
  if p_operation='issue_duel_link_v1' and p_token is null then
    if c.status<>'invited' or t>=c.accept_by or exists(select 1 from app.duel_lifecycle_closures where challenge_id=c.id) or exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then raise exception 'duel_link_unavailable' using errcode='55000'; end if;
    update app.duel_invitation_links set revoked_at=t where challenge_id=c.id and revoked_at is null;
    insert into app.duel_invitation_links(challenge_id,created_at,expires_at) values(c.id,t,least(c.accept_by,t+interval '24 hours'));
  elsif p_operation='revoke_duel_link_v1' and p_token is not null then
    if not exists(select 1 from app.duel_invitation_links where token=p_token and challenge_id=c.id) then
      raise exception 'duel_link_unavailable' using errcode='42501';
    end if;
    update app.duel_invitation_links set revoked_at=t where token=p_token and revoked_at is null;
  else raise exception 'duel_invalid_operation' using errcode='22023'; end if;
  insert into app.duel_requests values(a,p_request_id,payload,c.id,t);
  return c.id;
end; $$;
create function public.issue_duel_link_v1(p_request_id uuid,p_challenge_id uuid)
returns uuid language sql security definer set search_path='' as $$
  select app.change_duel_link_at_v1('issue_duel_link_v1',p_request_id,p_challenge_id);
$$;
create function public.revoke_duel_link_v1(p_request_id uuid,p_challenge_id uuid,p_token uuid)
returns uuid language sql security definer set search_path='' as $$
  select app.change_duel_link_at_v1('revoke_duel_link_v1',p_request_id,p_challenge_id,p_token);
$$;

-- A token is a locator, never authorization. No public preview or proof read.
-- Pair locks also serialize with friendship/block/deletion and acceptance.
create function app.read_duel_link_at_v1(p_challenge_id uuid,p_token uuid,p_now timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); c public.duel_challenges; l app.duel_invitation_links; t timestamptz;
begin
  if p_token is not null then
    select * into l from app.duel_invitation_links where token=p_token;
    p_challenge_id:=l.challenge_id;
  end if;
  select * into c from public.duel_challenges where id=p_challenge_id;
  if not found or a is null or (p_token is null and a<>c.creator_id) or (p_token is not null and a<>c.invitee_id) then
    raise exception 'duel_link_unavailable' using errcode='42501';
  end if;
  perform app.duel_lock_pair_v1(c.creator_id,c.invitee_id);
  perform app.duel_proof_require_session_v1();
  select * into strict c from public.duel_challenges where id=c.id for update;
  if not app.is_active_actor(c.creator_id) or not app.is_active_actor(c.invitee_id)
    or not app.is_friend(c.creator_id,c.invitee_id) or app.is_blocked_either_way(c.creator_id,c.invitee_id) then
    raise exception 'duel_link_unavailable' using errcode='42501';
  end if;
  t:=coalesce(p_now,clock_timestamp());
  if not isfinite(t) then raise exception 'duel_invalid_clock' using errcode='22023'; end if;
  select * into l from app.duel_invitation_links where challenge_id=c.id and revoked_at is null
    and (p_token is null or token=p_token) and t>=created_at and t<expires_at;
  if not found or c.status<>'invited' or t>=c.accept_by or exists(select 1 from app.duel_lifecycle_closures where challenge_id=c.id) or exists(select 1 from app.duel_lifecycle_results where challenge_id=c.id) then
    if p_token is null then return null; end if;
    raise exception 'duel_link_unavailable' using errcode='42501';
  end if;
  if p_token is not null then return jsonb_build_object('challengeId',c.id); end if;
  return jsonb_build_object('challengeId',c.id,'token',l.token,'expiresAt',l.expires_at);
end; $$;
create function public.get_my_duel_link_v1(p_challenge_id uuid) returns jsonb
language sql security definer set search_path='' as $$
  select app.read_duel_link_at_v1(p_challenge_id,null);
$$;
create function public.resolve_duel_link_v1(p_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if p_token is null then raise exception 'duel_link_unavailable' using errcode='42501'; end if;
  return app.read_duel_link_at_v1(null,p_token);
end; $$;

revoke all on function app.duel_link_guard_v1(),
 app.rematch_duel_at_v1(uuid,uuid,uuid,text,boolean,timestamptz),
 app.change_duel_link_at_v1(text,uuid,uuid,uuid,timestamptz),
 app.read_duel_link_at_v1(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.rematch_duel_v1(uuid,uuid,uuid,text,boolean),
 public.issue_duel_link_v1(uuid,uuid),public.revoke_duel_link_v1(uuid,uuid,uuid),
 public.get_my_duel_link_v1(uuid),public.resolve_duel_link_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.rematch_duel_v1(uuid,uuid,uuid,text,boolean),
 public.issue_duel_link_v1(uuid,uuid),public.revoke_duel_link_v1(uuid,uuid,uuid),
 public.get_my_duel_link_v1(uuid),public.resolve_duel_link_v1(uuid) to authenticated;
