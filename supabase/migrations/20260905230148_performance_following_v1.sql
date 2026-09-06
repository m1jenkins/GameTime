-- Phase 3(d): explicit, bilateral friend following of selected manual progress.
-- No private note, organizer proof, amount, result or external delivery path.
create table app.performance_following_runtime (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false
);
insert into app.performance_following_runtime values(true,false);
create table app.performance_following_grants (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  owner_id uuid not null references public.profiles(id),
  follower_id uuid not null references public.profiles(id),
  scope text not null check(scope='goal_and_selected_progress_v1'),
  status text not null check(status in ('pending','active','declined','revoked','unfollowed','expired')),
  revision integer not null default 1 check(revision>0),
  created_at timestamptz not null,
  expires_at timestamptz not null check(isfinite(expires_at) and expires_at>created_at),
  accepted_at timestamptz,
  ended_at timestamptz,
  reminder_at timestamptz check(isfinite(reminder_at)),
  check(owner_id<>follower_id),
  check((status in ('pending','active'))=(ended_at is null)),
  check(status<>'active' or accepted_at is not null)
);
create unique index performance_following_open_pair_idx on app.performance_following_grants(commitment_id,follower_id)
  where status in ('pending','active');
create index performance_following_owner_idx on app.performance_following_grants(owner_id,id);
create index performance_following_follower_idx on app.performance_following_grants(follower_id,id);
create index performance_following_commitment_idx on app.performance_following_grants(commitment_id,id);
create table app.performance_following_publications (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  sequence integer not null check(sequence between 1 and 512),
  progress_sequence integer not null,
  card jsonb not null,
  published_at timestamptz not null,
  retracted_at timestamptz,
  unique(commitment_id,sequence),
  foreign key(commitment_id,progress_sequence) references app.performance_progress_entries(commitment_id,sequence)
);
create index performance_following_progress_idx on app.performance_following_publications(commitment_id,progress_sequence);
create table app.performance_following_content (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  revision integer not null check(revision>0)
);
create table app.performance_following_reactions (
  follow_id uuid not null references app.performance_following_grants(id),
  publication_id uuid not null references app.performance_following_publications(id),
  code text check(code in ('cheer','well_done','keep_going')),
  recorded_at timestamptz not null,
  primary key(follow_id,publication_id)
);
create index performance_following_reaction_publication_idx on app.performance_following_reactions(publication_id);
create table app.performance_following_cases (
  id uuid primary key default extensions.gen_random_uuid(),
  follow_id uuid not null references app.performance_following_grants(id),
  reporter_id uuid not null references public.profiles(id),
  category text not null check(category in ('pressure','harassment','privacy','support')),
  note text not null check(char_length(note) between 1 and 500 and note=btrim(note) and note !~ '[[:cntrl:]]'),
  created_at timestamptz not null,
  resolution text check(resolution in ('guidance_recorded','action_recorded','no_action')),
  resolved_at timestamptz,
  check((resolution is null)=(resolved_at is null))
);
create index performance_following_case_follow_idx on app.performance_following_cases(follow_id);
create index performance_following_case_reporter_idx on app.performance_following_cases(reporter_id,id);
create table app.performance_following_support_grants (
  case_id uuid not null references app.performance_following_cases(id),
  operator_id uuid not null references public.profiles(id),
  expires_at timestamptz not null check(isfinite(expires_at)),
  revoked_at timestamptz,
  primary key(case_id,operator_id)
);
create index performance_following_operator_idx on app.performance_following_support_grants(operator_id);
create table app.performance_following_requests (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  payload jsonb not null check(octet_length(payload::text)<=8192),
  result jsonb not null,
  primary key(actor_id,request_id)
);
create index performance_following_request_commitment_idx on app.performance_following_requests(commitment_id);
create table app.performance_following_retention (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  scope text not null default 'performance_following_v1' check(scope='performance_following_v1'),
  held_at timestamptz not null default clock_timestamp()
);
create table app.performance_following_audit (
  id bigint generated always as identity primary key,
  kind text not null,
  subject_id uuid,
  actor_id uuid references public.profiles(id),
  recorded_at timestamptz not null default clock_timestamp()
);
create index performance_following_audit_actor_idx on app.performance_following_audit(actor_id);

create function app.performance_following_guard_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if current_user<>pg_get_userbyid((select relowner from pg_class where oid=tg_relid))
    or current_setting('app.performance_following_write_v1',true) is distinct from 'on' then
    raise exception 'performance_following_write_forbidden' using errcode='42501'; end if;
  if tg_op in ('DELETE','TRUNCATE') or (tg_op='UPDATE' and tg_table_name in
    ('performance_following_requests','performance_following_retention','performance_following_audit')) then
    raise exception 'performance_following_history_retained' using errcode='23001'; end if;
  if tg_op='UPDATE' then
    if tg_table_name='performance_following_grants' and
      (to_jsonb(new)-array['status','revision','accepted_at','ended_at','reminder_at']) is distinct from
      (to_jsonb(old)-array['status','revision','accepted_at','ended_at','reminder_at']) then
      raise exception 'performance_following_consent_immutable' using errcode='23001'; end if;
    if tg_table_name='performance_following_grants' then
      if (old.status not in ('pending','active') and new.status<>old.status)
        or (old.status='active' and new.status='pending')
        or (old.accepted_at is not null and new.accepted_at is distinct from old.accepted_at)
        or (old.ended_at is not null and new.ended_at is distinct from old.ended_at)
        or new.revision<>old.revision+1 then
        raise exception 'performance_following_transition_immutable' using errcode='23001'; end if;
    end if;
    if tg_table_name='performance_following_publications' and
      ((to_jsonb(new)-'retracted_at') is distinct from (to_jsonb(old)-'retracted_at') or to_jsonb(old)->>'retracted_at' is not null) then
      raise exception 'performance_following_publication_immutable' using errcode='23001'; end if;
    if tg_table_name='performance_following_cases' and
      ((to_jsonb(new)-array['resolution','resolved_at']) is distinct from (to_jsonb(old)-array['resolution','resolved_at'])
        or to_jsonb(old)->>'resolution' is not null) then
      raise exception 'performance_following_case_immutable' using errcode='23001'; end if;
  end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['runtime','grants','publications','content','reactions','cases','support_grants','requests','retention','audit'] loop
    execute format('alter table app.performance_following_%I enable row level security',t);
    execute format('revoke all on app.performance_following_%I from public,anon,authenticated,service_role',t);
    execute format('create trigger performance_following_guard before insert or update or delete on app.performance_following_%I
      for each row execute function app.performance_following_guard_v1()',t);
    execute format('create trigger performance_following_truncate before truncate on app.performance_following_%I
      for each statement execute function app.performance_following_guard_v1()',t);
  end loop;
end; $$;
revoke all on sequence app.performance_following_audit_id_seq from public,anon,authenticated,service_role;

create function public.set_commitment_following_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$ begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'performance_following_invalid_gate' using errcode='22023'; end if;
  perform set_config('app.performance_following_write_v1','on',true);
  update app.performance_following_runtime set enabled=p_enabled where singleton;
  insert into app.performance_following_audit(kind) values(case when p_enabled then 'enabled' else 'disabled' end);
  return p_enabled;
end; $$;

-- Pair profiles in UUID order -> caller session -> runtime -> agreement.
-- Tombstoned peers may be locked for safe exits/reporting; only an active caller
-- can act. Live sharing separately requires both actors, friendship and no block.
create function app.performance_following_lock_v1(p_commitment uuid,p_follower uuid default null)
returns app.performance_commitment_agreements language plpgsql set search_path='' as $$
declare c app.performance_commitment_agreements; a uuid:=auth.uid();
begin
  if current_setting('role')<>'authenticated' or a is null then
    raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  select * into c from app.performance_commitment_agreements where id=p_commitment;
  if not found or (a<>c.actor_id and (p_follower is null or a<>p_follower)) then
    raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  perform 1 from public.profiles where id=any(array[c.actor_id,p_follower]) order by id for update;
  perform app.performance_commitment_lock_actor_v1();
  perform 1 from app.performance_following_runtime where singleton for share;
  select * into c from app.performance_commitment_agreements where id=p_commitment for update;
  perform app.performance_commitment_lock_actor_v1();
  return c;
end; $$;
create function app.performance_following_pair_allowed_v1(g app.performance_following_grants) returns boolean
language sql stable set search_path='' as $$
  select app.is_active_actor(g.owner_id) and app.is_active_actor(g.follower_id)
    and app.is_friend(g.owner_id,g.follower_id) and not app.is_blocked_either_way(g.owner_id,g.follower_id)
$$;
create function app.performance_following_replay_v1(p_request uuid,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$ declare r app.performance_following_requests; begin
  if p_request is null then raise exception 'performance_following_request_required' using errcode='22023'; end if;
  select * into r from app.performance_following_requests where actor_id=auth.uid() and request_id=p_request;
  if found then
    if r.payload is distinct from p_payload then raise exception 'performance_following_request_conflict' using errcode='22023'; end if;
    return r.result;
  end if;
  return null;
end; $$;
create function app.performance_following_save_v1(p_request uuid,p_commitment uuid,p_payload jsonb,p_result jsonb) returns jsonb
language plpgsql set search_path='' as $$ begin
  perform set_config('app.performance_following_write_v1','on',true);
  insert into app.performance_following_retention(commitment_id) values(p_commitment) on conflict do nothing;
  insert into app.performance_following_requests values(auth.uid(),p_request,p_commitment,p_payload,p_result);
  insert into app.performance_following_audit(kind,subject_id,actor_id) values(p_payload->>'operation',p_commitment,auth.uid());
  return p_result;
end; $$;

create function public.invite_commitment_follower_v1(p_request_id uuid,p_commitment_id uuid,p_friend_id uuid,
  p_scope text,p_consent boolean) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; p jsonb; r jsonb; n timestamptz;
begin
  c:=app.performance_following_lock_v1(p_commitment_id,p_friend_id);
  if auth.uid()<>c.actor_id then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  p:=jsonb_build_object('operation','invite','commitment_id',c.id,'friend_id',p_friend_id,'scope',p_scope,'consent',p_consent);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  n:=clock_timestamp();
  g.owner_id:=c.actor_id; g.follower_id:=p_friend_id;
  if p_friend_id is null or p_friend_id=c.actor_id or not app.performance_following_pair_allowed_v1(g)
    or c.status<>'open' or n>=c.deadline_at or not(select enabled from app.performance_following_runtime where singleton) then
    raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  if p_scope is distinct from 'goal_and_selected_progress_v1' or p_consent is distinct from true then
    raise exception 'performance_following_consent_required' using errcode='22023'; end if;
  perform set_config('app.performance_following_write_v1','on',true);
  update app.performance_following_grants set status='expired',ended_at=n,reminder_at=null,revision=revision+1
    where commitment_id=c.id and status='pending' and expires_at<=n;
  if exists(select 1 from app.performance_following_grants where commitment_id=c.id and follower_id=p_friend_id and status in ('pending','active')) then
    raise exception 'performance_following_already_open' using errcode='22023'; end if;
  if (select count(*) from app.performance_following_grants where commitment_id=c.id)>=128
    or (select count(*) from app.performance_following_grants where commitment_id=c.id and status in ('pending','active'))>=32 then
    raise exception 'performance_following_capacity' using errcode='54000'; end if;
  insert into app.performance_following_grants(commitment_id,owner_id,follower_id,scope,status,created_at,expires_at)
    values(c.id,c.actor_id,p_friend_id,p_scope,'pending',n,least(n+interval '7 days',c.deadline_at)) returning * into g;
  return app.performance_following_save_v1(p_request_id,c.id,p,jsonb_build_object('follow_id',g.id,'status',g.status,'revision',g.revision));
end; $$;

create function app.mutate_performance_following_v1(p_request uuid,p_follow uuid,p_action text,p_reminder timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; p jsonb; r jsonb; n timestamptz;
begin
  select * into g from app.performance_following_grants where id=p_follow;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(g.commitment_id,g.follower_id);
  select * into g from app.performance_following_grants where id=p_follow for update;
  perform app.performance_commitment_lock_actor_v1(); n:=clock_timestamp();
  p:=jsonb_build_object('operation',p_action,'follow_id',p_follow,'reminder_at',p_reminder);
  r:=app.performance_following_replay_v1(p_request,p); if r is not null then return r; end if;
  if (p_action='revoke' and auth.uid()<>g.owner_id) or (p_action<>'revoke' and auth.uid()<>g.follower_id) then
    raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  perform set_config('app.performance_following_write_v1','on',true);
  if p_action='accept' or (p_action='reminder' and p_reminder is not null) then
    if not app.performance_following_pair_allowed_v1(g) or c.status<>'open' or n>=c.deadline_at
      or not(select enabled from app.performance_following_runtime where singleton) then
      raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  end if;
  if p_action='accept' then
    if g.status<>'pending' or n>=g.expires_at then raise exception 'performance_following_invitation_closed' using errcode='22023'; end if;
    update app.performance_following_grants set status='active',accepted_at=n,revision=revision+1 where id=g.id returning * into g;
  elsif p_action in ('revoke','decline','unfollow') then
    if p_action='decline' and g.status='active' then raise exception 'performance_following_invalid_transition' using errcode='22023'; end if;
    update app.performance_following_grants set status=case p_action when 'revoke' then 'revoked' when 'decline' then 'declined' else 'unfollowed' end,
      ended_at=n,reminder_at=null,revision=revision+1 where id=g.id and status in ('pending','active') returning * into g;
    if not found then select * into g from app.performance_following_grants where id=p_follow; end if;
  elsif p_action='reminder' then
    if p_reminder is not null and (g.status<>'active' or not isfinite(p_reminder) or p_reminder<=n
      or p_reminder>=c.deadline_at or p_reminder>n+interval '30 days') then
      raise exception 'performance_following_invalid_reminder' using errcode='22023'; end if;
    update app.performance_following_grants set reminder_at=p_reminder,revision=revision+1 where id=g.id returning * into g;
  else raise exception 'performance_following_invalid_action' using errcode='22023'; end if;
  return app.performance_following_save_v1(p_request,c.id,p,jsonb_build_object('follow_id',g.id,'status',g.status,'revision',g.revision,'reminder_at',g.reminder_at));
end; $$;
create function public.respond_commitment_follow_v1(p_request_id uuid,p_follow_id uuid,p_accept boolean) returns jsonb
language plpgsql security definer set search_path='' as $$ begin
  if p_accept is null then raise exception 'performance_following_consent_required' using errcode='22023'; end if;
  return app.mutate_performance_following_v1(p_request_id,p_follow_id,case when p_accept then 'accept' else 'decline' end);
end; $$;
create function public.end_commitment_follow_v1(p_request_id uuid,p_follow_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path='' as $$ begin
  if p_action is null or p_action not in ('revoke','unfollow') then raise exception 'performance_following_invalid_action' using errcode='22023'; end if;
  return app.mutate_performance_following_v1(p_request_id,p_follow_id,p_action);
end; $$;
create function public.set_commitment_follow_reminder_v1(p_request_id uuid,p_follow_id uuid,p_reminder_at timestamptz) returns jsonb
language sql security definer set search_path='' as $$
  select app.mutate_performance_following_v1(p_request_id,p_follow_id,'reminder',p_reminder_at)
$$;

create function public.publish_commitment_progress_v1(p_request_id uuid,p_commitment_id uuid,p_progress_sequence integer)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; e app.performance_progress_entries; m app.performance_progress_milestones;
  p jsonb; r jsonb; card jsonb; seq integer; pub uuid; n timestamptz;
begin
  c:=app.performance_following_lock_v1(p_commitment_id);
  p:=jsonb_build_object('operation','publish','commitment_id',c.id,'progress_sequence',p_progress_sequence);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  n:=clock_timestamp();
  if c.status<>'open' or n>=c.deadline_at or not(select enabled from app.performance_following_runtime where singleton) then
    raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  select * into e from app.performance_progress_entries where commitment_id=c.id and sequence=p_progress_sequence;
  if not found then raise exception 'performance_following_progress_unavailable' using errcode='42501'; end if;
  if exists(select 1 from app.performance_following_publications where commitment_id=c.id and progress_sequence=e.sequence and retracted_at is null) then
    raise exception 'performance_following_already_published' using errcode='22023'; end if;
  select coalesce(max(sequence),0)+1 into seq from app.performance_following_publications where commitment_id=c.id;
  if seq>512 then raise exception 'performance_following_publications_full' using errcode='54000'; end if;
  -- Explicit whitelist: never copy the entry row, note, request or proof JSON.
  card:=jsonb_build_object('kind',e.kind,'occurred_at',e.occurred_at,'recorded_at',e.recorded_at,
    'provenance','owner_reported','counts_as_proof',false);
  if e.kind<>'check_in' then
    select * into m from app.performance_progress_milestones where commitment_id=c.id and id=e.milestone_id;
    card:=card||jsonb_build_object('milestone_title',m.title,'milestone_due_at',m.due_at,'status',e.status);
  end if;
  perform set_config('app.performance_following_write_v1','on',true);
  insert into app.performance_following_publications(commitment_id,sequence,progress_sequence,card,published_at)
    values(c.id,seq,e.sequence,card,n) returning id into pub;
  insert into app.performance_following_content values(c.id,1)
    on conflict(commitment_id) do update set revision=app.performance_following_content.revision+1;
  return app.performance_following_save_v1(p_request_id,c.id,p,jsonb_build_object('publication_id',pub,'sequence',seq,'published_at',n));
end; $$;
create function public.retract_commitment_progress_v1(p_request_id uuid,p_publication_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; pub app.performance_following_publications; p jsonb; r jsonb;
begin
  select * into pub from app.performance_following_publications where id=p_publication_id;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(pub.commitment_id);
  p:=jsonb_build_object('operation','retract','publication_id',p_publication_id);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  perform set_config('app.performance_following_write_v1','on',true);
  update app.performance_following_publications set retracted_at=clock_timestamp()
    where id=p_publication_id and retracted_at is null returning * into pub;
  if found then
    update app.performance_following_content set revision=revision+1 where commitment_id=c.id;
  else select * into pub from app.performance_following_publications where id=p_publication_id;
  end if;
  return app.performance_following_save_v1(p_request_id,c.id,p,jsonb_build_object('publication_id',pub.id,'retracted_at',pub.retracted_at));
end; $$;

-- A changed publication set requires restarting pagination; no old cursor may
-- reveal a retracted card. Reactions are current annotations, not proof/history.
create function app.performance_following_cards_v1(p_commitment uuid,p_follow uuid,p_limit integer,p_after integer,p_revision integer)
returns jsonb language plpgsql set search_path='' set timezone='UTC' as $$
declare rev integer; next_seq integer; cards jsonb; more boolean;
begin
  select coalesce((select revision from app.performance_following_content where commitment_id=p_commitment),0) into rev;
  if p_limit is null or p_limit not between 1 and 50 or p_after is null or p_after<0 or p_after>512
    or (p_after>0 and p_revision is null) then
    raise exception 'performance_following_invalid_page' using errcode='22023'; end if;
  if p_revision is not null and p_revision<>rev then
    raise exception 'performance_following_refresh_required' using errcode='22023'; end if;
  select coalesce(jsonb_agg(pub.card||jsonb_build_object('publication_id',pub.id,'sequence',pub.sequence,'published_at',pub.published_at,
    'your_reaction',(select code from app.performance_following_reactions where follow_id=p_follow and publication_id=pub.id),
    'reaction_counts',case when p_follow is null then (select coalesce(jsonb_object_agg(x.code,x.n),'{}'::jsonb) from (
      select rx.code,count(*) as n from app.performance_following_reactions rx join app.performance_following_grants g on g.id=rx.follow_id
      where rx.publication_id=pub.id and rx.code is not null and g.status='active' and app.performance_following_pair_allowed_v1(g)
      group by rx.code) x) end)
    order by pub.sequence),'[]'::jsonb),coalesce(max(pub.sequence),p_after) into cards,next_seq
    from (select * from app.performance_following_publications where commitment_id=p_commitment and retracted_at is null
      and sequence>p_after order by sequence limit p_limit) pub;
  select exists(select 1 from app.performance_following_publications where commitment_id=p_commitment and retracted_at is null and sequence>next_seq) into more;
  return jsonb_build_object('cards',cards,'content_revision',rev,'next_after_sequence',next_seq,'has_more',more);
end; $$;
create function public.get_commitment_publications_v1(p_commitment_id uuid,p_limit integer default 50,
  p_after_sequence integer default 0,p_content_revision integer default null) returns jsonb
language plpgsql security definer set search_path='' as $$ declare c app.performance_commitment_agreements; begin
  c:=app.performance_following_lock_v1(p_commitment_id);
  return jsonb_build_object('commitment_id',c.id)||app.performance_following_cards_v1(c.id,null,p_limit,p_after_sequence,p_content_revision);
end; $$;
create function public.get_commitment_follow_v1(p_follow_id uuid,p_limit integer default 50,
  p_after_sequence integer default 0,p_content_revision integer default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; n timestamptz; r jsonb;
begin
  select * into g from app.performance_following_grants where id=p_follow_id;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(g.commitment_id,g.follower_id);
  select * into g from app.performance_following_grants where id=p_follow_id for update;
  perform app.performance_commitment_lock_actor_v1(); n:=clock_timestamp();
  r:=jsonb_build_object('follow_id',g.id,'access_revision',g.revision,'server_now',n,
    'access_allowed',false,'cards','[]'::jsonb,'reminder_due',false);
  if not app.performance_following_pair_allowed_v1(g) or c.status<>'open' or g.status not in ('pending','active')
    or (g.status='pending' and g.expires_at<=n) then
    return r||jsonb_build_object('status','unavailable');
  end if;
  if g.status='pending' then
    return r||jsonb_build_object('status','pending','owner_id',g.owner_id,'scope',g.scope,'expires_at',g.expires_at);
  end if;
  -- Goal facts were explicitly included in owner consent. No whole agreement
  -- serialization: amounts, recipient, requests and proof never enter this DTO.
  return r||jsonb_build_object('status','active','access_allowed',true,'owner_id',g.owner_id,'scope',g.scope,
    'goal',jsonb_build_object('distance_meters',5000,'target_seconds',c.target_seconds,'comparison','strictly_less_than',
      'starts_at',c.starts_at,'deadline_at',c.deadline_at,'display_timezone',c.display_timezone),
    'reminder_at',case when auth.uid()=g.follower_id then g.reminder_at end,
    'reminder_due',coalesce(auth.uid()=g.follower_id and g.reminder_at<=n and n<c.deadline_at
      and (select enabled from app.performance_following_runtime where singleton),false))
    ||app.performance_following_cards_v1(c.id,case when auth.uid()=g.follower_id then g.id end,p_limit,p_after_sequence,p_content_revision);
end; $$;

-- Locator-only discovery. Each detail read reauthorizes under pair locks. This
-- list carries no goal/card/profile text, reminder or other person's reaction.
create function public.list_commitment_follows_v1(p_limit integer default 50,p_after_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$ declare a uuid; rows jsonb; begin
  a:=app.performance_commitment_lock_actor_v1();
  if p_limit is null or p_limit not between 1 and 50 then raise exception 'performance_following_invalid_page' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('follow_id',g.id,'direction',case when g.owner_id=a then 'outgoing' else 'incoming' end)
    order by g.id),'[]'::jsonb) into rows from (select id,owner_id from app.performance_following_grants
      where (owner_id=a or follower_id=a) and (p_after_id is null or id>p_after_id) order by id limit p_limit) g;
  return jsonb_build_object('follows',rows,'next_after_id',rows->-1->>'follow_id');
end; $$;

create function public.react_commitment_progress_v1(p_request_id uuid,p_follow_id uuid,p_publication_id uuid,p_code text)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; p jsonb; r jsonb; n timestamptz;
begin
  select * into g from app.performance_following_grants where id=p_follow_id;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(g.commitment_id,g.follower_id);
  if auth.uid()<>g.follower_id then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  select * into g from app.performance_following_grants where id=p_follow_id for update;
  perform app.performance_commitment_lock_actor_v1(); n:=clock_timestamp();
  p:=jsonb_build_object('operation','react','follow_id',p_follow_id,'publication_id',p_publication_id,'code',p_code);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  if p_code is not null and p_code not in ('cheer','well_done','keep_going') then
    raise exception 'performance_following_invalid_reaction' using errcode='22023'; end if;
  if p_code is not null then
    if g.status<>'active' or not app.performance_following_pair_allowed_v1(g) or c.status<>'open' or n>=c.deadline_at
      or not(select enabled from app.performance_following_runtime where singleton)
      or not exists(select 1 from app.performance_following_publications where id=p_publication_id and commitment_id=c.id and retracted_at is null) then
      raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  elsif not exists(select 1 from app.performance_following_reactions where follow_id=g.id and publication_id=p_publication_id) then
    raise exception 'performance_following_unavailable' using errcode='42501';
  end if;
  perform set_config('app.performance_following_write_v1','on',true);
  insert into app.performance_following_reactions values(g.id,p_publication_id,p_code,n)
    on conflict(follow_id,publication_id) do update set code=excluded.code,recorded_at=excluded.recorded_at;
  return app.performance_following_save_v1(p_request_id,c.id,p,
    jsonb_build_object('follow_id',g.id,'publication_id',p_publication_id,'code',p_code,'recorded_at',n));
end; $$;

-- Safety events permanently end existing grants. Unblock/re-friending requires
-- a fresh invitation and follower consent. These triggers never acquire a peer
-- profile: the existing social/deletion caller lock already excludes pair reads.
create function app.performance_following_sever_v1() returns trigger
language plpgsql security definer set search_path='' as $$ declare x uuid; y uuid; cid uuid; g record; begin
  if tg_table_name='friendships' then
    if tg_op='UPDATE' and (old.status<>'accepted' or new.status='accepted') then return null; end if;
    x:=old.user_a; y:=old.user_b;
  elsif tg_table_name='blocks' then x:=new.blocker_id; y:=new.blocked_id;
  elsif tg_table_name='profiles' then
    if old.deleted_at is not null or new.deleted_at is null then return null; end if;
    x:=new.id;
  else
    if old.status<>'open' or new.status='open' then return null; end if;
    cid:=new.id;
  end if;
  perform set_config('app.performance_following_write_v1','on',true);
  for g in select id from app.performance_following_grants
    where status in ('pending','active') and ((cid is not null and commitment_id=cid)
      or (cid is null and y is null and x in (owner_id,follower_id))
      or (y is not null and ((owner_id=x and follower_id=y) or (owner_id=y and follower_id=x)))) order by id for update loop
    update app.performance_following_grants set status='revoked',ended_at=clock_timestamp(),reminder_at=null,revision=revision+1 where id=g.id;
  end loop;
  return null;
end; $$;
create function app.performance_following_grant_audit_v1() returns trigger
language plpgsql security definer set search_path='' as $$ begin
  if tg_op='INSERT' or new.status is distinct from old.status then
    perform set_config('app.performance_following_write_v1','on',true);
    insert into app.performance_following_audit(kind,subject_id) values('follow_'||new.status,new.id);
  end if;
  return null;
end; $$;
create trigger performance_following_status_audit after insert or update on app.performance_following_grants
  for each row execute function app.performance_following_grant_audit_v1();
create trigger performance_following_friend_sever after delete or update on public.friendships
  for each row execute function app.performance_following_sever_v1();
create trigger performance_following_block_sever after insert on public.blocks
  for each row execute function app.performance_following_sever_v1();
create trigger performance_following_deleted_sever after update of deleted_at on public.profiles
  for each row execute function app.performance_following_sever_v1();
create trigger performance_following_closed_sever after update of status on app.performance_commitment_agreements
  for each row execute function app.performance_following_sever_v1();

create function public.block_commitment_follow_v1(p_request_id uuid,p_follow_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; peer uuid; p jsonb; r jsonb;
begin
  select * into g from app.performance_following_grants where id=p_follow_id;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(g.commitment_id,g.follower_id);
  p:=jsonb_build_object('operation','block','follow_id',p_follow_id);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  peer:=case when auth.uid()=g.owner_id then g.follower_id else g.owner_id end;
  -- A deleted peer is already inaccessible. Preserve the person's safe action
  -- without trying to recreate a social artifact referencing an inactive actor.
  if app.is_active_actor(peer) then
    insert into public.blocks(blocker_id,blocked_id) values(auth.uid(),peer) on conflict do nothing;
  end if;
  return app.performance_following_save_v1(p_request_id,c.id,p,jsonb_build_object('follow_id',g.id,'contact_disabled',true));
end; $$;
create function public.report_commitment_follow_v1(p_request_id uuid,p_follow_id uuid,p_category text,p_note text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; g app.performance_following_grants; p jsonb; r jsonb; cid uuid; n timestamptz;
begin
  select * into g from app.performance_following_grants where id=p_follow_id;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  c:=app.performance_following_lock_v1(g.commitment_id,g.follower_id);
  if p_note is null or char_length(p_note) not between 1 and 500 or p_note<>btrim(p_note) or p_note ~ '[[:cntrl:]]'
    or p_category is null or p_category not in ('pressure','harassment','privacy','support') then
    raise exception 'performance_following_invalid_report' using errcode='22023'; end if;
  p:=jsonb_build_object('operation','report','follow_id',p_follow_id,'category',p_category,'note',p_note);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  if (select count(*) from app.performance_following_cases where follow_id=g.id and reporter_id=auth.uid())>=16 then
    raise exception 'performance_following_reports_full' using errcode='54000'; end if;
  perform set_config('app.performance_following_write_v1','on',true); n:=clock_timestamp();
  insert into app.performance_following_cases(follow_id,reporter_id,category,note,created_at)
    values(g.id,auth.uid(),p_category,p_note,n) returning id into cid;
  return app.performance_following_save_v1(p_request_id,c.id,p,jsonb_build_object('case_id',cid,'status','recorded','recorded_at',n));
end; $$;
create function public.get_commitment_follow_report_v1(p_case_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare a uuid; k app.performance_following_cases; begin
  a:=app.performance_commitment_lock_actor_v1();
  select * into k from app.performance_following_cases where id=p_case_id and reporter_id=a for share;
  if not found then raise exception 'performance_following_unavailable' using errcode='42501'; end if;
  perform app.performance_commitment_lock_actor_v1();
  return jsonb_build_object('case_id',k.id,'category',k.category,'note',k.note,'recorded_at',k.created_at,
    'resolution',k.resolution,'resolved_at',k.resolved_at);
end; $$;
create function public.list_commitment_follow_reports_v1(p_limit integer default 50,p_after_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$ declare a uuid; rows jsonb; begin
  a:=app.performance_commitment_lock_actor_v1();
  if p_limit is null or p_limit not between 1 and 50 then raise exception 'performance_following_invalid_page' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('case_id',k.id) order by k.id),'[]'::jsonb) into rows
    from (select id from app.performance_following_cases where reporter_id=a and (p_after_id is null or id>p_after_id)
      order by id limit p_limit) k;
  return jsonb_build_object('cases',rows,'next_after_id',rows->-1->>'case_id');
end; $$;

-- Server-owned, case-specific, expiring support access. Only the submitted
-- report is available; assignment never grants private progress/proof access.
create function public.set_commitment_follow_support_v1(p_case_id uuid,p_operator_id uuid,p_expires_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare k app.performance_following_cases; g app.performance_following_grants; n timestamptz;
begin
  perform app.duel_require_service_v1();
  select * into k from app.performance_following_cases where id=p_case_id;
  select * into g from app.performance_following_grants where id=k.follow_id;
  if k.id is null or p_operator_id is null or p_operator_id in (g.owner_id,g.follower_id) then
    raise exception 'performance_following_support_unavailable' using errcode='42501'; end if;
  perform 1 from public.profiles where id=any(array[g.owner_id,g.follower_id,p_operator_id]) order by id for update;
  perform 1 from app.performance_following_runtime where singleton for share;
  perform 1 from app.performance_commitment_agreements where id=g.commitment_id for update;
  perform 1 from app.performance_following_cases where id=k.id for update;
  perform set_config('app.performance_following_write_v1','on',true); n:=clock_timestamp();
  if p_expires_at is null then
    update app.performance_following_support_grants set revoked_at=n where case_id=k.id and operator_id=p_operator_id;
  else
    if not app.is_active_actor(p_operator_id) or not(select enabled from app.performance_following_runtime where singleton)
      or not isfinite(p_expires_at) or p_expires_at<=n or p_expires_at>n+interval '7 days' then
      raise exception 'performance_following_support_unavailable' using errcode='42501'; end if;
    insert into app.performance_following_support_grants values(k.id,p_operator_id,p_expires_at,null)
      on conflict(case_id,operator_id) do update set expires_at=excluded.expires_at,revoked_at=null;
  end if;
  insert into app.performance_following_audit(kind,subject_id,actor_id)
    values(case when p_expires_at is null then 'support_revoked' else 'support_granted' end,k.id,p_operator_id);
end; $$;
create function app.performance_following_support_lock_v1(p_case uuid) returns app.performance_following_cases
language plpgsql set search_path='' as $$
declare k app.performance_following_cases; g app.performance_following_grants; s app.performance_following_support_grants;
begin
  if current_setting('role')<>'authenticated' or auth.uid() is null then
    raise exception 'performance_following_support_unavailable' using errcode='42501'; end if;
  select * into k from app.performance_following_cases where id=p_case;
  select * into g from app.performance_following_grants where id=k.follow_id;
  if k.id is null or auth.uid() in (g.owner_id,g.follower_id) then
    raise exception 'performance_following_support_unavailable' using errcode='42501'; end if;
  perform 1 from public.profiles where id=any(array[g.owner_id,g.follower_id,auth.uid()]) order by id for update;
  perform app.performance_commitment_lock_actor_v1();
  perform 1 from app.performance_following_runtime where singleton for share;
  perform 1 from app.performance_commitment_agreements where id=g.commitment_id for update;
  select * into k from app.performance_following_cases where id=p_case for update;
  select * into s from app.performance_following_support_grants where case_id=k.id and operator_id=auth.uid() for share;
  perform app.performance_commitment_lock_actor_v1();
  if s.case_id is null or s.revoked_at is not null or s.expires_at<=clock_timestamp()
    or not(select enabled from app.performance_following_runtime where singleton) then
    raise exception 'performance_following_support_unavailable' using errcode='42501'; end if;
  return k;
end; $$;
create function public.read_commitment_follow_support_v1(p_case_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$ declare k app.performance_following_cases; begin
  k:=app.performance_following_support_lock_v1(p_case_id);
  perform set_config('app.performance_following_write_v1','on',true);
  insert into app.performance_following_audit(kind,subject_id,actor_id) values('support_read',k.id,auth.uid());
  return jsonb_build_object('case_id',k.id,'category',k.category,'note',k.note,'recorded_at',k.created_at,
    'resolution',k.resolution,'resolved_at',k.resolved_at);
end; $$;
create function public.resolve_commitment_follow_support_v1(p_request_id uuid,p_case_id uuid,p_resolution text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare k app.performance_following_cases; c uuid; p jsonb; r jsonb; n timestamptz; begin
  k:=app.performance_following_support_lock_v1(p_case_id);
  select commitment_id into c from app.performance_following_grants where id=k.follow_id;
  p:=jsonb_build_object('operation','support_resolve','case_id',p_case_id,'resolution',p_resolution);
  r:=app.performance_following_replay_v1(p_request_id,p); if r is not null then return r; end if;
  if p_resolution is null or p_resolution not in ('guidance_recorded','action_recorded','no_action') or k.resolution is not null then
    raise exception 'performance_following_invalid_resolution' using errcode='22023'; end if;
  perform set_config('app.performance_following_write_v1','on',true); n:=clock_timestamp();
  update app.performance_following_cases set resolution=p_resolution,resolved_at=n where id=k.id;
  return app.performance_following_save_v1(p_request_id,c,p,jsonb_build_object('case_id',k.id,'resolution',p_resolution,'resolved_at',n));
end; $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and (p.proname like '%performance_following%v1' or p.proname like '%commitment_follow%v1'
      or p.proname in ('publish_commitment_progress_v1','retract_commitment_progress_v1','react_commitment_progress_v1','get_commitment_publications_v1')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.set_commitment_following_enabled_v1(boolean),
  public.set_commitment_follow_support_v1(uuid,uuid,timestamptz) to service_role;
grant execute on function public.invite_commitment_follower_v1(uuid,uuid,uuid,text,boolean),
  public.respond_commitment_follow_v1(uuid,uuid,boolean),public.end_commitment_follow_v1(uuid,uuid,text),
  public.set_commitment_follow_reminder_v1(uuid,uuid,timestamptz),public.publish_commitment_progress_v1(uuid,uuid,integer),
  public.retract_commitment_progress_v1(uuid,uuid),public.get_commitment_publications_v1(uuid,integer,integer,integer),
  public.get_commitment_follow_v1(uuid,integer,integer,integer),public.list_commitment_follows_v1(integer,uuid),
  public.react_commitment_progress_v1(uuid,uuid,uuid,text),public.block_commitment_follow_v1(uuid,uuid),
  public.report_commitment_follow_v1(uuid,uuid,text,text),public.get_commitment_follow_report_v1(uuid),
  public.list_commitment_follow_reports_v1(integer,uuid),
  public.read_commitment_follow_support_v1(uuid),public.resolve_commitment_follow_support_v1(uuid,uuid,text) to authenticated;
