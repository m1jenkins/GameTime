-- Reviewed checkpoint through Phase 3(c); no following or new product behavior.
-- Preserve prior source/request identity and all historical agreement terms.
-- New source validation follows committed exact recovery deliberately.
create or replace function app.capture_commitment_attempt_at_v1(p_source_id uuid,p_commitment_id uuid,p_attempt_id uuid,p_document jsonb,p_now timestamptz default null)
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
    or jsonb_typeof(p_document->'published_bib') not in ('string','null')
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
    -- The retained JSON is consumed directly by the pure evaluator. PostgreSQL
    -- accepts more timestamp spellings and precision than that wire contract.
    if jsonb_typeof(p_document->'started_at') is distinct from 'string'
      or jsonb_typeof(p_document->'finished_at') is distinct from 'string'
      or (p_document->>'started_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$'
      or (p_document->>'finished_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception 'performance_attempt_invalid_window' using errcode='22023';
    end if;
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

-- Called only after sorted pair locks: profile -> session -> runtime/agreement.
-- Revocation waits for this operation; natural expiry is rechecked after waits.
create function app.duel_link_lock_session_v1() returns void
language plpgsql security definer set search_path='' as $$
begin
  perform app.duel_proof_require_session_v1();
  perform 1 from auth.sessions where id::text=auth.jwt()->>'session_id'
    and user_id=auth.uid() for share;
  perform app.duel_proof_require_session_v1();
end; $$;
revoke all on function app.duel_link_lock_session_v1() from public,anon,authenticated,service_role;

create or replace function app.rematch_duel_at_v1(p_request_id uuid,p_previous_challenge_id uuid,p_event_id uuid,
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
  perform app.duel_link_lock_session_v1();
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
  perform app.duel_proof_require_session_v1();
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


create or replace function app.change_duel_link_at_v1(p_operation text,p_request_id uuid,p_challenge_id uuid,
  p_token uuid default null,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); c public.duel_challenges; payload jsonb; recovered uuid; t timestamptz;
begin
  select * into c from public.duel_challenges where id=p_challenge_id;
  if not found or a is null or a<>c.creator_id then
    raise exception 'duel_link_unavailable' using errcode='42501';
  end if;
  perform app.duel_lock_pair_v1(c.creator_id,c.invitee_id);
  perform app.duel_link_lock_session_v1();
  payload:=jsonb_build_object('operation',p_operation,'challenge_id',c.id,'token',p_token);
  recovered:=app.duel_recover_request_v1(a,p_request_id,payload);
  if recovered is not null then return recovered; end if;
  if p_operation='issue_duel_link_v1' then perform app.duel_admit_pair_v1(c.creator_id,c.invitee_id); end if;
  select * into strict c from public.duel_challenges where id=c.id for update;
  perform app.duel_proof_require_session_v1();
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

create or replace function app.read_duel_link_at_v1(p_challenge_id uuid,p_token uuid,p_now timestamptz default null)
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
  perform app.duel_link_lock_session_v1();
  select * into strict c from public.duel_challenges where id=c.id for update;
  perform app.duel_proof_require_session_v1();
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
