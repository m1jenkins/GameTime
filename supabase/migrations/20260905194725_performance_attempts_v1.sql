-- Phase 3(b): fictional nominated attempts and private reviewed corrections.
-- No result publisher, slot release, schedule, provider or settlement.
create table app.performance_attempt_runtime (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false
);
insert into app.performance_attempt_runtime values(true,false);
create table app.performance_attempt_events (
  id uuid primary key,
  starts_at timestamptz not null check(isfinite(starts_at)),
  ends_at timestamptz not null check(isfinite(ends_at) and ends_at>starts_at),
  source text not null default 'fixture_official_5k_v1' check(source='fixture_official_5k_v1'),
  distance_meters integer not null default 5000 check(distance_meters=5000)
);
create table app.performance_attempt_nominations (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  event_id uuid not null references app.performance_attempt_events(id),
  bib text not null check(bib ~ '^[A-Za-z0-9-]{1,32}$'),
  nominated_at timestamptz not null check(isfinite(nominated_at)),
  unique(commitment_id,event_id), unique(commitment_id,id)
);
create index performance_attempt_event_idx on app.performance_attempt_nominations(event_id);
create table app.performance_attempt_confirmations (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  kind text not null check(kind in ('complete_set','no_attempts')),
  attempt_ids uuid[] not null check(cardinality(attempt_ids)<=32)
);
create table app.performance_attempt_grants (
  id bigint generated always as identity primary key,
  request_id uuid not null unique,
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  reviewer_id uuid not null references public.profiles(id),
  enabled boolean not null,
  recorded_at timestamptz not null
);
create index performance_attempt_grant_current_idx on app.performance_attempt_grants(commitment_id,reviewer_id,id desc);
create index performance_attempt_grant_reviewer_idx on app.performance_attempt_grants(reviewer_id);
create table app.performance_attempt_sources (
  id uuid primary key,
  commitment_id uuid not null,
  attempt_id uuid not null,
  captured_at timestamptz not null check(isfinite(captured_at)),
  document jsonb not null check(jsonb_typeof(document)='object' and octet_length(document::text)<=4096),
  foreign key(commitment_id,attempt_id) references app.performance_attempt_nominations(commitment_id,id),
  unique(commitment_id,id)
);
create index performance_attempt_source_attempt_idx on app.performance_attempt_sources(commitment_id,attempt_id);
create table app.performance_attempt_revisions (
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  revision integer not null check(revision>0),
  attempt_id uuid not null,
  source_id uuid not null,
  supersedes_revision integer,
  reviewer_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.performance_attempt_grants(id),
  recorded_at timestamptz not null check(isfinite(recorded_at)),
  primary key(commitment_id,revision), unique(commitment_id,source_id),
  foreign key(commitment_id,attempt_id) references app.performance_attempt_nominations(commitment_id,id),
  foreign key(commitment_id,source_id) references app.performance_attempt_sources(commitment_id,id),
  foreign key(commitment_id,supersedes_revision) references app.performance_attempt_revisions(commitment_id,revision)
);
create index performance_attempt_revision_attempt_idx on app.performance_attempt_revisions(commitment_id,attempt_id,revision desc);
create index performance_attempt_revision_previous_idx on app.performance_attempt_revisions(commitment_id,supersedes_revision);
create index performance_attempt_revision_reviewer_idx on app.performance_attempt_revisions(reviewer_id);
create index performance_attempt_revision_grant_idx on app.performance_attempt_revisions(grant_id);
create table app.performance_attempt_requests (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  payload jsonb not null,
  result jsonb not null,
  primary key(actor_id,request_id)
);
create index performance_attempt_request_commitment_idx on app.performance_attempt_requests(commitment_id);
-- Explicit product retention scope. Local fixtures stay on hold until a later
-- result/review slice provides finality, case holds and an approved purge rule.
-- Neither deletion nor the legacy raw-evidence worker may shorten this hold.
create table app.performance_attempt_retention (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  scope text not null default 'performance_attempts_v1' check(scope='performance_attempts_v1'),
  reason text not null default 'awaiting_result_review_retention_policy'
    check(reason='awaiting_result_review_retention_policy')
);
create table app.performance_attempt_audit (
  id bigint generated always as identity primary key,
  commitment_id uuid references app.performance_commitment_agreements(id),
  actor_id uuid references public.profiles(id),
  operation text not null check(operation in ('gate_on','gate_off','source_read','snapshot_read')),
  source_id uuid references app.performance_attempt_sources(id),
  recorded_at timestamptz not null default clock_timestamp()
);
create index performance_attempt_audit_commitment_idx on app.performance_attempt_audit(commitment_id);
create index performance_attempt_audit_actor_idx on app.performance_attempt_audit(actor_id);
create index performance_attempt_audit_source_idx on app.performance_attempt_audit(source_id);

create function app.performance_attempt_guard_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
    or coalesce(current_setting('app.performance_attempt_write_v1',true),'')<>'on' then
    raise exception 'performance_attempt_rpc_required' using errcode='42501';
  end if;
  if tg_op<>'INSERT' and not(tg_op='UPDATE' and tg_table_name='performance_attempt_runtime') then
    raise exception 'performance_attempt_history_retained' using errcode='23001';
  end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['runtime','events','nominations','confirmations','grants','sources','revisions','requests','retention','audit'] loop
    execute format('alter table app.performance_attempt_%I enable row level security',t);
    execute format('revoke all on app.performance_attempt_%I from public,anon,authenticated,service_role',t);
    execute format('create trigger performance_attempt_guard before insert or update or delete on app.performance_attempt_%I
      for each row execute function app.performance_attempt_guard_v1()',t);
    execute format('create trigger performance_attempt_truncate before truncate on app.performance_attempt_%I
      for each statement execute function app.performance_attempt_guard_v1()',t);
  end loop;
end; $$;

create function public.set_commitment_attempts_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$ begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'performance_attempt_invalid_gate' using errcode='22023'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  update app.performance_attempt_runtime set enabled=p_enabled where singleton;
  insert into app.performance_attempt_audit(operation) values(case when p_enabled then 'gate_on' else 'gate_off' end);
  return p_enabled;
end; $$;
create function public.curate_commitment_fixture_event_v1(p_event_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$ declare e app.performance_attempt_events; begin
  perform app.duel_require_service_v1();
  perform 1 from app.performance_attempt_runtime where singleton for update;
  select * into e from app.performance_attempt_events where id=p_event_id;
  if found then
    if (e.starts_at,e.ends_at) is distinct from (p_starts_at,p_ends_at) then
      raise exception 'performance_attempt_event_conflict' using errcode='22023'; end if;
    return e.id;
  end if;
  if p_event_id is null or p_starts_at is null or p_ends_at is null or not isfinite(p_starts_at)
    or not isfinite(p_ends_at) or p_ends_at<=p_starts_at or p_ends_at>p_starts_at+interval '24 hours' then
    raise exception 'performance_attempt_invalid_event' using errcode='22023'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_events(id,starts_at,ends_at) values(p_event_id,p_starts_at,p_ends_at);
  return p_event_id;
end; $$;

-- Sorted profiles -> caller session -> runtime -> agreement on every path.
-- Recheck sessions after all blocking locks; no metadata-based authorization.
create function app.performance_attempt_lock_v1(p_commitment uuid,p_actor uuid)
returns app.performance_commitment_agreements language plpgsql set search_path='' as $$
declare c app.performance_commitment_agreements;
begin
  select * into c from app.performance_commitment_agreements where id=p_commitment;
  if not found then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  perform id from public.profiles where id in(c.actor_id,p_actor) order by id for update;
  if p_actor is not null then perform app.performance_commitment_lock_actor_v1(); end if;
  perform 1 from app.performance_attempt_runtime where singleton for share;
  select * into strict c from app.performance_commitment_agreements where id=p_commitment for update;
  if p_actor is not null then perform app.performance_commitment_lock_actor_v1(); end if;
  return c;
end; $$;
create function app.performance_attempt_open_v1(c app.performance_commitment_agreements) returns void
language plpgsql set search_path='' as $$ begin
  if c.status<>'open' or not app.is_active_actor(c.actor_id)
    or not (select enabled from app.performance_attempt_runtime where singleton) then
    raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
end; $$;
create function app.performance_attempt_reviewer_v1(c app.performance_commitment_agreements) returns bigint
language plpgsql set search_path='' as $$ declare g app.performance_attempt_grants; begin
  if auth.uid() is null or auth.uid()=c.actor_id or not app.is_active_actor(c.actor_id)
    or app.is_blocked_either_way(auth.uid(),c.actor_id) then
    raise exception 'performance_attempt_reviewer_required' using errcode='42501'; end if;
  select * into g from app.performance_attempt_grants where commitment_id=c.id and reviewer_id=auth.uid() order by id desc limit 1;
  if not found or not g.enabled then raise exception 'performance_attempt_reviewer_required' using errcode='42501'; end if;
  return g.id;
end; $$;
create function app.performance_attempt_recover_v1(p_request uuid,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$ declare r app.performance_attempt_requests; begin
  if p_request is null then raise exception 'performance_attempt_request_required' using errcode='22023'; end if;
  select * into r from app.performance_attempt_requests where actor_id=auth.uid() and request_id=p_request;
  if found and r.payload is distinct from p_payload then
    raise exception 'performance_attempt_request_conflict' using errcode='22023'; end if;
  return r.result;
end; $$;

create function app.nominate_commitment_attempt_at_v1(p_request_id uuid,p_commitment_id uuid,p_event_id uuid,p_bib text,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; e app.performance_attempt_events; n timestamptz; v_id uuid; p jsonb; r jsonb;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  p:=jsonb_build_object('op','nominate','commitment_id',c.id,'event_id',p_event_id,'bib',p_bib);
  r:=app.performance_attempt_recover_v1(p_request_id,p); if r is not null then return (r->>0)::uuid; end if;
  perform app.performance_attempt_open_v1(c);
  n:=coalesce(p_now,clock_timestamp());
  select * into e from app.performance_attempt_events where id=p_event_id;
  if not found or not isfinite(n) or n<c.created_at or n>=e.starts_at
    or e.starts_at<c.starts_at or e.starts_at<c.created_at or e.ends_at>=c.deadline_at
    or p_bib is null or p_bib !~ '^[A-Za-z0-9-]{1,32}$'
    or (select count(*) from app.performance_attempt_nominations where commitment_id=c.id)>=32 then
    raise exception 'performance_attempt_invalid_nomination' using errcode='22023'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_retention(commitment_id) values(c.id) on conflict do nothing;
  insert into app.performance_attempt_nominations(commitment_id,event_id,bib,nominated_at)
    values(c.id,e.id,p_bib,n) returning id into v_id;
  insert into app.performance_attempt_requests values(auth.uid(),p_request_id,c.id,p,jsonb_build_array(v_id));
  return v_id;
end; $$;
create function public.nominate_commitment_attempt_v1(p_request_id uuid,p_commitment_id uuid,p_event_id uuid,p_bib text)
returns uuid language sql security definer set search_path='' as $$
  select app.nominate_commitment_attempt_at_v1(p_request_id,p_commitment_id,p_event_id,p_bib)
$$;
create function app.confirm_commitment_attempt_set_at_v1(p_request_id uuid,p_commitment_id uuid,p_attempt_ids uuid[],p_confirm boolean,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; n timestamptz; ids uuid[]; p jsonb; r jsonb;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  p:=jsonb_build_object('op','confirm_set','commitment_id',c.id,'attempt_ids',p_attempt_ids,'confirm',p_confirm);
  r:=app.performance_attempt_recover_v1(p_request_id,p); if r is not null then return c.id; end if;
  perform app.performance_attempt_open_v1(c); n:=coalesce(p_now,clock_timestamp());
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into ids from app.performance_attempt_nominations where commitment_id=c.id;
  if not isfinite(n) or n<c.deadline_at or n>=(c.terms->>'results_due_at')::timestamptz or p_confirm is distinct from true
    or p_attempt_ids is distinct from ids then raise exception 'performance_attempt_invalid_confirmation' using errcode='22023'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_retention(commitment_id) values(c.id) on conflict do nothing;
  insert into app.performance_attempt_confirmations values(c.id,n,case when cardinality(ids)=0 then 'no_attempts' else 'complete_set' end,ids);
  insert into app.performance_attempt_requests values(auth.uid(),p_request_id,c.id,p,jsonb_build_array(c.id));
  return c.id;
end; $$;
create function public.confirm_commitment_attempt_set_v1(p_request_id uuid,p_commitment_id uuid,p_attempt_ids uuid[],p_confirm boolean)
returns uuid language sql security definer set search_path='' as $$
  select app.confirm_commitment_attempt_set_at_v1(p_request_id,p_commitment_id,p_attempt_ids,p_confirm)
$$;
create function public.set_commitment_attempt_reviewer_v1(p_request_id uuid,p_commitment_id uuid,p_reviewer_id uuid,p_enabled boolean)
returns bigint language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; g app.performance_attempt_grants; v_id bigint;
begin
  perform app.duel_require_service_v1();
  -- Service locks reviewer too, but has no caller session to validate.
  select * into c from app.performance_commitment_agreements where id=p_commitment_id;
  perform id from public.profiles where id in(c.actor_id,p_reviewer_id) order by id for update;
  c:=app.performance_attempt_lock_v1(p_commitment_id,null);
  select * into g from app.performance_attempt_grants where request_id=p_request_id;
  if found then
    if (g.commitment_id,g.reviewer_id,g.enabled) is distinct from (c.id,p_reviewer_id,p_enabled) then
      raise exception 'performance_attempt_request_conflict' using errcode='22023'; end if;
    return g.id;
  end if;
  if p_request_id is null or p_reviewer_id is null or p_enabled is null or p_reviewer_id=c.actor_id
    or (p_enabled and (not app.is_active_actor(p_reviewer_id) or not app.is_active_actor(c.actor_id)
      or c.status<>'open' or app.is_blocked_either_way(p_reviewer_id,c.actor_id))) then
    raise exception 'performance_attempt_invalid_reviewer' using errcode='42501'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_grants(request_id,commitment_id,reviewer_id,enabled,recorded_at)
    values(p_request_id,c.id,p_reviewer_id,p_enabled,clock_timestamp()) returning id into v_id;
  return v_id;
end; $$;

create function app.capture_commitment_attempt_at_v1(p_source_id uuid,p_commitment_id uuid,p_attempt_id uuid,p_document jsonb,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; a app.performance_attempt_nominations; e app.performance_attempt_events;
  s app.performance_attempt_sources; n timestamptz; v_start timestamptz; v_finish timestamptz; seconds integer;
begin
  perform app.duel_require_service_v1();
  c:=app.performance_attempt_lock_v1(p_commitment_id,null);
  select * into s from app.performance_attempt_sources where id=p_source_id;
  if found then
    if (s.commitment_id,s.attempt_id,s.document) is distinct from (c.id,p_attempt_id,p_document) then
      raise exception 'performance_attempt_source_conflict' using errcode='22023'; end if;
    return s.id;
  end if;
  perform app.performance_attempt_open_v1(c); n:=coalesce(p_now,clock_timestamp());
  select * into a from app.performance_attempt_nominations where commitment_id=c.id and id=p_attempt_id;
  if not found then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  select * into strict e from app.performance_attempt_events where id=a.event_id;
  if p_source_id is null or not isfinite(n) or n<e.ends_at or n>=(c.terms->>'finality_due_at')::timestamptz
    or not app.duel_proof_keys_v1(p_document,array['source','event_id','distance_meters','timing_basis','precision_ms',
      'published_bib','status','chip_seconds','started_at','finished_at'])
    or p_document->>'source' is distinct from e.source or p_document->>'event_id' is distinct from e.id::text
    or p_document->'distance_meters' is distinct from '5000'::jsonb
    or p_document->>'timing_basis' is distinct from 'organizer_chip'
    or p_document->'precision_ms' is distinct from '1000'::jsonb
    or p_document->>'status' is null or p_document->>'status' not in ('finished','dns','dnf','disqualified','missing','ambiguous')
    or octet_length(p_document::text)>4096 then
    raise exception 'performance_attempt_invalid_source' using errcode='22023'; end if;
  if p_document->>'status' in ('finished','dns','dnf','disqualified') and p_document->>'published_bib' is distinct from a.bib then
    raise exception 'performance_attempt_bib_mismatch' using errcode='22023'; end if;
  if p_document->>'status'='finished' then
    if jsonb_typeof(p_document->'chip_seconds')<>'number' or (p_document->>'chip_seconds') !~ '^[0-9]+$' then
      raise exception 'performance_attempt_invalid_precision' using errcode='22023'; end if;
    seconds:=(p_document->>'chip_seconds')::integer;
    v_start:=(p_document->>'started_at')::timestamptz; v_finish:=(p_document->>'finished_at')::timestamptz;
    if seconds not between 1 and 86400 or v_start is null or v_finish is null or not isfinite(v_start) or not isfinite(v_finish)
      or v_start<e.starts_at or v_start<c.starts_at or v_start<c.created_at or v_finish>e.ends_at
      or v_finish>=c.deadline_at or v_finish-v_start<>seconds*interval '1 second' then
      raise exception 'performance_attempt_invalid_window' using errcode='22023'; end if;
  elsif p_document->'chip_seconds'<>'null'::jsonb or p_document->'started_at'<>'null'::jsonb or p_document->'finished_at'<>'null'::jsonb then
    raise exception 'performance_attempt_invalid_nonfinish' using errcode='22023';
  end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_sources values(p_source_id,c.id,a.id,n,p_document);
  return p_source_id;
end; $$;
create function public.capture_commitment_attempt_fixture_v1(p_source_id uuid,p_commitment_id uuid,p_attempt_id uuid,p_document jsonb)
returns uuid language sql security definer set search_path='' as $$
  select app.capture_commitment_attempt_at_v1(p_source_id,p_commitment_id,p_attempt_id,p_document)
$$;
create function public.get_commitment_attempt_source_v1(p_commitment_id uuid,p_source_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; s app.performance_attempt_sources;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid());
  perform app.performance_attempt_reviewer_v1(c); perform app.performance_attempt_open_v1(c);
  select * into s from app.performance_attempt_sources where commitment_id=c.id and id=p_source_id;
  if not found then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_audit(commitment_id,actor_id,operation,source_id) values(c.id,auth.uid(),'source_read',s.id);
  return to_jsonb(s);
end; $$;
create function app.review_commitment_attempt_at_v1(p_request_id uuid,p_commitment_id uuid,p_source_id uuid,p_supersedes_revision integer,
  p_identity_confirmed boolean,p_now timestamptz default null) returns integer
language plpgsql security definer set search_path='' as $$
declare c app.performance_commitment_agreements; s app.performance_attempt_sources; g bigint; n timestamptz;
  previous integer; v_revision integer; p jsonb; r jsonb;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid()); g:=app.performance_attempt_reviewer_v1(c);
  p:=jsonb_build_object('op','review','commitment_id',c.id,'source_id',p_source_id,'supersedes_revision',p_supersedes_revision,'identity_confirmed',p_identity_confirmed);
  r:=app.performance_attempt_recover_v1(p_request_id,p); if r is not null then return (r->>0)::integer; end if;
  perform app.performance_attempt_open_v1(c); n:=coalesce(p_now,clock_timestamp());
  select * into s from app.performance_attempt_sources where commitment_id=c.id and id=p_source_id;
  if not found then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  select max(revision) into previous from app.performance_attempt_revisions where commitment_id=c.id and attempt_id=s.attempt_id;
  select coalesce(max(revision),0)+1 into v_revision from app.performance_attempt_revisions where commitment_id=c.id;
  if p_supersedes_revision is distinct from previous or p_identity_confirmed is distinct from true
    or not isfinite(n) or n<s.captured_at or n>=(c.terms->>'finality_due_at')::timestamptz
    or (previous is null and n>=(c.terms->>'results_due_at')::timestamptz)
    or exists(select 1 from app.performance_attempt_revisions where commitment_id=c.id and recorded_at>n)
    or not exists(select 1 from app.performance_attempt_audit where commitment_id=c.id and source_id=s.id and actor_id=auth.uid() and operation='source_read') then
    raise exception 'performance_attempt_invalid_review' using errcode='22023'; end if;
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_revisions values(c.id,v_revision,s.attempt_id,s.id,previous,auth.uid(),g,n);
  insert into app.performance_attempt_requests values(auth.uid(),p_request_id,c.id,p,jsonb_build_array(v_revision));
  return v_revision;
end; $$;
create function public.review_commitment_attempt_v1(p_request_id uuid,p_commitment_id uuid,p_source_id uuid,p_supersedes_revision integer,p_identity_confirmed boolean)
returns integer language sql security definer set search_path='' as $$
  select app.review_commitment_attempt_at_v1(p_request_id,p_commitment_id,p_source_id,p_supersedes_revision,p_identity_confirmed)
$$;

create function public.list_commitment_attempt_events_v1(p_commitment_id uuid,p_limit integer default 50)
returns setof jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; n timestamptz;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  perform app.performance_attempt_open_v1(c); n:=clock_timestamp();
  if p_limit is null or p_limit not between 1 and 100 then raise exception 'performance_attempt_invalid_page' using errcode='22023'; end if;
  return query select to_jsonb(e) from app.performance_attempt_events e
    where e.starts_at>n and e.starts_at>=c.starts_at and e.ends_at<c.deadline_at
      and not exists(select 1 from app.performance_attempt_nominations a where a.commitment_id=c.id and a.event_id=e.id)
    order by e.starts_at,e.id limit p_limit;
end; $$;
create function public.get_commitment_attempts_v1(p_commitment_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements;
begin
  c:=app.performance_attempt_lock_v1(p_commitment_id,auth.uid());
  if c.actor_id is distinct from auth.uid() then raise exception 'performance_attempt_unavailable' using errcode='42501'; end if;
  return jsonb_build_object('commitment_id',c.id,'server_now',clock_timestamp(),
    'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'event',to_jsonb(e),'nominated_at',a.nominated_at)
      order by a.nominated_at,a.id) from app.performance_attempt_nominations a join app.performance_attempt_events e on e.id=a.event_id where a.commitment_id=c.id),'[]'::jsonb),
    'confirmation',(select to_jsonb(f) from app.performance_attempt_confirmations f where f.commitment_id=c.id),
    'receipts',coalesce((select jsonb_agg(jsonb_build_object('revision',r.revision,'attempt_id',r.attempt_id,
      'supersedes_revision',r.supersedes_revision,'recorded_at',r.recorded_at) order by r.revision)
      from app.performance_attempt_revisions r where r.commitment_id=c.id),'[]'::jsonb));
end; $$;
-- A server/operator diagnostic snapshot, never a participant or follower read.
create function public.get_commitment_attempt_snapshot_v1(p_commitment_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements;
begin
  perform app.duel_require_service_v1(); c:=app.performance_attempt_lock_v1(p_commitment_id,null);
  perform app.performance_attempt_open_v1(c);
  perform set_config('app.performance_attempt_write_v1','on',true);
  insert into app.performance_attempt_audit(commitment_id,operation) values(c.id,'snapshot_read');
  return jsonb_build_object('agreement',app.performance_commitment_projection_v1(c.id,clock_timestamp()),
    'attempts',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('event',to_jsonb(e)) order by a.nominated_at,a.id)
      from app.performance_attempt_nominations a join app.performance_attempt_events e on e.id=a.event_id where a.commitment_id=c.id),'[]'::jsonb),
    'confirmation',(select to_jsonb(f) from app.performance_attempt_confirmations f where f.commitment_id=c.id),
    'proofRevisions',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('source',to_jsonb(s)) order by r.revision)
      from app.performance_attempt_revisions r join app.performance_attempt_sources s on s.id=r.source_id where r.commitment_id=c.id),'[]'::jsonb));
end; $$;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and (p.proname like '%performance_attempt%v1' or p.proname like '%commitment_attempt%v1'
      or p.proname='curate_commitment_fixture_event_v1') loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.nominate_commitment_attempt_v1(uuid,uuid,uuid,text),
  public.list_commitment_attempt_events_v1(uuid,integer),
  public.confirm_commitment_attempt_set_v1(uuid,uuid,uuid[],boolean),public.get_commitment_attempts_v1(uuid),
  public.get_commitment_attempt_source_v1(uuid,uuid),public.review_commitment_attempt_v1(uuid,uuid,uuid,integer,boolean) to authenticated;
grant execute on function public.set_commitment_attempts_enabled_v1(boolean),public.curate_commitment_fixture_event_v1(uuid,timestamptz,timestamptz),
  public.set_commitment_attempt_reviewer_v1(uuid,uuid,uuid,boolean),public.capture_commitment_attempt_fixture_v1(uuid,uuid,uuid,jsonb),
  public.get_commitment_attempt_snapshot_v1(uuid) to service_role;
