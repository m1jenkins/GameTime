-- D144: optional Stripe sandbox commitment on real-Health personal goals.
--
-- A person may attach a commitment to a Personal Steps or Outdoor run goal.
-- The card is saved with a Stripe SetupIntent before consent. Nothing is
-- charged at commit time. One off-session charge of the committed amount is
-- queued only when the goal becomes final with a confirmed miss; success,
-- void, exclusion, cancellation and missing or partial data never charge.
-- The recipient is GameTime and is part of the frozen terms.
--
-- Committed goals use a new, versioned proof rule (complete_window_v1): a
-- shortfall counts only when the latest saved Health total covers the whole
-- goal window and was recorded by the result deadline (end + 48 hours).
-- Goals without a commitment keep byte-identical terms and the existing
-- evaluator. Nothing here is enabled by default, touches the legacy
-- Personal sandbox tables, or talks to live Stripe.

-- Settings: default-off runtime switch and per-account eligibility (D115 pattern).
create table app.challenge_commitment_runtime_v1 (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);
insert into app.challenge_commitment_runtime_v1 default values;

create table app.challenge_commitment_eligibility_v1 (
  actor_id uuid primary key references auth.users(id) on delete cascade,
  eligible boolean not null,
  updated_at timestamptz not null default clock_timestamp()
);

create table app.challenge_commitment_customers_v1 (
  actor_id uuid primary key,
  stripe_customer_id text not null unique check (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  livemode boolean not null default false check (not livemode),
  created_at timestamptz not null default clock_timestamp()
);

create table app.challenge_commitment_setups_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid not null,
  request_id uuid not null,
  amount_cents integer not null check (amount_cents between 100 and 5000 and amount_cents % 100 = 0),
  currency text not null default 'usd' check (currency = 'usd'),
  status text not null default 'pending_provider'
    check (status in ('pending_provider', 'requires_action', 'processing', 'succeeded', 'cancelled', 'consumed')),
  stripe_customer_id text check (stripe_customer_id is null or stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  stripe_setup_intent_id text unique check (stripe_setup_intent_id is null or stripe_setup_intent_id ~ '^seti_[A-Za-z0-9]+$'),
  stripe_payment_method_id text check (stripe_payment_method_id is null or stripe_payment_method_id ~ '^pm_[A-Za-z0-9]+$'),
  livemode boolean not null default false check (not livemode),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_by uuid,
  unique (actor_id, request_id),
  check ((status = 'succeeded' or status = 'consumed') = (stripe_payment_method_id is not null)),
  check ((status = 'consumed') = (consumed_by is not null))
);

create table app.challenge_commitment_agreements_v1 (
  challenge_id uuid primary key references app.challenge_lobbies_v1(id) on delete restrict,
  actor_id uuid not null,
  setup_id uuid not null unique references app.challenge_commitment_setups_v1(id) on delete restrict,
  amount_cents integer not null check (amount_cents between 100 and 5000 and amount_cents % 100 = 0),
  currency text not null check (currency = 'usd'),
  recipient_version text not null,
  terms_digest text not null,
  stripe_customer_id text not null check (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  stripe_payment_method_id text not null check (stripe_payment_method_id ~ '^pm_[A-Za-z0-9]+$'),
  created_at timestamptz not null default clock_timestamp()
);
create index challenge_commitment_agreements_actor on app.challenge_commitment_agreements_v1(actor_id);

create table app.challenge_commitment_charges_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  challenge_id uuid not null unique references app.challenge_commitment_agreements_v1(challenge_id) on delete restrict,
  actor_id uuid not null,
  amount_cents integer not null,
  currency text not null check (currency = 'usd'),
  idempotency_key text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'succeeded', 'requires_action', 'failed')),
  stripe_payment_intent_id text unique check (stripe_payment_intent_id is null or stripe_payment_intent_id ~ '^pi_[A-Za-z0-9]+$'),
  failure_code text check (failure_code is null or failure_code ~ '^[a-z0-9][a-z0-9_]*$'),
  attempt_count integer not null default 0 check (attempt_count between 0 and 3),
  first_attempt_at timestamptz,
  lease_owner uuid,
  lease_expires_at timestamptz,
  livemode boolean not null default false check (not livemode),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index challenge_commitment_charges_due on app.challenge_commitment_charges_v1(status, created_at);
create index challenge_commitment_charges_actor on app.challenge_commitment_charges_v1(actor_id);

create table app.challenge_commitment_webhook_receipts_v1 (
  stripe_event_id text primary key check (stripe_event_id ~ '^evt_[A-Za-z0-9]+$'),
  event_type text not null,
  object_id text not null,
  disposition text not null,
  received_at timestamptz not null default clock_timestamp()
);

alter table app.challenge_commitment_runtime_v1 enable row level security;
alter table app.challenge_commitment_eligibility_v1 enable row level security;
alter table app.challenge_commitment_customers_v1 enable row level security;
alter table app.challenge_commitment_setups_v1 enable row level security;
alter table app.challenge_commitment_agreements_v1 enable row level security;
alter table app.challenge_commitment_charges_v1 enable row level security;
alter table app.challenge_commitment_webhook_receipts_v1 enable row level security;
revoke all on app.challenge_commitment_runtime_v1, app.challenge_commitment_eligibility_v1,
  app.challenge_commitment_customers_v1, app.challenge_commitment_setups_v1,
  app.challenge_commitment_agreements_v1, app.challenge_commitment_charges_v1,
  app.challenge_commitment_webhook_receipts_v1
  from public, anon, authenticated, service_role;

-- Agreements and charges are an audit record: no rewrites of the binding.
create function app.challenge_commitment_immutable_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' or tg_op = 'TRUNCATE' then
    raise exception 'challenge_commitment_immutable' using errcode = '42501';
  end if;
  if tg_table_name = 'challenge_commitment_agreements_v1' then
    raise exception 'challenge_commitment_immutable' using errcode = '42501';
  end if;
  if (new.id, new.challenge_id, new.actor_id, new.amount_cents, new.currency, new.idempotency_key, new.created_at)
     is distinct from (old.id, old.challenge_id, old.actor_id, old.amount_cents, old.currency, old.idempotency_key, old.created_at)
     or old.status = 'succeeded' then
    raise exception 'challenge_commitment_immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger challenge_commitment_agreements_immutable before update or delete on app.challenge_commitment_agreements_v1
  for each row execute function app.challenge_commitment_immutable_v1();
create trigger challenge_commitment_agreements_no_truncate before truncate on app.challenge_commitment_agreements_v1
  for each statement execute function app.challenge_commitment_immutable_v1();
create trigger challenge_commitment_charges_immutable before update or delete on app.challenge_commitment_charges_v1
  for each row execute function app.challenge_commitment_immutable_v1();
create trigger challenge_commitment_charges_no_truncate before truncate on app.challenge_commitment_charges_v1
  for each statement execute function app.challenge_commitment_immutable_v1();

-- Which goals may carry a commitment. Activity minutes can never show a
-- complete shortfall and timed runs only give an upper bound, so both stay out.
create function app.challenge_commitment_pair_allowed_v1(p_policy text, p_source text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce((p_policy, p_source) in (
    ('personal_steps_goal_v1', 'apple_watch_steps_v1'),
    ('personal_distance_goal_v1', 'apple_workout_outdoor_distance_v1')), false)
$$;

create function app.challenge_commitment_lock_v1(p_actor uuid) returns void
language sql set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('challenge_commitment_v1:' || p_actor::text, 0))
$$;

-- Admission: switched on, account eligible, one open commitment, nothing unpaid.
create function app.challenge_commitment_admit_v1(p_actor uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if not coalesce((select enabled from app.challenge_commitment_runtime_v1 where singleton), false) then
    raise exception 'challenge_commitment_unavailable' using errcode = '42501';
  end if;
  if not coalesce((select eligible from app.challenge_commitment_eligibility_v1 where actor_id = p_actor), false)
     or not app.is_active_actor(p_actor) then
    raise exception 'challenge_commitment_unavailable' using errcode = '42501';
  end if;
  if exists (select 1 from app.challenge_commitment_charges_v1
             where actor_id = p_actor and status in ('requires_action', 'failed')) then
    raise exception 'challenge_commitment_unpaid' using errcode = '55000';
  end if;
  if exists (select 1 from app.challenge_commitment_agreements_v1 agreement
             join app.challenge_lobbies_v1 lobby on lobby.id = agreement.challenge_id
             where agreement.actor_id = p_actor
               and (lobby.status not in ('final', 'void', 'cancelled')
                 or exists (select 1 from app.challenge_commitment_charges_v1 charge
                            where charge.challenge_id = agreement.challenge_id
                              and charge.status in ('pending', 'processing')))) then
    raise exception 'challenge_commitment_limit' using errcode = '23505';
  end if;
end $$;

-- The commitment block that joins the frozen terms of a committed goal.
create function app.challenge_commitment_block_v1(p_amount integer) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'amount_cents', p_amount,
    'currency', 'usd',
    'recipient', 'gametime',
    'recipient_version', 'gametime_recipient_v1',
    'charge_rule', 'one_charge_after_confirmed_miss_v1',
    'proof_rule', 'complete_window_v1',
    'provider', 'stripe_sandbox')
$$;

create function app.challenge_commitment_terms_v1(
  p_actor uuid, p_policy text, p_config jsonb, p_target bigint, p_source text, p_setup_id uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare setup app.challenge_commitment_setups_v1; terms jsonb;
begin
  if not app.challenge_commitment_pair_allowed_v1(p_policy, p_source) then
    raise exception 'challenge_commitment_policy_unavailable' using errcode = '22023';
  end if;
  select * into setup from app.challenge_commitment_setups_v1 where id = p_setup_id and actor_id = p_actor;
  if setup.id is null or setup.status <> 'succeeded' or setup.expires_at <= clock_timestamp() then
    raise exception 'challenge_commitment_card_required' using errcode = '42501';
  end if;
  terms := app.challenge_real_health_personal_terms_v1(p_actor, p_policy, p_config, p_target, p_source);
  if (terms -> 'config' ->> 'amount_cents')::integer is distinct from setup.amount_cents then
    raise exception 'challenge_commitment_amount_mismatch' using errcode = '22023';
  end if;
  return terms || jsonb_build_object('simulation', 'stripe_sandbox',
    'commitment', app.challenge_commitment_block_v1(setup.amount_cents));
end $$;

create function public.challenge_commitment_preview_v1(
  p_policy text, p_config jsonb, p_target bigint, p_source_policy_version text, p_setup_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; terms jsonb;
begin
  actor := app.challenge_session_v1();
  perform app.challenge_commitment_admit_v1(actor);
  terms := app.challenge_commitment_terms_v1(actor, p_policy, p_config, p_target, p_source_policy_version, p_setup_id);
  return jsonb_build_object('terms', terms, 'digest', encode(extensions.digest(terms::text, 'sha256'), 'hex'));
end $$;

-- Personal commit: identical to the previous version unless the payload names
-- a saved card with commitment_setup_id.
create or replace function app.challenge_personal_commit_v1(a uuid, p jsonb)
returns jsonb language plpgsql set search_path = '' as $function$
declare
 terms jsonb; cfg jsonb; pol jsonb; cid uuid:=extensions.gen_random_uuid();
 c app.challenge_lobbies_v1; digest text; n timestamptz;
 source_version text:=p->>'source_policy_version'; real boolean:=p ? 'source_policy_version';
 committed boolean:=p ? 'commitment_setup_id'; setup app.challenge_commitment_setups_v1;
begin
 if committed and not real then raise exception 'challenge_commitment_policy_unavailable' using errcode='22023'; end if;
 if real then
  if jsonb_typeof(p->'source_policy_version') is distinct from 'string' then
   raise exception 'challenge_invalid_real_health_source' using errcode='22023';
  end if;
  if not app.challenge_real_health_policy_available_v1(source_version) then raise exception 'challenge_invalid_real_health_source' using errcode='22023'; end if;
  perform set_config('app.challenge_real_health_command_v1','on',true);
  n:=app.challenge_real_health_now_v1();
 else
  perform set_config('app.challenge_real_health_command_v1','off',true);
  n:=app.challenge_now_v1();
 end if;
 perform app.challenge_admit_v1(a);
 if p-(case when committed then array['op','policy','config','target','digest','consent','source_policy_version','commitment_setup_id']
            when real then array['op','policy','config','target','digest','consent','source_policy_version']
            else array['op','policy','config','target','digest','consent'] end)<>'{}'
    or not (p ?& array['op','policy','config','target','digest','consent'])
    or p->'consent' is distinct from 'true'::jsonb
    or jsonb_typeof(p->'target') is distinct from 'number'
    or p->>'target' !~ '^[0-9]+$'
    or (committed and (jsonb_typeof(p->'commitment_setup_id') is distinct from 'string'
      or p->>'commitment_setup_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
 then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
 if committed then
  perform app.challenge_commitment_lock_v1(a);
  perform app.challenge_commitment_admit_v1(a);
  select * into setup from app.challenge_commitment_setups_v1
   where id=(p->>'commitment_setup_id')::uuid and actor_id=a for update;
  terms:=app.challenge_commitment_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint,source_version,setup.id);
 elsif real then
  terms:=app.challenge_real_health_personal_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint,source_version);
 else
  terms:=app.challenge_personal_terms_v1(a,p->>'policy',p->'config',(p->>'target')::bigint);
 end if;
 digest:=encode(extensions.digest(terms::text,'sha256'),'hex');
 cfg:=terms->'config'; pol:=app.challenge_policy_v1(p->>'policy');
 if p->>'digest' is distinct from digest then raise exception 'challenge_consent_mismatch' using errcode='22023'; end if;
 if real then
  if not app.challenge_real_health_has_readiness_v1(a,source_version,(cfg->>'distance_mm')::bigint,n)
  then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 elsif not exists(select 1 from app.challenge_readiness_v1 readiness
   where readiness.actor_id=a and readiness.metric=pol->>'metric'
     and readiness.recorded_at between n-(case when pol->>'metric'='timed' then interval '90 days' else interval '30 days' end) and n)
 then raise exception 'challenge_readiness_required' using errcode='42501'; end if;
 perform id from public.profiles where id=a for update;
 perform app.challenge_session_v1();
 perform app.challenge_admit_v1(a);
 perform set_config('app.challenge_write_v1','on',true);
 insert into app.challenge_lobbies_v1(
   id,creator_id,policy,config,starts_at,ends_at,status,created_at,minimum,capacity,
   agreement_version,real_source_policy_version
 ) values (
   cid,a,p->>'policy',cfg,(cfg->>'starts_at')::timestamptz,(cfg->>'ends_at')::timestamptz,
   'scheduled',n,1,1,1,case when real then source_version else null end
 ) returning * into c;
 perform app.challenge_slot_v1(a,c);
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
 values(cid,a,true,(p->>'target')::bigint);
 insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
 values(cid,a,'personal',pol->>'metric',c.starts_at,c.ends_at);
 insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
 values(cid,1,terms,n);
 insert into app.challenge_consents_v1 values(cid,1,a,digest,n);
 if committed then
  update app.challenge_commitment_setups_v1 set status='consumed', consumed_by=cid where id=setup.id;
  insert into app.challenge_commitment_agreements_v1(challenge_id,actor_id,setup_id,amount_cents,currency,
    recipient_version,terms_digest,stripe_customer_id,stripe_payment_method_id,created_at)
  values(cid,a,setup.id,setup.amount_cents,setup.currency,terms->'commitment'->>'recipient_version',digest,
    setup.stripe_customer_id,setup.stripe_payment_method_id,n);
 end if;
 return jsonb_build_object('id',cid,'revision',c.revision,'status','scheduled');
end $function$;

-- complete_window_v1: like the real-Health evaluator, except that a saved
-- total covering the whole window by the result deadline is complete even
-- when it falls short. No total, a partial window, a deleted or unresolved
-- total, or one saved after the deadline stays unresolved and voids the goal.
create function app.challenge_commitment_evaluate_v1(p_challenge_id uuid, p_force_void boolean default false)
returns jsonb language plpgsql stable set search_path = '' as $$
declare challenge app.challenge_lobbies_v1; people jsonb; pol jsonb;
begin
  select * into challenge from app.challenge_lobbies_v1 where id = p_challenge_id;
  if challenge.id is null then
    raise exception 'challenge_unavailable' using errcode = '22023';
  end if;
  pol := app.challenge_policy_v1(challenge.policy);
  select coalesce(jsonb_agg(jsonb_build_object(
    'actor_id', slot.actor_id,
    'target', member.target,
    'excluded', member.exited_at is not null
      or app.challenge_actor_unavailable_v1(slot.actor_id)
      or exists (
        select 1
        from app.challenge_reviews_v1 review
        left join app.challenge_resolutions_v1 resolution on resolution.review_id = review.id
        where review.challenge_id = challenge.id
          and review.actor_id = slot.actor_id
          and (resolution.decision = 'exclude'
            or (resolution.review_id is null and app.challenge_real_health_now_v1() >= review.resolve_by))
      ),
    'state', case
      when fact.state = 'value' and fact.value >= member.target then 'complete'
      when fact.state = 'value' and fact.queried_through_at >= challenge.ends_at
        and fact.recorded_at <= challenge.ends_at + interval '48 hours' then 'complete'
      else 'unresolved' end,
    'value', case
      when fact.state = 'value' and fact.value >= member.target then fact.value
      when fact.state = 'value' and fact.queried_through_at >= challenge.ends_at
        and fact.recorded_at <= challenge.ends_at + interval '48 hours' then fact.value
      else null end
  ) order by slot.actor_id), '[]'::jsonb)
  into people
  from app.challenge_slots_v1 slot
  join app.challenge_members_v1 member
    on member.challenge_id = slot.challenge_id and member.actor_id = slot.actor_id
  left join lateral (
    select f.*
    from app.challenge_real_health_admissions_v1 admission
    join app.challenge_real_health_facts_v1 f
      on f.challenge_id = admission.challenge_id
     and f.actor_id = admission.actor_id
     and f.agreement_version = admission.agreement_version
    where admission.challenge_id = challenge.id
      and admission.actor_id = slot.actor_id
      and admission.agreement_version = challenge.agreement_version
    order by f.revision desc
    limit 1
  ) fact on true
  where slot.challenge_id = challenge.id;

  if pol ->> 'competition' <> 'goal' or pol ->> 'metric' = 'timed' then
    raise exception 'challenge_commitment_policy_unavailable' using errcode = '22023';
  end if;
  return app.challenge_evaluate_policy_v1(challenge.policy, people,
    (challenge.config ->> 'amount_cents')::integer, challenge.minimum, p_force_void);
end $$;

create or replace function app.challenge_evaluate_v1(p_id uuid, p_force_void boolean default false)
returns jsonb language plpgsql set search_path = '' as $function$
declare challenge app.challenge_lobbies_v1;
begin
  select * into challenge from app.challenge_lobbies_v1 where id = p_id;
  if challenge.real_source_policy_version is not null then
    if exists (select 1 from app.challenge_agreements_v1 agreement
               where agreement.challenge_id = p_id and agreement.version = challenge.agreement_version
                 and agreement.terms -> 'commitment' ->> 'proof_rule' = 'complete_window_v1') then
      return app.challenge_commitment_evaluate_v1(p_id, p_force_void);
    end if;
    return app.challenge_real_health_evaluate_v1(p_id,p_force_void);
  end if;
  return app.challenge_fictional_evaluate_v1(p_id,p_force_void);
end;
$function$;

-- Finality queues exactly one charge, only for a scored, confirmed miss.
-- The review and correction windows have closed by the time a final row exists.
create function app.challenge_commitment_on_final_v1() returns trigger
language plpgsql security definer set search_path = '' as $$
declare agreement app.challenge_commitment_agreements_v1;
begin
  select * into agreement from app.challenge_commitment_agreements_v1 where challenge_id = new.challenge_id;
  if agreement.challenge_id is null then return new; end if;
  if new.result ->> 'outcome' = 'scored'
     and new.result -> 'participants' -> agreement.actor_id::text ->> 'status' = 'missed' then
    insert into app.challenge_commitment_charges_v1(challenge_id, actor_id, amount_cents, currency, idempotency_key)
    values (agreement.challenge_id, agreement.actor_id, agreement.amount_cents, agreement.currency,
      'gt:challenge-commitment:v1:' || agreement.challenge_id::text || ':' || agreement.actor_id::text)
    on conflict (challenge_id) do nothing;
  end if;
  return new;
end $$;
create trigger challenge_commitment_final after insert on app.challenge_finals_v1
  for each row execute function app.challenge_commitment_on_final_v1();

-- Owner-facing reads.
create function public.challenge_commitment_availability_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid; reason text := null;
begin
  actor := app.challenge_session_v1();
  begin
    perform app.challenge_commitment_admit_v1(actor);
  exception when sqlstate '42501' or sqlstate '55000' or sqlstate '23505' then
    get stacked diagnostics reason = message_text;
  end;
  return jsonb_build_object('available', reason is null, 'reason', reason,
    'minimum_cents', 100, 'maximum_cents', 5000, 'step_cents', 100, 'currency', 'usd',
    'recipient', 'gametime', 'provider', 'stripe_sandbox',
    'policies', jsonb_build_array(
      jsonb_build_object('policy', 'personal_steps_goal_v1', 'source_policy_version', 'apple_watch_steps_v1'),
      jsonb_build_object('policy', 'personal_distance_goal_v1', 'source_policy_version', 'apple_workout_outdoor_distance_v1')));
end $$;

create function public.challenge_commitment_status_v1(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid; agreement app.challenge_commitment_agreements_v1; charge app.challenge_commitment_charges_v1;
  lobby app.challenge_lobbies_v1;
begin
  actor := app.challenge_session_v1();
  select * into agreement from app.challenge_commitment_agreements_v1
   where challenge_id = p_challenge_id and actor_id = actor;
  if agreement.challenge_id is null then return null; end if;
  select * into lobby from app.challenge_lobbies_v1 where id = p_challenge_id;
  select * into charge from app.challenge_commitment_charges_v1 where challenge_id = p_challenge_id;
  return jsonb_build_object(
    'challenge_id', agreement.challenge_id,
    'amount_cents', agreement.amount_cents,
    'currency', agreement.currency,
    'recipient', 'gametime',
    'provider', 'stripe_sandbox',
    'state', case
      when charge.id is not null then case charge.status
        when 'pending' then 'charge_processing' when 'processing' then 'charge_processing'
        when 'succeeded' then 'charged' when 'requires_action' then 'charge_needs_attention'
        else 'charge_failed' end
      when lobby.status = 'final' then 'not_charged'
      when lobby.status in ('void', 'cancelled') then 'not_charged'
      else 'committed' end,
    'failure_code', charge.failure_code);
end $$;

-- Service-only commands used by the Edge Functions. None of them runs for a
-- signed-in client; service_role has no direct table access.
create function public.challenge_commitment_begin_setup_service_v1(p_actor uuid, p_request_id uuid, p_amount_cents integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare setup app.challenge_commitment_setups_v1;
begin
  if p_actor is null or p_request_id is null then
    raise exception 'challenge_commitment_invalid_request' using errcode = '22023';
  end if;
  perform app.challenge_commitment_lock_v1(p_actor);
  select * into setup from app.challenge_commitment_setups_v1 where actor_id = p_actor and request_id = p_request_id;
  if setup.id is not null then
    if setup.amount_cents <> p_amount_cents then
      raise exception 'challenge_commitment_request_conflict' using errcode = '22023';
    end if;
  else
    perform app.challenge_commitment_admit_v1(p_actor);
    if p_amount_cents is null or p_amount_cents not between 100 and 5000 or p_amount_cents % 100 <> 0 then
      raise exception 'challenge_commitment_invalid_amount' using errcode = '22023';
    end if;
    insert into app.challenge_commitment_setups_v1(actor_id, request_id, amount_cents, expires_at,
      stripe_customer_id)
    values (p_actor, p_request_id, p_amount_cents, clock_timestamp() + interval '24 hours',
      (select stripe_customer_id from app.challenge_commitment_customers_v1 where actor_id = p_actor))
    returning * into setup;
  end if;
  return jsonb_build_object('setup_id', setup.id, 'status', setup.status, 'amount_cents', setup.amount_cents,
    'stripe_customer_id', setup.stripe_customer_id, 'stripe_setup_intent_id', setup.stripe_setup_intent_id,
    'expires_at', setup.expires_at);
end $$;

create function public.challenge_commitment_record_customer_service_v1(p_actor uuid, p_customer_id text, p_livemode boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_livemode is distinct from false then
    raise exception 'challenge_commitment_livemode_refused' using errcode = '42501';
  end if;
  perform app.challenge_commitment_lock_v1(p_actor);
  insert into app.challenge_commitment_customers_v1(actor_id, stripe_customer_id) values (p_actor, p_customer_id)
  on conflict (actor_id) do nothing;
  if (select stripe_customer_id from app.challenge_commitment_customers_v1 where actor_id = p_actor) <> p_customer_id then
    raise exception 'challenge_commitment_customer_conflict' using errcode = '23505';
  end if;
  update app.challenge_commitment_setups_v1 set stripe_customer_id = p_customer_id
   where actor_id = p_actor and stripe_customer_id is null and status = 'pending_provider';
end $$;

create function public.challenge_commitment_record_setup_service_v1(
  p_actor uuid, p_setup_id uuid, p_setup_intent_id text, p_payment_method_id text, p_status text, p_livemode boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare setup app.challenge_commitment_setups_v1; next_status text;
begin
  if p_livemode is distinct from false then
    raise exception 'challenge_commitment_livemode_refused' using errcode = '42501';
  end if;
  perform app.challenge_commitment_lock_v1(p_actor);
  select * into setup from app.challenge_commitment_setups_v1 where id = p_setup_id and actor_id = p_actor for update;
  if setup.id is null then raise exception 'challenge_commitment_unavailable' using errcode = '42501'; end if;
  if setup.stripe_setup_intent_id is not null and setup.stripe_setup_intent_id <> p_setup_intent_id then
    raise exception 'challenge_commitment_setup_conflict' using errcode = '23505';
  end if;
  if setup.status = 'consumed' then
    return jsonb_build_object('setup_id', setup.id, 'status', setup.status);
  end if;
  next_status := case p_status
    when 'succeeded' then 'succeeded' when 'requires_action' then 'requires_action'
    when 'requires_confirmation' then 'pending_provider' when 'requires_payment_method' then 'pending_provider'
    when 'processing' then 'processing' when 'canceled' then 'cancelled' else null end;
  if next_status is null or (next_status = 'succeeded' and p_payment_method_id is null) then
    raise exception 'challenge_commitment_invalid_request' using errcode = '22023';
  end if;
  update app.challenge_commitment_setups_v1
     set stripe_setup_intent_id = p_setup_intent_id, status = next_status,
         stripe_payment_method_id = case when next_status = 'succeeded' then p_payment_method_id else null end
   where id = setup.id returning * into setup;
  return jsonb_build_object('setup_id', setup.id, 'status', setup.status);
end $$;

create function public.challenge_commitment_claim_charges_service_v1(p_lease_owner uuid, p_limit integer default 10)
returns table(charge_id uuid, challenge_id uuid, amount_cents integer, currency text, idempotency_key text,
  stripe_customer_id text, stripe_payment_method_id text, attempt_count integer)
language plpgsql security definer set search_path = '' as $$
begin
  if p_lease_owner is null or p_limit is null or p_limit not between 1 and 50 then
    raise exception 'challenge_commitment_invalid_request' using errcode = '22023';
  end if;
  if not coalesce((select enabled from app.challenge_commitment_runtime_v1 where singleton), false) then
    return;
  end if;
  return query
  with due as (
    select charge.id from app.challenge_commitment_charges_v1 charge
    where charge.status = 'pending'
       or (charge.status = 'processing' and charge.lease_expires_at <= clock_timestamp()
           and charge.attempt_count < 3 and charge.first_attempt_at > clock_timestamp() - interval '23 hours')
    order by charge.created_at
    limit p_limit
    for update skip locked
  ), claimed as (
    update app.challenge_commitment_charges_v1 charge
       set status = 'processing', lease_owner = p_lease_owner,
           lease_expires_at = clock_timestamp() + interval '2 minutes',
           attempt_count = charge.attempt_count + 1,
           first_attempt_at = coalesce(charge.first_attempt_at, clock_timestamp()),
           updated_at = clock_timestamp()
      from due where charge.id = due.id
    returning charge.*
  )
  select claimed.id, claimed.challenge_id, claimed.amount_cents, claimed.currency, claimed.idempotency_key,
         agreement.stripe_customer_id, agreement.stripe_payment_method_id, claimed.attempt_count
    from claimed join app.challenge_commitment_agreements_v1 agreement using (challenge_id);
end $$;

-- Record the result of one dispatch attempt. 'processing' means the provider
-- call was ambiguous (a transport error): the lease lapses and the same
-- idempotency key is retried, at most three times within 23 hours. A decline
-- is final; there are no automatic retries after a decline (D113).
create function public.challenge_commitment_record_charge_service_v1(
  p_charge_id uuid, p_lease_owner uuid, p_status text, p_payment_intent_id text, p_failure_code text, p_livemode boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare charge app.challenge_commitment_charges_v1;
begin
  if p_livemode is distinct from false then
    raise exception 'challenge_commitment_livemode_refused' using errcode = '42501';
  end if;
  if p_status not in ('succeeded', 'requires_action', 'failed', 'processing') then
    raise exception 'challenge_commitment_invalid_request' using errcode = '22023';
  end if;
  select * into charge from app.challenge_commitment_charges_v1 where id = p_charge_id for update;
  if charge.id is null or charge.lease_owner is distinct from p_lease_owner or charge.status <> 'processing' then
    raise exception 'challenge_commitment_lease_lost' using errcode = '40001';
  end if;
  update app.challenge_commitment_charges_v1
     set status = case when p_status = 'processing' and charge.attempt_count >= 3 then 'failed' else p_status end,
         stripe_payment_intent_id = coalesce(p_payment_intent_id, charge.stripe_payment_intent_id),
         failure_code = case when p_status = 'processing' and charge.attempt_count >= 3 then 'provider_unreachable'
                             when p_status in ('failed', 'requires_action') then coalesce(p_failure_code, p_status)
                             else null end,
         lease_owner = case when p_status = 'processing' then charge.lease_owner else null end,
         lease_expires_at = case when p_status = 'processing' then clock_timestamp() else null end,
         updated_at = clock_timestamp()
   where id = charge.id returning * into charge;
  return jsonb_build_object('charge_id', charge.id, 'status', charge.status);
end $$;

-- Webhooks reconcile PaymentIntent and SetupIntent state after the Edge
-- Function has re-fetched the object from Stripe.
create function public.challenge_commitment_apply_webhook_service_v1(
  p_event_id text, p_event_type text, p_object_kind text, p_object_id text, p_status text,
  p_payment_method_id text, p_failure_code text, p_livemode boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare disposition text := 'ignored'; charge app.challenge_commitment_charges_v1; setup app.challenge_commitment_setups_v1;
begin
  if p_livemode is distinct from false then
    raise exception 'challenge_commitment_livemode_refused' using errcode = '42501';
  end if;
  if exists (select 1 from app.challenge_commitment_webhook_receipts_v1 where stripe_event_id = p_event_id) then
    return jsonb_build_object('disposition', 'duplicate');
  end if;
  if p_object_kind = 'payment_intent' then
    select * into charge from app.challenge_commitment_charges_v1 where stripe_payment_intent_id = p_object_id for update;
    if charge.id is not null and charge.status <> 'succeeded' then
      update app.challenge_commitment_charges_v1
         set status = case p_status when 'succeeded' then 'succeeded'
                                    when 'requires_action' then 'requires_action'
                                    when 'requires_payment_method' then 'failed'
                                    when 'canceled' then 'failed'
                                    else charge.status end,
             failure_code = case when p_status = 'succeeded' then null
                                 when p_status in ('requires_payment_method', 'canceled', 'requires_action')
                                   then coalesce(p_failure_code, charge.failure_code, p_status)
                                 else charge.failure_code end,
             lease_owner = case when p_status in ('succeeded', 'requires_action', 'requires_payment_method', 'canceled') then null else charge.lease_owner end,
             lease_expires_at = case when p_status in ('succeeded', 'requires_action', 'requires_payment_method', 'canceled') then null else charge.lease_expires_at end,
             updated_at = clock_timestamp()
       where id = charge.id;
      disposition := 'applied';
    end if;
  elsif p_object_kind = 'setup_intent' then
    select * into setup from app.challenge_commitment_setups_v1 where stripe_setup_intent_id = p_object_id;
    if setup.id is not null and setup.status not in ('consumed') then
      perform public.challenge_commitment_record_setup_service_v1(setup.actor_id, setup.id, p_object_id,
        p_payment_method_id, p_status, p_livemode);
      disposition := 'applied';
    end if;
  end if;
  insert into app.challenge_commitment_webhook_receipts_v1(stripe_event_id, event_type, object_id, disposition)
  values (p_event_id, p_event_type, p_object_id, disposition);
  return jsonb_build_object('disposition', disposition);
end $$;

-- Operator controls (service role only), mirroring the legacy sandbox controls.
create function public.challenge_commitment_set_runtime_v1(p_enabled boolean) returns void
language sql security definer set search_path = '' as $$
  update app.challenge_commitment_runtime_v1 set enabled = p_enabled, updated_at = clock_timestamp() where singleton
$$;
create function public.challenge_commitment_set_eligibility_v1(p_actor uuid, p_eligible boolean) returns void
language sql security definer set search_path = '' as $$
  insert into app.challenge_commitment_eligibility_v1(actor_id, eligible) values (p_actor, p_eligible)
  on conflict (actor_id) do update set eligible = excluded.eligible, updated_at = clock_timestamp()
$$;

revoke all on function
  app.challenge_commitment_immutable_v1(),
  app.challenge_commitment_pair_allowed_v1(text, text),
  app.challenge_commitment_lock_v1(uuid),
  app.challenge_commitment_admit_v1(uuid),
  app.challenge_commitment_block_v1(integer),
  app.challenge_commitment_terms_v1(uuid, text, jsonb, bigint, text, uuid),
  app.challenge_commitment_evaluate_v1(uuid, boolean),
  app.challenge_commitment_on_final_v1(),
  public.challenge_commitment_preview_v1(text, jsonb, bigint, text, uuid),
  public.challenge_commitment_availability_v1(),
  public.challenge_commitment_status_v1(uuid),
  public.challenge_commitment_begin_setup_service_v1(uuid, uuid, integer),
  public.challenge_commitment_record_customer_service_v1(uuid, text, boolean),
  public.challenge_commitment_record_setup_service_v1(uuid, uuid, text, text, text, boolean),
  public.challenge_commitment_claim_charges_service_v1(uuid, integer),
  public.challenge_commitment_record_charge_service_v1(uuid, uuid, text, text, text, boolean),
  public.challenge_commitment_apply_webhook_service_v1(text, text, text, text, text, text, text, boolean),
  public.challenge_commitment_set_runtime_v1(boolean),
  public.challenge_commitment_set_eligibility_v1(uuid, boolean)
from public, anon, authenticated, service_role;

grant execute on function
  public.challenge_commitment_preview_v1(text, jsonb, bigint, text, uuid),
  public.challenge_commitment_availability_v1(),
  public.challenge_commitment_status_v1(uuid)
to authenticated;

grant execute on function
  public.challenge_commitment_begin_setup_service_v1(uuid, uuid, integer),
  public.challenge_commitment_record_customer_service_v1(uuid, text, boolean),
  public.challenge_commitment_record_setup_service_v1(uuid, uuid, text, text, text, boolean),
  public.challenge_commitment_claim_charges_service_v1(uuid, integer),
  public.challenge_commitment_record_charge_service_v1(uuid, uuid, text, text, text, boolean),
  public.challenge_commitment_apply_webhook_service_v1(text, text, text, text, text, text, text, boolean),
  public.challenge_commitment_set_runtime_v1(boolean),
  public.challenge_commitment_set_eligibility_v1(uuid, boolean)
to service_role;
