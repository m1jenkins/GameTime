-- Phase 3(c): private owner-reported progress. This ledger is deliberately absent
-- from organizer proof, scoring, agreement terms and settlement snapshots.
create table app.performance_progress_runtime (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false
);
insert into app.performance_progress_runtime values(true,false);
create table app.performance_progress_milestones (
  id uuid primary key default extensions.gen_random_uuid(),
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  title text not null check(char_length(title) between 1 and 80 and title=btrim(title) and title !~ '[[:cntrl:]]'),
  due_at timestamptz not null check(isfinite(due_at)),
  created_at timestamptz not null check(isfinite(created_at)),
  unique(commitment_id,id)
);
create table app.performance_progress_entries (
  commitment_id uuid not null references app.performance_commitment_agreements(id),
  sequence integer not null check(sequence between 1 and 512),
  milestone_id uuid,
  kind text not null check(kind in ('milestone_created','check_in','milestone_status')),
  status text check(status in ('planned','completed','retired')),
  note text check(char_length(note) between 1 and 500 and note=btrim(note) and note !~ '[[:cntrl:]]'),
  occurred_at timestamptz not null check(isfinite(occurred_at)),
  recorded_at timestamptz not null check(isfinite(recorded_at) and occurred_at<=recorded_at),
  primary key(commitment_id,sequence),
  foreign key(commitment_id,milestone_id) references app.performance_progress_milestones(commitment_id,id),
  check((kind='check_in' and status is null and note is not null)
    or (kind='milestone_created' and milestone_id is not null and status='planned' and note is null)
    or (kind='milestone_status' and milestone_id is not null and status is not null and note is null))
);
create index performance_progress_milestone_history_idx on app.performance_progress_entries(commitment_id,milestone_id,sequence desc);
create table app.performance_progress_requests (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  commitment_id uuid not null,
  sequence integer not null,
  payload jsonb not null check(octet_length(payload::text)<=8192),
  result jsonb not null,
  primary key(actor_id,request_id),
  foreign key(commitment_id,sequence) references app.performance_progress_entries(commitment_id,sequence)
);
create index performance_progress_request_entry_idx on app.performance_progress_requests(commitment_id,sequence);
-- Local fictional history stays held after closure/deletion, just as attempts
-- do. A later product-specific retention policy must govern release and purge.
create table app.performance_progress_retention (
  commitment_id uuid primary key references app.performance_commitment_agreements(id),
  scope text not null default 'performance_progress_v1' check(scope='performance_progress_v1'),
  reason text not null default 'awaiting_progress_retention_policy' check(reason='awaiting_progress_retention_policy')
);
create table app.performance_progress_audit (
  id bigint generated always as identity primary key,
  enabled boolean not null,
  recorded_at timestamptz not null default clock_timestamp()
);
create function app.performance_progress_guard_v1() returns trigger
language plpgsql set search_path='' as $$ begin
  if current_user<>pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid=tg_relid))
    or coalesce(current_setting('app.performance_progress_write_v1',true),'')<>'on' then
    raise exception 'performance_progress_rpc_required' using errcode='42501';
  end if;
  if tg_op<>'INSERT' and not(tg_op='UPDATE' and tg_table_name='performance_progress_runtime') then
    raise exception 'performance_progress_history_retained' using errcode='23001';
  end if;
  return new;
end; $$;
do $$ declare t text; begin
  foreach t in array array['runtime','milestones','entries','requests','retention','audit'] loop
    execute format('alter table app.performance_progress_%I enable row level security',t);
    execute format('revoke all on app.performance_progress_%I from public,anon,authenticated,service_role',t);
    execute format('create trigger performance_progress_guard before insert or update or delete on app.performance_progress_%I
      for each row execute function app.performance_progress_guard_v1()',t);
    execute format('create trigger performance_progress_truncate before truncate on app.performance_progress_%I
      for each statement execute function app.performance_progress_guard_v1()',t);
  end loop;
end; $$;
create function public.set_commitment_progress_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$ begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'performance_progress_invalid_gate' using errcode='22023'; end if;
  perform set_config('app.performance_progress_write_v1','on',true);
  update app.performance_progress_runtime set enabled=p_enabled where singleton;
  insert into app.performance_progress_audit(enabled) values(p_enabled);
  return p_enabled;
end; $$;

-- Owner profile -> real caller session -> progress runtime -> agreement.
-- This shares the agreement/deletion serialization order, independently of
-- attempt admission. Natural session expiry is checked again after waiting.
create function app.performance_progress_lock_v1(p_commitment uuid)
returns app.performance_commitment_agreements language plpgsql set search_path='' as $$
declare a uuid; c app.performance_commitment_agreements;
begin
  a:=app.performance_commitment_lock_actor_v1();
  perform 1 from app.performance_progress_runtime where singleton for share;
  select * into c from app.performance_commitment_agreements where id=p_commitment and actor_id=a for update;
  if not found then raise exception 'performance_progress_unavailable' using errcode='42501'; end if;
  perform app.performance_commitment_lock_actor_v1();
  return c;
end; $$;
create function app.performance_progress_entry_v1(e app.performance_progress_entries) returns jsonb
language sql immutable set search_path='' set timezone='UTC' as $$
  select to_jsonb(e)||jsonb_build_object('provenance','owner_reported','counts_as_proof',false)
$$;

-- One exact-request namespace across all three progress mutations. Private
-- clock input is solely for deterministic local tests and has no API grant.
create function app.write_commitment_progress_at_v1(p_request_id uuid,p_commitment_id uuid,p_kind text,
  p_milestone_id uuid,p_title text,p_due_at timestamptz,p_status text,p_expected_revision integer,
  p_note text,p_occurred_at timestamptz,p_now timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; m app.performance_progress_milestones;
  previous app.performance_progress_entries; e app.performance_progress_entries; r app.performance_progress_requests;
  p jsonb; result jsonb; n timestamptz; seq integer; last_at timestamptz; mid uuid:=p_milestone_id;
begin
  c:=app.performance_progress_lock_v1(p_commitment_id);
  if p_request_id is null then raise exception 'performance_progress_request_required' using errcode='22023'; end if;
  -- Bound text before storing or constructing request identity; never trim or
  -- silently rewrite a user's saved exact request.
  if (p_title is not null and (char_length(p_title) not between 1 and 80 or p_title<>btrim(p_title) or p_title ~ '[[:cntrl:]]'))
    or (p_note is not null and (char_length(p_note) not between 1 and 500 or p_note<>btrim(p_note) or p_note ~ '[[:cntrl:]]')) then
    raise exception 'performance_progress_invalid_text' using errcode='22023';
  end if;
  p:=jsonb_build_object('kind',p_kind,'commitment_id',c.id,'milestone_id',p_milestone_id,'title',p_title,
    'due_at',p_due_at,'status',p_status,'expected_revision',p_expected_revision,'note',p_note,'occurred_at',p_occurred_at);
  select * into r from app.performance_progress_requests where actor_id=auth.uid() and request_id=p_request_id;
  if found then
    if r.payload is distinct from p then raise exception 'performance_progress_request_conflict' using errcode='22023'; end if;
    return r.result;
  end if;
  if c.status<>'open' or not(select enabled from app.performance_progress_runtime where singleton) then
    raise exception 'performance_progress_unavailable' using errcode='42501'; end if;
  n:=coalesce(p_now,clock_timestamp());
  select coalesce(max(sequence),0)+1,max(recorded_at) into seq,last_at from app.performance_progress_entries where commitment_id=c.id;
  if not isfinite(n) or n<c.created_at or n>=c.deadline_at or n<last_at then
    raise exception 'performance_progress_window_closed' using errcode='22023'; end if;
  if seq>512 then raise exception 'performance_progress_history_full' using errcode='54000'; end if;
  if mid is not null then
    select * into m from app.performance_progress_milestones where commitment_id=c.id and id=mid;
    if not found then raise exception 'performance_progress_milestone_unavailable' using errcode='42501'; end if;
    select * into previous from app.performance_progress_entries where commitment_id=c.id and milestone_id=mid
      and status is not null order by sequence desc limit 1;
  end if;
  if p_kind='milestone_created' then
    if mid is not null or p_title is null or p_due_at is null or not isfinite(p_due_at)
      or p_due_at<n or p_due_at>=c.deadline_at or p_status is not null or p_expected_revision is not null
      or p_note is not null or p_occurred_at is not null then
      raise exception 'performance_progress_invalid_milestone' using errcode='22023'; end if;
    if (select count(*) from app.performance_progress_milestones where commitment_id=c.id)>=32 then
      raise exception 'performance_progress_milestones_full' using errcode='54000'; end if;
  elsif p_kind='check_in' then
    if p_note is null or p_occurred_at is null or not isfinite(p_occurred_at) or p_occurred_at<c.created_at or p_occurred_at>n
      or (mid is not null and (p_occurred_at<m.created_at or previous.status='retired'))
      or p_title is not null or p_due_at is not null or p_status is not null or p_expected_revision is not null then
      raise exception 'performance_progress_invalid_check_in' using errcode='22023'; end if;
  elsif p_kind='milestone_status' then
    if mid is null or p_status is null or p_status not in ('planned','completed','retired')
      or p_expected_revision is distinct from previous.sequence or previous.status='retired' or p_status=previous.status
      or p_title is not null or p_due_at is not null or p_note is not null or p_occurred_at is not null then
      raise exception 'performance_progress_invalid_transition' using errcode='22023'; end if;
  else
    raise exception 'performance_progress_invalid_kind' using errcode='22023';
  end if;
  perform set_config('app.performance_progress_write_v1','on',true);
  insert into app.performance_progress_retention(commitment_id) values(c.id) on conflict do nothing;
  if p_kind='milestone_created' then
    insert into app.performance_progress_milestones(commitment_id,title,due_at,created_at)
      values(c.id,p_title,p_due_at,n) returning id into mid;
  end if;
  insert into app.performance_progress_entries values(c.id,seq,mid,p_kind,
    case when p_kind='milestone_created' then 'planned' else p_status end,p_note,coalesce(p_occurred_at,n),n) returning * into e;
  result:=app.performance_progress_entry_v1(e);
  insert into app.performance_progress_requests values(auth.uid(),p_request_id,c.id,seq,p,result);
  return result;
end; $$;
create function public.create_commitment_milestone_v1(p_request_id uuid,p_commitment_id uuid,p_title text,p_due_at timestamptz)
returns jsonb language sql security definer set search_path='' as $$
  select app.write_commitment_progress_at_v1(p_request_id,p_commitment_id,'milestone_created',null,p_title,p_due_at,null,null,null,null)
$$;
create function public.record_commitment_progress_v1(p_request_id uuid,p_commitment_id uuid,p_note text,p_occurred_at timestamptz,p_milestone_id uuid default null)
returns jsonb language sql security definer set search_path='' as $$
  select app.write_commitment_progress_at_v1(p_request_id,p_commitment_id,'check_in',p_milestone_id,null,null,null,null,p_note,p_occurred_at)
$$;
create function public.set_commitment_milestone_status_v1(p_request_id uuid,p_commitment_id uuid,p_milestone_id uuid,p_status text,p_expected_revision integer)
returns jsonb language sql security definer set search_path='' as $$
  select app.write_commitment_progress_at_v1(p_request_id,p_commitment_id,'milestone_status',p_milestone_id,null,null,p_status,p_expected_revision,null,null)
$$;

-- Forward keyset pagination freezes an upper sequence on the first page.
-- Milestone states are computed at that same upper sequence, so concurrent
-- writes neither shuffle history nor leak a newer status into an older page.
create function public.get_commitment_progress_v1(p_commitment_id uuid,p_limit integer default 50,
  p_after_sequence integer default 0,p_through_sequence integer default null)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c app.performance_commitment_agreements; hi integer; through_seq integer; next_seq integer; n timestamptz; entries jsonb; milestones jsonb;
begin
  c:=app.performance_progress_lock_v1(p_commitment_id); n:=clock_timestamp();
  select coalesce(max(sequence),0) into hi from app.performance_progress_entries where commitment_id=c.id;
  through_seq:=coalesce(p_through_sequence,hi);
  if p_limit is null or p_limit not between 1 and 100 or p_after_sequence is null or p_after_sequence<0
    or through_seq<0 or through_seq>hi or p_after_sequence>through_seq then
    raise exception 'performance_progress_invalid_page' using errcode='22023'; end if;
  select coalesce(jsonb_agg(app.performance_progress_entry_v1(e) order by e.sequence),'[]'::jsonb),coalesce(max(e.sequence),p_after_sequence)
    into entries,next_seq from (select * from app.performance_progress_entries where commitment_id=c.id
      and sequence>p_after_sequence and sequence<=through_seq order by sequence limit p_limit) e;
  select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('status',s.status,'status_revision',s.sequence,
    'provenance','owner_reported','counts_as_proof',false) order by m.due_at,m.id),'[]'::jsonb)
    into milestones from app.performance_progress_milestones m join lateral (
      select e.status,e.sequence from app.performance_progress_entries e where e.commitment_id=m.commitment_id and e.milestone_id=m.id
        and e.status is not null and e.sequence<=through_seq order by e.sequence desc limit 1
    ) s on true where m.commitment_id=c.id;
  return jsonb_build_object('commitment_id',c.id,'server_now',n,'provenance','owner_reported','counts_as_proof',false,
    'new_writes_allowed',c.status='open' and n>=c.created_at and n<c.deadline_at and hi<512
      and (select enabled from app.performance_progress_runtime where singleton),
    'milestones',milestones,'entries',entries,'through_sequence',through_seq,'next_after_sequence',next_seq,'has_more',next_seq<through_seq);
end; $$;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and (p.proname like '%performance_progress%v1' or p.proname like '%commitment_progress%v1'
      or p.proname like '%commitment_milestone%v1') loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.create_commitment_milestone_v1(uuid,uuid,text,timestamptz),
  public.record_commitment_progress_v1(uuid,uuid,text,timestamptz,uuid),
  public.set_commitment_milestone_status_v1(uuid,uuid,uuid,text,integer),
  public.get_commitment_progress_v1(uuid,integer,integer,integer) to authenticated;
grant execute on function public.set_commitment_progress_enabled_v1(boolean) to service_role;
