-- Phase 2(b): private fictional source capture and independent proof review.
-- No result publication, notice, review case, worker, scheduler or money path.
-- All new API access is explicit; app remains outside exposed schemas.

create table app.duel_proof_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into app.duel_proof_runtime(singleton) values (true);

-- Each service decision is retained. Authorization uses the latest event,
-- never a JWT role claim, mutable user metadata, or a submitted reviewer ID.
create table app.duel_proof_grants (
  id bigint generated always as identity primary key,
  request_id uuid not null unique,
  challenge_id uuid not null references public.duel_challenges(id),
  reviewer_id uuid not null references public.profiles(id),
  enabled boolean not null,
  recorded_at timestamptz not null check (isfinite(recorded_at)),
  authority text not null check (authority in ('postgres','service_role'))
);
create index duel_proof_grant_current_idx on app.duel_proof_grants(challenge_id,reviewer_id,id desc);
create index duel_proof_grant_reviewer_idx on app.duel_proof_grants(reviewer_id);

-- Bounded JSON fixture document, not a Storage bucket, route or remote URL.
-- JSONB digest identifies canonical captured content, not original file bytes.
create table app.duel_proof_sources (
  id uuid primary key,
  challenge_id uuid not null references public.duel_challenges(id),
  document jsonb not null check (jsonb_typeof(document)='object'),
  content_digest text generated always as
    (encode(extensions.digest(document::text,'sha256'),'hex')) stored,
  source_reference text not null unique,
  retrieved_at timestamptz not null check (isfinite(retrieved_at)),
  authority text not null check (authority in ('postgres','service_role')),
  unique (challenge_id,id)
);

create table app.duel_proof_revisions (
  challenge_id uuid not null references public.duel_challenges(id),
  revision integer not null check (revision>0),
  supersedes_revision integer,
  reviewer_id uuid not null references public.profiles(id),
  grant_id bigint not null references app.duel_proof_grants(id),
  request_id uuid not null,
  source_id uuid not null,
  request_payload jsonb not null,
  terms_digest text not null,
  recorded_at timestamptz not null check (isfinite(recorded_at)),
  records jsonb not null check (jsonb_typeof(records)='array' and jsonb_array_length(records)=2),
  primary key (challenge_id,revision),
  unique (reviewer_id,request_id),
  foreign key (challenge_id,supersedes_revision) references app.duel_proof_revisions(challenge_id,revision),
  foreign key (challenge_id,source_id) references app.duel_proof_sources(challenge_id,id),
  check ((revision=1 and supersedes_revision is null) or
    (revision>1 and supersedes_revision is not null and supersedes_revision=revision-1))
);
create index duel_proof_revision_predecessor_idx on app.duel_proof_revisions(challenge_id,supersedes_revision);
create index duel_proof_revision_source_idx on app.duel_proof_revisions(challenge_id,source_id);
create index duel_proof_revision_grant_idx on app.duel_proof_revisions(grant_id);

create table app.duel_proof_access_audit (
  id bigint generated always as identity primary key,
  operation text not null check (operation in ('source_read','gate_enabled','gate_disabled')),
  source_id uuid references app.duel_proof_sources(id),
  reviewer_id uuid references public.profiles(id),
  grant_id bigint references app.duel_proof_grants(id),
  recorded_at timestamptz not null check (isfinite(recorded_at)),
  authority text not null check (authority in ('postgres','service_role','authenticated')),
  check ((operation='source_read' and source_id is not null and reviewer_id is not null and grant_id is not null)
    or (operation<>'source_read' and source_id is null and reviewer_id is null and grant_id is null))
);
create index duel_proof_access_source_idx on app.duel_proof_access_audit(source_id);
create index duel_proof_access_reviewer_idx on app.duel_proof_access_audit(reviewer_id);
create index duel_proof_access_grant_idx on app.duel_proof_access_audit(grant_id);

create function app.duel_proof_guard_v1() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid(
      (select relowner from pg_catalog.pg_class where oid=tg_relid))
    or coalesce(current_setting('app.duel_proof_write_v1',true),'') <> 'on' then
    raise exception 'duel_proof_write_requires_rpc' using errcode='42501';
  end if;
  if tg_op<>'INSERT' and not (tg_op='UPDATE' and tg_table_name='duel_proof_runtime') then
    raise exception 'duel_proof_append_only' using errcode='23001';
  end if;
  return new;
end;
$$;
do $$ declare t text; begin
  foreach t in array array['duel_proof_runtime','duel_proof_grants','duel_proof_sources',
    'duel_proof_revisions','duel_proof_access_audit'] loop
    execute format('alter table app.%I enable row level security',t);
    execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
    execute format('create trigger duel_proof_guard before insert or update or delete on app.%I
      for each row execute function app.duel_proof_guard_v1()',t);
    execute format('create trigger duel_proof_no_truncate before truncate on app.%I
      for each statement execute function app.duel_proof_guard_v1()',t);
  end loop;
end; $$;
revoke all on sequence app.duel_proof_grants_id_seq,app.duel_proof_access_audit_id_seq
  from public,anon,authenticated,service_role;

create function app.duel_proof_authority_v1() returns text
language sql stable set search_path='' as $$
  select case when current_setting('role')='none' then session_user::text else current_setting('role') end;
$$;

create function public.set_duel_proof_enabled_v1(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform app.duel_require_service_v1();
  if p_enabled is null then raise exception 'duel_proof_invalid_gate' using errcode='22023'; end if;
  -- This control takes only the runtime lock, never an actor/challenge lock.
  perform 1 from app.duel_proof_runtime where singleton for update;
  perform set_config('app.duel_proof_write_v1','on',true);
  update app.duel_proof_runtime set enabled=p_enabled where singleton;
  insert into app.duel_proof_access_audit(operation,recorded_at,authority)
    values(case when p_enabled then 'gate_enabled' else 'gate_disabled' end,
      clock_timestamp(),app.duel_proof_authority_v1());
  return p_enabled;
end;
$$;

-- All paths lock the union of the pair and reviewer in UUID order BEFORE
-- challenge, runtime, or proof rows. Account deletion owns just its actor and
-- then challenge; it never waits for the opponent. No challenge-first path.
create function app.duel_proof_lock_v1(p_challenge uuid,p_reviewer uuid)
returns public.duel_challenges language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges;
begin
  select * into c from public.duel_challenges where id=p_challenge;
  if not found then raise exception 'duel_proof_unavailable' using errcode='42501'; end if;
  perform id from public.profiles where id in (c.creator_id,c.invitee_id,p_reviewer) order by id for update;
  select * into strict c from public.duel_challenges where id=p_challenge for update;
  return c;
end;
$$;

create function app.duel_proof_require_session_v1() returns uuid
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid();
begin
  if current_setting('role')<>'authenticated' or not app.is_active_actor(a)
    or not exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
      and s.user_id=a and (s.not_after is null or s.not_after>clock_timestamp())) then
    raise exception 'duel_proof_session_required' using errcode='42501';
  end if;
  return a;
end;
$$;

create function app.duel_proof_require_pair_v1(c public.duel_challenges) returns void
language plpgsql set search_path='' as $$
begin
  if not app.is_active_actor(c.creator_id) or not app.is_active_actor(c.invitee_id)
    or app.is_blocked_either_way(c.creator_id,c.invitee_id) then
    raise exception 'duel_proof_unavailable' using errcode='42501';
  end if;
end;
$$;

create function app.duel_proof_require_reviewer_v1(c public.duel_challenges) returns bigint
language plpgsql set search_path='' as $$
declare a uuid; g app.duel_proof_grants;
begin
  a:=app.duel_proof_require_session_v1();
  perform app.duel_proof_require_pair_v1(c);
  if a in (c.creator_id,c.invitee_id) or app.is_blocked_either_way(a,c.creator_id)
    or app.is_blocked_either_way(a,c.invitee_id) then
    raise exception 'duel_proof_reviewer_required' using errcode='42501';
  end if;
  select * into g from app.duel_proof_grants where challenge_id=c.id and reviewer_id=a order by id desc limit 1;
  if not found or not g.enabled then
    raise exception 'duel_proof_reviewer_required' using errcode='42501';
  end if;
  return g.id;
end;
$$;

create function public.set_duel_proof_reviewer_v1(p_request_id uuid,p_challenge_id uuid,
  p_reviewer_id uuid,p_enabled boolean) returns bigint
language plpgsql security definer set search_path='' as $$
declare c public.duel_challenges; g app.duel_proof_grants; v_id bigint;
begin
  perform app.duel_require_service_v1();
  if p_request_id is null or p_reviewer_id is null or p_enabled is null then
    raise exception 'duel_proof_invalid_grant' using errcode='22023';
  end if;
  c:=app.duel_proof_lock_v1(p_challenge_id,p_reviewer_id);
  select * into g from app.duel_proof_grants where request_id=p_request_id;
  if found then
    if (g.challenge_id,g.reviewer_id,g.enabled) is distinct from (p_challenge_id,p_reviewer_id,p_enabled) then
      raise exception 'duel_proof_request_conflict' using errcode='22023';
    end if;
    return g.id; -- A replay never restores a subsequently revoked grant.
  end if;
  if p_reviewer_id in (c.creator_id,c.invitee_id) then
    raise exception 'duel_proof_self_review' using errcode='42501';
  end if;
  if p_enabled then
    perform app.duel_proof_require_pair_v1(c);
    if not app.is_active_actor(p_reviewer_id) or c.status<>'scheduled'
      or app.is_blocked_either_way(p_reviewer_id,c.creator_id)
      or app.is_blocked_either_way(p_reviewer_id,c.invitee_id) then
      raise exception 'duel_proof_unavailable' using errcode='42501';
    end if;
  end if; -- Revocation remains possible after deletion, blocking or gate-off.
  perform set_config('app.duel_proof_write_v1','on',true);
  insert into app.duel_proof_grants(request_id,challenge_id,reviewer_id,enabled,recorded_at,authority)
    values(p_request_id,c.id,p_reviewer_id,p_enabled,clock_timestamp(),app.duel_proof_authority_v1()) returning id into v_id;
  return v_id;
end;
$$;

-- Strict shapes bound size and exclude arbitrary notes, names, URLs and files.
create function app.duel_proof_keys_v1(p jsonb,keys text[]) returns boolean
language sql immutable set search_path='' as $$
  select coalesce(jsonb_typeof(p)='object' and p ?& keys and p-keys='{}'::jsonb,false);
$$;
create function app.duel_proof_validate_source_v1(c public.duel_challenges,p jsonb) returns void
language plpgsql set search_path='' as $$
declare r jsonb; ids text[]:=array[]::text[]; bibs text[]:=array[]::text[];
begin
  if not app.duel_proof_keys_v1(p,array['eventId','course','wave','distanceMeters','timingBasis','precisionSeconds','rows'])
    or octet_length(p::text)>8192 or p->>'eventId' is distinct from c.event_id::text
    or jsonb_typeof(p->'course')<>'string' or length(p->>'course') not between 1 and 100
    or jsonb_typeof(p->'wave')<>'string' or length(p->>'wave') not between 1 and 100
    or jsonb_typeof(p->'timingBasis')<>'string' or length(p->>'timingBasis') not between 1 and 100
    or jsonb_typeof(p->'distanceMeters')<>'number' or jsonb_typeof(p->'precisionSeconds')<>'number'
    or jsonb_typeof(p->'rows')<>'array' then
    raise exception 'duel_proof_invalid_source' using errcode='22023';
  end if;
  if jsonb_array_length(p->'rows')<>2 then
    raise exception 'duel_proof_complete_pair_required' using errcode='22023';
  end if;
  for r in select value from jsonb_array_elements(p->'rows') loop
    if not app.duel_proof_keys_v1(r,array['actorId','mappedBib','publishedBib','status','chipSeconds'])
      or r->>'actorId' is null or r->>'actorId' not in (c.creator_id::text,c.invitee_id::text)
      or r->>'actorId'=any(ids) or r->>'status' is null
      or r->>'status' not in ('finished','dns','dnf','disqualified','missing','ambiguous')
      or jsonb_typeof(r->'chipSeconds') not in ('number','null')
      or jsonb_typeof(r->'mappedBib') not in ('string','null')
      or jsonb_typeof(r->'publishedBib') not in ('string','null')
      or (r->>'mappedBib' is not null and (r->>'mappedBib' !~ '^fictional-bib-[0-9]{1,6}$' or r->>'mappedBib'=any(bibs)))
      or (r->>'publishedBib' is not null and r->>'publishedBib' !~ '^fictional-bib-[0-9]{1,6}$')
      or (r->>'status'<>'finished' and r->'chipSeconds'<>'null'::jsonb) then
      raise exception 'duel_proof_invalid_source_row' using errcode='22023';
    end if;
    ids:=array_append(ids,r->>'actorId');
    if r->>'mappedBib' is not null then bibs:=array_append(bibs,r->>'mappedBib'); end if;
  end loop;
end;
$$;

-- Private clock seam used only by rollback/concurrency fixtures. The exposed
-- wrapper takes no timestamp, source reference, digest or authority argument.
create function app.duel_proof_capture_at_v1(p_source_id uuid,p_challenge_id uuid,
  p_document jsonb,p_now timestamptz default null) returns uuid
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; s app.duel_proof_sources; t timestamptz;
begin
  perform app.duel_require_service_v1();
  c:=app.duel_proof_lock_v1(p_challenge_id,null);
  if p_source_id is null then raise exception 'duel_proof_source_required' using errcode='22023'; end if;
  select * into s from app.duel_proof_sources where id=p_source_id;
  if found then
    if (s.challenge_id,s.document) is distinct from (c.id,p_document) then
      raise exception 'duel_proof_request_conflict' using errcode='22023';
    end if;
    return s.id;
  end if;
  perform app.duel_proof_require_pair_v1(c);
  perform 1 from app.duel_proof_runtime where singleton and enabled for share;
  if not found then raise exception 'duel_proof_disabled' using errcode='42501'; end if;
  t:=coalesce(p_now,clock_timestamp());
  if not isfinite(t) or c.status<>'scheduled' or c.policy_version<>'duel-fixture-5k-v1'
    or t<(c.terms->'event'->>'ends_at')::timestamptz
    or t>=(c.terms->>'finality_due_at')::timestamptz then
    raise exception 'duel_proof_capture_closed' using errcode='55000';
  end if;
  perform app.duel_proof_validate_source_v1(c,p_document);
  perform set_config('app.duel_proof_write_v1','on',true);
  insert into app.duel_proof_sources(id,challenge_id,document,source_reference,retrieved_at,authority)
    values(p_source_id,c.id,p_document,'fixture://duel/'||c.event_id::text||'/'||p_source_id::text,
      t,app.duel_proof_authority_v1());
  return p_source_id;
end;
$$;
create function public.capture_duel_proof_fixture_v1(p_source_id uuid,p_challenge_id uuid,p_document jsonb)
returns uuid language sql security definer set search_path='' as $$
  select app.duel_proof_capture_at_v1(p_source_id,p_challenge_id,p_document);
$$;

create function public.get_duel_proof_source_v1(p_challenge_id uuid,p_source_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; g bigint; s app.duel_proof_sources;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  g:=app.duel_proof_require_reviewer_v1(c);
  select * into s from app.duel_proof_sources where challenge_id=c.id and id=p_source_id;
  if not found then raise exception 'duel_proof_unavailable' using errcode='42501'; end if;
  perform set_config('app.duel_proof_write_v1','on',true);
  insert into app.duel_proof_access_audit(operation,source_id,reviewer_id,grant_id,recorded_at,authority)
    values('source_read',s.id,auth.uid(),g,clock_timestamp(),'authenticated');
  return jsonb_build_object('sourceId',s.id,'challengeId',c.id,'document',s.document,
    'contentDigest',s.content_digest,'sourceReference',s.source_reference,'retrievedAt',s.retrieved_at);
end;
$$;

create function app.duel_proof_append_at_v1(p_request_id uuid,p_challenge_id uuid,p_source_id uuid,
  p_expected_revision integer,p_identity_confirmations jsonb,p_now timestamptz default null) returns integer
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; s app.duel_proof_sources; old app.duel_proof_revisions;
  g bigint; n integer; t timestamptz; payload jsonb; r jsonb; verdict jsonb;
  records jsonb:='[]'::jsonb; ids text[]:=array[]::text[];
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  g:=app.duel_proof_require_reviewer_v1(c);
  if p_request_id is null then raise exception 'duel_proof_request_required' using errcode='22023'; end if;
  payload:=jsonb_build_object('operation','submit_duel_proof_v1','challengeId',c.id,
    'sourceId',p_source_id,'expectedRevision',p_expected_revision,'identityConfirmations',p_identity_confirmations);
  select * into old from app.duel_proof_revisions where reviewer_id=auth.uid() and request_id=p_request_id;
  if found then
    if old.request_payload is distinct from payload then
      raise exception 'duel_proof_request_conflict' using errcode='22023';
    end if;
    return old.revision; -- No reapplication, even after a correction or cutoff.
  end if;
  perform 1 from app.duel_proof_runtime where singleton and enabled for share;
  if not found then raise exception 'duel_proof_disabled' using errcode='42501'; end if;
  select * into old from app.duel_proof_revisions where challenge_id=c.id order by revision desc limit 1;
  n:=coalesce(old.revision,0);
  if p_expected_revision is null or p_expected_revision<>n then
    raise exception 'duel_proof_revision_conflict' using errcode='40001';
  end if;
  select * into s from app.duel_proof_sources where challenge_id=c.id and id=p_source_id;
  if not found then raise exception 'duel_proof_unavailable' using errcode='42501'; end if;
  perform app.duel_proof_require_session_v1();
  -- Sample AFTER every potentially blocking lock. Capturing a source before
  -- cutoff does not backdate a later reviewer submission.
  t:=coalesce(p_now,clock_timestamp());
  if not isfinite(t) or c.status<>'scheduled' or c.policy_version<>'duel-fixture-5k-v1'
    or t<s.retrieved_at or t<(c.terms->'event'->>'ends_at')::timestamptz
    or t>=(c.terms->>'finality_due_at')::timestamptz
    or (n=0 and t>=(c.terms->>'results_due_at')::timestamptz)
    or (n>0 and t<old.recorded_at) then
    raise exception 'duel_proof_submission_closed' using errcode='55000';
  end if;
  if (select count(*) from public.duel_participants where challenge_id=c.id and accepted_at is not null
      and consent_terms_digest=c.terms_digest and consent_policy_version=c.policy_version)<>2 then
    raise exception 'duel_proof_consents_required' using errcode='55000';
  end if;
  if jsonb_typeof(p_identity_confirmations) is distinct from 'array' then
    raise exception 'duel_proof_complete_review_required' using errcode='22023';
  end if;
  if jsonb_array_length(p_identity_confirmations)<>2 then
    raise exception 'duel_proof_complete_review_required' using errcode='22023';
  end if;
  for verdict in select value from jsonb_array_elements(p_identity_confirmations) loop
    if not app.duel_proof_keys_v1(verdict,array['actorId','identityConfirmed'])
      or verdict->>'actorId' is null or verdict->>'actorId' not in (c.creator_id::text,c.invitee_id::text)
      or verdict->>'actorId'=any(ids) or jsonb_typeof(verdict->'identityConfirmed')<>'boolean' then
      raise exception 'duel_proof_invalid_review' using errcode='22023';
    end if;
    ids:=array_append(ids,verdict->>'actorId');
    select value into strict r from jsonb_array_elements(s.document->'rows') where value->>'actorId'=verdict->>'actorId';
    if (verdict->>'identityConfirmed')::boolean and (
      r->>'status' in ('missing','ambiguous') or r->>'mappedBib' is null
      or r->>'mappedBib' is distinct from r->>'publishedBib'
      or (select count(*) from jsonb_array_elements(s.document->'rows') where value->>'publishedBib'=r->>'publishedBib')<>1) then
      raise exception 'duel_proof_identity_unresolved' using errcode='22023';
    end if;
    records:=records||jsonb_build_array(r||jsonb_build_object('identityConfirmed',verdict->'identityConfirmed',
      'source','fixture_official_5k_v1','sourceReference',s.source_reference,
      'eventId',s.document->'eventId','course',s.document->'course','wave',s.document->'wave',
      'distanceMeters',s.document->'distanceMeters','timingBasis',s.document->'timingBasis',
      'precisionSeconds',s.document->'precisionSeconds'));
  end loop;
  perform set_config('app.duel_proof_write_v1','on',true);
  insert into app.duel_proof_revisions(challenge_id,revision,supersedes_revision,reviewer_id,grant_id,
    request_id,source_id,request_payload,terms_digest,recorded_at,records)
    values(c.id,n+1,nullif(n,0),auth.uid(),g,p_request_id,s.id,payload,c.terms_digest,t,
      (select jsonb_agg(value order by value->>'actorId') from jsonb_array_elements(records)));
  return n+1;
end;
$$;
create function public.submit_duel_proof_v1(p_request_id uuid,p_challenge_id uuid,p_source_id uuid,
  p_expected_revision integer,p_identity_confirmations jsonb) returns integer
language sql security definer set search_path='' as $$
  select app.duel_proof_append_at_v1(p_request_id,p_challenge_id,p_source_id,p_expected_revision,p_identity_confirmations);
$$;

-- A participant sees receipt metadata only. No source, bib, reviewer, raw time,
-- identity verdict, digest of private content, or implied athletic result.
create function public.get_duel_proof_status_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c public.duel_challenges; a uuid; r app.duel_proof_revisions;
begin
  c:=app.duel_proof_lock_v1(p_challenge_id,auth.uid());
  a:=app.duel_proof_require_session_v1();
  if a not in (c.creator_id,c.invitee_id) then
    raise exception 'duel_proof_unavailable' using errcode='42501';
  end if;
  perform app.duel_proof_require_pair_v1(c);
  select * into r from app.duel_proof_revisions where challenge_id=c.id order by revision desc limit 1;
  return jsonb_build_object('challengeId',c.id,'termsDigest',c.terms_digest,
    'proofRevision',coalesce(r.revision,0),'recordedAt',r.recorded_at);
end;
$$;

-- Private projection for the next worker; callers must own the same actor /
-- challenge locks and keep them through snapshot verification and commit.
-- Deliberately no full scoring snapshot: notices, cases and finality do not
-- exist yet, and this helper must never silently invent empty operational ledgers.
create function app.duel_proof_history_v1(p_challenge_id uuid) returns jsonb
language sql stable set search_path='' set timezone='UTC' as $$
  select coalesce(jsonb_agg(jsonb_build_object('revision',revision,'supersedesRevision',supersedes_revision,
    'reviewerId',reviewer_id,'recordedAt',recorded_at,'records',records) order by revision),'[]'::jsonb)
  from app.duel_proof_revisions where challenge_id=p_challenge_id;
$$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and p.proname like '%duel_proof%v1' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end; $$;
grant execute on function public.set_duel_proof_enabled_v1(boolean),
  public.set_duel_proof_reviewer_v1(uuid,uuid,uuid,boolean),
  public.capture_duel_proof_fixture_v1(uuid,uuid,jsonb) to service_role;
grant execute on function public.get_duel_proof_source_v1(uuid,uuid),
  public.submit_duel_proof_v1(uuid,uuid,uuid,integer,jsonb),
  public.get_duel_proof_status_v1(uuid) to authenticated;
