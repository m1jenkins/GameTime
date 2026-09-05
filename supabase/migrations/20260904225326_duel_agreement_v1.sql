-- Phase 1A: isolated, nonredeemable same-event 5K agreements. No worker,
-- scoring, proof, provider objects or legacy agreement dispatch is added.

create table public.duel_policy_versions (
  version text primary key,
  specification jsonb not null check (jsonb_typeof(specification) = 'object')
);
insert into public.duel_policy_versions values ('duel-fixture-5k-v1', '{
  "source":"fixture_official_5k_v1", "sport":"outdoor_running",
  "distance_meters":5000, "timing_basis":"organizer_chip",
  "precision_seconds":1, "attempts":1, "handicap":"none",
  "mode":"simulated", "currency":"USD", "stake_cents_each":2000,
  "fee_cents_each":0, "participant_count":2,
  "accept_within_hours":72, "accept_before_start_hours":1,
  "results_after_end_hours":72, "dispute_after_durable_notice_hours":168,
  "review_after_filing_hours":168, "finality_after_end_hours":720,
  "winner":"lower_valid_chip_seconds", "tie":"return_both_zero_fee",
  "confirmed_nonfinish":"qualifying_finisher_wins_after_review",
  "both_nonfinish":"void_zero_consequence",
  "missing_or_ambiguous_proof":"review_then_void_zero_consequence",
  "prestart_cancellation":"creator_or_either_accepted_runner_zero_consequence",
  "poststart_withdrawal":"withdrawn_no_contest_zero_consequence",
  "injury_or_event_cancellation":"void_zero_consequence",
  "settlement":"simulation_only_after_dispute_deadline_and_review",
  "review_timeout":"void_zero_consequence",
  "corrections":"append_only_no_automatic_new_consequence",
  "consent_version":"duel-simulated-consent-v1"
}');

-- Events are explicit, immutable service fixtures, never generated from a
-- client's title/URL. A fresh reset has no dated event to accidentally reuse.
create table public.duel_event_fixtures (
  id uuid primary key,
  policy_version text not null references public.duel_policy_versions(version),
  event_name text not null check (event_name = 'Fictional local 5K'),
  course text not null check (course = 'fixture_course_5k_v1'),
  wave text not null check (wave = 'fixture_common_wave_v1'),
  starts_at timestamptz not null check (isfinite(starts_at)),
  ends_at timestamptz not null check (isfinite(ends_at) and ends_at > starts_at),
  display_timezone text not null
);
create index duel_event_policy_idx on public.duel_event_fixtures(policy_version);

create table app.duel_runtime (
  singleton boolean primary key default true check (singleton),
  admission_enabled boolean not null default false
);
insert into app.duel_runtime(singleton) values (true);
create table app.duel_beta_allowlist (
  actor_id uuid primary key references public.profiles(id)
);

create table public.duel_challenges (
  id uuid primary key default extensions.gen_random_uuid(),
  creator_id uuid not null references public.profiles(id),
  invitee_id uuid not null references public.profiles(id),
  event_id uuid not null references public.duel_event_fixtures(id),
  policy_version text not null references public.duel_policy_versions(version),
  created_at timestamptz not null,
  starts_at timestamptz not null,
  accept_by timestamptz not null,
  terms jsonb not null,
  terms_digest text generated always as
    (encode(extensions.digest(terms::text, 'sha256'), 'hex')) stored,
  status text not null default 'invited'
    check (status in ('invited','scheduled','declined','expired','cancelled')),
  closed_at timestamptz,
  close_reason text check (close_reason in
    ('declined','acceptance_expired','creator_cancelled','participant_cancelled','account_deleted')),
  check (creator_id <> invitee_id),
  check (isfinite(created_at) and isfinite(starts_at) and isfinite(accept_by)),
  check (starts_at > created_at and starts_at <= created_at + interval '720 hours'),
  check (accept_by = least(created_at + interval '72 hours', starts_at - interval '1 hour')
    and accept_by > created_at),
  check ((status in ('declined','expired','cancelled')) = (closed_at is not null)),
  check ((closed_at is null) = (close_reason is null)),
  check (closed_at is null or closed_at >= created_at)
);
create index duel_creator_history_idx on public.duel_challenges(creator_id, created_at desc, id);
create index duel_invitee_history_idx on public.duel_challenges(invitee_id, created_at desc, id);
create index duel_event_idx on public.duel_challenges(event_id);
create index duel_policy_idx on public.duel_challenges(policy_version);

create table public.duel_participants (
  challenge_id uuid not null references public.duel_challenges(id),
  actor_id uuid not null references public.profiles(id),
  role text not null check (role in ('creator','invitee')),
  accepted_at timestamptz,
  consent_policy_version text references public.duel_policy_versions(version),
  consent_terms_digest text,
  declined_at timestamptz,
  primary key (challenge_id, actor_id),
  unique (challenge_id, role),
  check ((accepted_at is null) = (consent_policy_version is null)),
  check ((accepted_at is null) = (consent_terms_digest is null)),
  check (accepted_at is null or declined_at is null),
  check (role <> 'creator' or accepted_at is not null)
);
create index duel_participant_actor_idx on public.duel_participants(actor_id);
create index duel_participant_policy_idx on public.duel_participants(consent_policy_version);

-- Retained enrollment history, separate from every Personal/Solo slot.
create table app.duel_enrollments (
  challenge_id uuid not null,
  actor_id uuid not null,
  reserved_at timestamptz not null,
  released_at timestamptz,
  primary key (challenge_id, actor_id),
  foreign key (challenge_id, actor_id) references public.duel_participants(challenge_id, actor_id),
  check (released_at is null or released_at >= reserved_at)
);
create unique index duel_one_unsettled_per_actor on app.duel_enrollments(actor_id)
  where released_at is null;
create index duel_enrollment_actor_idx on app.duel_enrollments(actor_id);

-- The key spans all v1 user operations; reusing it for a different verb fails.
create table app.duel_requests (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  payload jsonb not null,
  challenge_id uuid not null references public.duel_challenges(id),
  committed_at timestamptz not null,
  primary key (actor_id, request_id)
);
create index duel_request_challenge_idx on app.duel_requests(challenge_id);

-- Writable only from owner-executed guarded functions. A client-supplied GUC
-- cannot confer the table owner's authority, even if grants later drift.
create function app.duel_guard_write_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid(
      (select relowner from pg_catalog.pg_class where oid = tg_relid))
     or coalesce(current_setting('app.duel_write_v1', true), '') <> 'on' then
    raise exception 'duel_write_requires_rpc' using errcode = '42501';
  end if;
  if tg_op in ('DELETE','TRUNCATE') and tg_table_name <> 'duel_beta_allowlist' then
    raise exception 'duel_history_is_retained' using errcode = '23001';
  end if;
  if tg_op = 'UPDATE' then
    if tg_table_name = 'duel_challenges' then
      if (to_jsonb(new) - array['status','closed_at','close_reason','terms_digest'])
           is distinct from (to_jsonb(old) - array['status','closed_at','close_reason','terms_digest'])
         or not ((old.status = 'invited' and new.status in ('scheduled','declined','expired','cancelled'))
              or (old.status = 'scheduled' and new.status = 'cancelled')) then
        raise exception 'duel_terms_or_transition_immutable' using errcode = '23001';
      end if;
    elsif tg_table_name = 'duel_participants' then
      if old.accepted_at is not null or old.declined_at is not null
         or (new.challenge_id,new.actor_id,new.role) is distinct from
            (old.challenge_id,old.actor_id,old.role)
         or (new.accepted_at is null and new.declined_at is null) then
        raise exception 'duel_consent_is_immutable' using errcode = '23001';
      end if;
    elsif tg_table_name = 'duel_enrollments' then
      if old.released_at is not null or new.released_at is null
         or (new.challenge_id,new.actor_id,new.reserved_at) is distinct from
            (old.challenge_id,old.actor_id,old.reserved_at) then
        raise exception 'duel_enrollment_is_retained' using errcode = '23001';
      end if;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Deferred checks enforce the aggregate at transaction commit, including
-- exactly two named rows and enrollment iff accepted and not yet closed.
create function app.duel_check_aggregate_v1() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.duel_challenges; v_id uuid;
begin
  if tg_table_name = 'duel_challenges' then v_id := new.id;
  else v_id := new.challenge_id; end if;
  select * into strict c from public.duel_challenges where id = v_id;
  if (select count(*) from public.duel_participants where challenge_id = c.id) <> 2
     or exists (select 1 from public.duel_participants p where p.challenge_id = c.id and (
       p.actor_id <> case p.role when 'creator' then c.creator_id else c.invitee_id end
       or (p.accepted_at is not null and (
         p.consent_policy_version <> c.policy_version or p.consent_terms_digest <> c.terms_digest
         or p.accepted_at < c.created_at or p.accepted_at >= c.accept_by))
       or (p.role = 'creator' and p.accepted_at <> c.created_at)
       or (p.role = 'invitee' and ((c.status = 'scheduled' and p.accepted_at is null)
         or (c.status in ('invited','expired','declined') and p.accepted_at is not null)
         or ((c.status = 'declined') <> (p.declined_at is not null))))
       or ((p.accepted_at is not null and c.closed_at is null) <>
         exists (select 1 from app.duel_enrollments e where e.challenge_id = c.id
           and e.actor_id = p.actor_id and e.released_at is null))
     )) then
    raise exception 'duel_aggregate_invariant' using errcode = '23514';
  end if;
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['public.duel_policy_versions','public.duel_event_fixtures',
    'public.duel_challenges','public.duel_participants','app.duel_enrollments',
    'app.duel_requests','app.duel_runtime','app.duel_beta_allowlist'] loop
    execute format('alter table %s enable row level security', t);
    execute format('revoke all on %s from public, anon, authenticated, service_role', t);
    if t in ('public.duel_policy_versions','public.duel_event_fixtures','app.duel_requests') then
      execute format('create trigger duel_immutable before update or delete on %s
        for each row execute function app.forbid_mutation()', t);
      execute format('create trigger duel_no_truncate before truncate on %s
        for each statement execute function app.forbid_mutation()', t);
    end if;
    execute format('create trigger duel_guard before insert or update or delete on %s
      for each row execute function app.duel_guard_write_v1()', t);
    execute format('create trigger duel_guard_truncate before truncate on %s
      for each statement execute function app.duel_guard_write_v1()', t);
    if t in ('public.duel_challenges','public.duel_participants','app.duel_enrollments') then
      execute format('create constraint trigger duel_aggregate after insert or update on %s
        deferrable initially deferred for each row execute function app.duel_check_aggregate_v1()', t);
    end if;
  end loop;
end;
$$;

create function app.duel_require_service_v1() returns void
language plpgsql set search_path = '' as $$
begin
  if not (current_setting('role') = 'service_role'
      or (current_setting('role') = 'none' and session_user = 'postgres')) then
    raise exception 'duel_service_required' using errcode = '42501';
  end if;
end;
$$;

create function public.set_duel_admission_v1(p_enabled boolean, p_actor_ids uuid[])
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform app.duel_require_service_v1();
  if p_enabled is null or p_actor_ids is null or cardinality(p_actor_ids) > 100
     or array_position(p_actor_ids,null) is not null then
    raise exception 'duel_invalid_admission' using errcode = '22023';
  end if;
  -- Actor locks precede runtime, as in create/accept. Empty disables everyone.
  perform app.lock_active_actors(p_actor_ids);
  perform 1 from app.duel_runtime where singleton for update;
  perform set_config('app.duel_write_v1','on',true);
  update app.duel_runtime set admission_enabled = p_enabled where singleton;
  delete from app.duel_beta_allowlist;
  insert into app.duel_beta_allowlist select distinct unnest(p_actor_ids);
  return p_enabled;
end;
$$;

create function public.curate_duel_fixture_event_v1(
  p_event_id uuid, p_starts_at timestamptz, p_ends_at timestamptz, p_display_timezone text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare e public.duel_event_fixtures;
begin
  perform app.duel_require_service_v1();
  if p_event_id is null or p_starts_at is null or p_ends_at is null
     or not isfinite(p_starts_at) or not isfinite(p_ends_at) or p_ends_at <= p_starts_at
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_display_timezone) then
    raise exception 'duel_invalid_event' using errcode = '22023';
  end if;
  perform set_config('app.duel_write_v1','on',true);
  insert into public.duel_event_fixtures values (p_event_id,'duel-fixture-5k-v1',
    'Fictional local 5K','fixture_course_5k_v1','fixture_common_wave_v1',
    p_starts_at,p_ends_at,p_display_timezone) on conflict (id) do nothing;
  select * into strict e from public.duel_event_fixtures where id = p_event_id;
  if (e.starts_at,e.ends_at,e.display_timezone) is distinct from
     (p_starts_at,p_ends_at,p_display_timezone) then
    raise exception 'duel_event_identity_conflict' using errcode = '22023';
  end if;
  return p_event_id;
end;
$$;

-- Lock all profiles (including tombstones) in stable order. Exact committed
-- recovery needs only the caller to remain active, not the other participant.
-- Never call require_active_caller BEFORE taking this pair lock.
create function app.duel_lock_pair_v1(p_a uuid, p_b uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform id from public.profiles where id in (p_a,p_b) order by id for update;
  if auth.uid() is null or not app.is_active_actor(auth.uid()) then
    raise exception 'duel_active_actor_required' using errcode = '42501';
  end if;
end;
$$;

create function app.duel_admit_pair_v1(p_a uuid,p_b uuid) returns void
language plpgsql set search_path = '' as $$
begin
  -- FOR SHARE linearizes runtime changes; history/recovery/cancel skip it.
  perform 1 from app.duel_runtime where singleton and admission_enabled for share;
  if not found or (select count(*) from app.duel_beta_allowlist where actor_id in (p_a,p_b)) <> 2
     or not app.is_active_actor(p_a) or not app.is_active_actor(p_b)
     or not app.is_friend(p_a,p_b) or app.is_blocked_either_way(p_a,p_b) then
    raise exception 'duel_admission_denied' using errcode = '42501';
  end if;
end;
$$;

create function app.duel_recover_request_v1(p_actor uuid,p_request uuid,p_payload jsonb)
returns uuid language plpgsql set search_path = '' as $$
declare r app.duel_requests;
begin
  if p_request is null then raise exception 'duel_request_required' using errcode = '22023'; end if;
  select * into r from app.duel_requests where actor_id = p_actor and request_id = p_request;
  if found and r.payload is distinct from p_payload then
    raise exception 'duel_request_payload_conflict' using errcode = '22023';
  end if;
  return r.challenge_id;
end;
$$;

-- Caller owns an actor lock before taking challenge locks. Deletion already
-- owns the deleted profile; it deliberately does NOT acquire an opponent lock.
create function app.duel_close_v1(p_id uuid,p_status text,p_reason text,p_now timestamptz)
returns void language plpgsql set search_path = '' as $$
begin
  perform set_config('app.duel_write_v1','on',true);
  update public.duel_challenges set status=p_status,close_reason=p_reason,closed_at=p_now where id=p_id;
  update app.duel_enrollments set released_at=p_now where challenge_id=p_id and released_at is null;
end;
$$;

-- Private manual clock seam; no API grant and no registered scheduler.
create function app.expire_duel_invitation_at_v1(p_id uuid,p_now timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
declare c public.duel_challenges;
begin
  if p_now is null or not isfinite(p_now) then
    raise exception 'duel_invalid_clock' using errcode = '22023';
  end if;
  select * into c from public.duel_challenges where id=p_id;
  if not found then return false; end if;
  perform id from public.profiles where id=c.creator_id for update;
  select * into strict c from public.duel_challenges where id=p_id for update;
  if c.status <> 'invited' or p_now < c.accept_by then return false; end if;
  perform app.duel_close_v1(c.id,'expired','acceptance_expired',p_now);
  return true;
end;
$$;

create function app.duel_release_overdue_v1(p_actor uuid,p_now timestamptz)
returns void language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in select c.id from public.duel_challenges c
      where c.creator_id=p_actor and c.status='invited' and c.accept_by <= p_now order by c.id loop
    perform app.expire_duel_invitation_at_v1(v_id,p_now);
  end loop;
end;
$$;

create function app.create_duel_at_v1(p_request_id uuid,p_invitee_id uuid,p_event_id uuid,
  p_expected_policy_version text,p_consent boolean,p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare a uuid := auth.uid(); v_payload jsonb; v_id uuid; v_now timestamptz;
  e public.duel_event_fixtures; v_policy jsonb; v_terms jsonb; v_digest text;
begin
  perform app.duel_lock_pair_v1(a,p_invitee_id);
  v_payload := jsonb_build_object('operation','create_duel_v1','invitee_id',p_invitee_id,
    'event_id',p_event_id,'policy_version',p_expected_policy_version,'consent',p_consent);
  v_id := app.duel_recover_request_v1(a,p_request_id,v_payload);
  if v_id is not null then return v_id; end if;
  if p_invitee_id is null or p_invitee_id = a or p_consent is distinct from true
      or p_expected_policy_version is distinct from 'duel-fixture-5k-v1' then
    raise exception 'duel_invalid_terms' using errcode = '22023';
  end if;
  perform app.duel_admit_pair_v1(a,p_invitee_id);
  -- Wall clock is sampled AFTER potentially blocking locks; transaction-start
  -- time must never admit a request that waited past the cutoff.
  v_now := coalesce(p_now,clock_timestamp());
  select * into e from public.duel_event_fixtures where id=p_event_id;
  if not found or not isfinite(v_now) or e.policy_version <> p_expected_policy_version
     or e.ends_at > v_now + interval '720 hours' or e.starts_at - interval '1 hour' <= v_now then
    raise exception 'duel_event_unavailable' using errcode = '22023';
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
  return v_id;
end;
$$;

create function app.respond_duel_at_v1(p_operation text,p_request_id uuid,p_challenge_id uuid,
  p_expected_policy_version text default null,p_expected_terms_digest text default null,
  p_now timestamptz default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a uuid := auth.uid(); c public.duel_challenges; v_payload jsonb; v_id uuid; v_now timestamptz;
begin
  select * into c from public.duel_challenges where id=p_challenge_id;
  if a is null or not found or a not in (c.creator_id,c.invitee_id) then
    raise exception 'duel_unavailable' using errcode = '42501';
  end if;
  perform app.duel_lock_pair_v1(c.creator_id,c.invitee_id);
  v_payload := jsonb_build_object('operation',p_operation,'challenge_id',p_challenge_id,
    'policy_version',p_expected_policy_version,'terms_digest',p_expected_terms_digest);
  v_id := app.duel_recover_request_v1(a,p_request_id,v_payload);
  if v_id is not null then return v_id; end if;
  if p_operation = 'accept_duel_v1' then perform app.duel_admit_pair_v1(c.creator_id,c.invitee_id); end if;
  select * into strict c from public.duel_challenges where id=p_challenge_id for update;
  v_now := coalesce(p_now,clock_timestamp());
  if not isfinite(v_now) or v_now < c.created_at then
    raise exception 'duel_invalid_clock' using errcode = '22023';
  end if;
  if c.closed_at is not null then raise exception 'duel_closed' using errcode = '55000'; end if;
  perform set_config('app.duel_write_v1','on',true);
  if p_operation = 'accept_duel_v1' then
    if a <> c.invitee_id then raise exception 'duel_invitee_required' using errcode = '42501'; end if;
    if c.status <> 'invited' then raise exception 'duel_already_accepted' using errcode = '55000'; end if;
    if v_now >= c.accept_by then raise exception 'duel_acceptance_expired' using errcode = '55000'; end if;
    if p_expected_policy_version is distinct from c.policy_version
       or p_expected_terms_digest is distinct from c.terms_digest then
      raise exception 'duel_consent_mismatch' using errcode = '22023';
    end if;
    perform app.duel_release_overdue_v1(a,v_now);
    if exists (select 1 from app.duel_enrollments where actor_id=a and released_at is null) then
      raise exception 'duel_slot_occupied' using errcode = '23505';
    end if;
    update public.duel_participants set accepted_at=v_now,consent_policy_version=c.policy_version,
      consent_terms_digest=c.terms_digest where challenge_id=c.id and actor_id=a;
    insert into app.duel_enrollments values(c.id,a,v_now,null);
    update public.duel_challenges set status='scheduled' where id=c.id;
  elsif p_operation = 'decline_duel_v1' then
    if a <> c.invitee_id then raise exception 'duel_invitee_required' using errcode = '42501'; end if;
    if c.status <> 'invited' or v_now >= c.accept_by then
      raise exception 'duel_invitation_unavailable' using errcode = '55000';
    end if;
    update public.duel_participants set declined_at=v_now where challenge_id=c.id and actor_id=a;
    perform app.duel_close_v1(c.id,'declined','declined',v_now);
  elsif p_operation = 'cancel_duel_v1' then
    if v_now >= c.starts_at then raise exception 'duel_already_started' using errcode = '55000'; end if;
    if a <> c.creator_id and c.status <> 'scheduled' then
      raise exception 'duel_accepted_participant_required' using errcode = '42501';
    end if;
    perform app.duel_close_v1(c.id,'cancelled',case when a=c.creator_id then 'creator_cancelled'
      else 'participant_cancelled' end,v_now);
  else raise exception 'duel_invalid_operation' using errcode = '22023';
  end if;
  insert into app.duel_requests values(a,p_request_id,v_payload,c.id,v_now);
  return c.id;
end;
$$;

create function public.create_duel_v1(p_request_id uuid,p_invitee_id uuid,p_event_id uuid,
  p_expected_policy_version text,p_consent boolean)
returns uuid language sql security definer set search_path = '' as $$
  select app.create_duel_at_v1(p_request_id,p_invitee_id,p_event_id,p_expected_policy_version,p_consent);
$$;
create function public.accept_duel_v1(p_request_id uuid,p_challenge_id uuid,
  p_expected_policy_version text,p_expected_terms_digest text)
returns uuid language sql security definer set search_path = '' as $$
  select app.respond_duel_at_v1('accept_duel_v1',p_request_id,p_challenge_id,p_expected_policy_version,p_expected_terms_digest);
$$;
create function public.decline_duel_v1(p_request_id uuid,p_challenge_id uuid)
returns uuid language sql security definer set search_path = '' as $$
  select app.respond_duel_at_v1('decline_duel_v1',p_request_id,p_challenge_id);
$$;
create function public.cancel_duel_v1(p_request_id uuid,p_challenge_id uuid)
returns uuid language sql security definer set search_path = '' as $$
  select app.respond_duel_at_v1('cancel_duel_v1',p_request_id,p_challenge_id);
$$;

create function app.duel_can_read_v1(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_active_actor(auth.uid()) and exists (select 1 from public.duel_challenges
    where id=p_id and auth.uid() in (creator_id,invitee_id));
$$;
create policy duel_pair_read on public.duel_challenges for select to authenticated
  using (app.duel_can_read_v1(id));
create policy duel_pair_read on public.duel_participants for select to authenticated
  using (app.duel_can_read_v1(challenge_id));
create policy duel_policy_read on public.duel_policy_versions for select to authenticated
  using (app.is_active_actor((select auth.uid())));
create policy duel_event_read on public.duel_event_fixtures for select to authenticated
  using (app.is_active_actor((select auth.uid())));
grant select on public.duel_challenges, public.duel_participants,
  public.duel_policy_versions,public.duel_event_fixtures to authenticated;

create function public.get_duel_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid; v_result jsonb;
begin
  a := app.require_active_caller();
  select to_jsonb(c) || jsonb_build_object('expiry_due',c.status='invited' and clock_timestamp() >= c.accept_by,
    'participants',(select jsonb_agg(to_jsonb(p) order by p.role) from public.duel_participants p where p.challenge_id=c.id))
    into v_result from public.duel_challenges c where c.id=p_challenge_id and a in (c.creator_id,c.invitee_id);
  if v_result is null then raise exception 'duel_unavailable' using errcode = '42501'; end if;
  return v_result;
end;
$$;
create function public.list_my_duels_v1(p_limit integer default 50,p_before timestamptz default null,
  p_before_id uuid default null) returns setof jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid;
begin
  a := app.require_active_caller();
  if p_limit is null or p_limit not between 1 and 100 or ((p_before is null) <> (p_before_id is null)) then
    raise exception 'duel_invalid_page' using errcode = '22023';
  end if;
  return query select public.get_duel_v1(c.id) from public.duel_challenges c
    where a in (c.creator_id,c.invitee_id) and (p_before is null or (c.created_at,c.id) < (p_before,p_before_id))
    order by c.created_at desc,c.id desc limit p_limit;
end;
$$;

create function app.resolve_duels_on_account_deletion_v1() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c public.duel_challenges;
begin
  if old.deleted_at is not null or new.deleted_at is null then return new; end if;
  if not exists (select 1 from app.account_deletion_transactions where transaction_id=txid_current()
    and backend_pid=pg_backend_pid() and actor_id=new.id) then
    raise exception 'duel_deletion_requires_rpc' using errcode = '42501';
  end if;
  for c in select * from public.duel_challenges where new.id in (creator_id,invitee_id)
      and closed_at is null order by id for update loop
    if new.deleted_at < c.starts_at then
      perform app.duel_close_v1(c.id,'cancelled','account_deleted',new.deleted_at);
    end if;
  end loop;
  perform set_config('app.duel_write_v1','on',true);
  delete from app.duel_beta_allowlist where actor_id=new.id;
  return new;
end;
$$;
create trigger profiles_resolve_duels_on_deletion after update of deleted_at on public.profiles
  for each row execute function app.resolve_duels_on_account_deletion_v1();

-- Revoke every new helper/wrapper, then grant only intentional entry points.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public') and p.proname like '%duel%v1' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end;
$$;
grant execute on function app.duel_can_read_v1(uuid) to authenticated;
grant execute on function public.create_duel_v1(uuid,uuid,uuid,text,boolean),
  public.accept_duel_v1(uuid,uuid,text,text), public.decline_duel_v1(uuid,uuid),
  public.cancel_duel_v1(uuid,uuid),public.get_duel_v1(uuid),
  public.list_my_duels_v1(integer,timestamptz,uuid) to authenticated;
grant execute on function public.set_duel_admission_v1(boolean,uuid[]),
  public.curate_duel_fixture_event_v1(uuid,timestamptz,timestamptz,text) to service_role;
