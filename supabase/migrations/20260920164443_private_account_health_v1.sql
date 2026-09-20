-- A private account trial may omit device proof only after an operator enables
-- the exact project and enrolls the signed-in account. All other projects and
-- signed pending requests keep their original proof requirements.
alter table app.challenge_private_device_trial_v1
  add column require_device_verification boolean not null default true;

create function app.challenge_private_account_health_allowed_v1(p_actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app.challenge_private_device_trial_v1 trial
    join app.challenge_private_device_accounts_v1 enrolled on enrolled.actor_id = p_actor
    where trial.singleton and trial.enabled and not trial.require_device_verification
  );
$$;
create function app.challenge_private_account_health_require_v1(p_actor uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.challenge_private_account_health_allowed_v1(p_actor) then
    raise exception 'challenge_private_account_health_disabled' using errcode = '42501';
  end if;
end;
$$;
revoke all on function app.challenge_private_account_health_allowed_v1(uuid),
  app.challenge_private_account_health_require_v1(uuid)
  from public, anon, authenticated, service_role;

alter table app.challenge_real_health_readiness_requests_v1
  alter column device_key_id drop not null,
  alter column assertion_counter drop not null,
  add constraint challenge_real_readiness_proof_pair_v1
    check ((device_key_id is null) = (assertion_counter is null)),
  add column verification_mode text generated always as
    (case when device_key_id is null then 'private_account' else 'app_attest' end) stored;
alter table app.challenge_real_health_requests_v1
  alter column device_key_id drop not null,
  alter column assertion_counter drop not null,
  add constraint challenge_real_request_proof_pair_v1
    check ((device_key_id is null) = (assertion_counter is null)),
  add column verification_mode text generated always as
    (case when device_key_id is null then 'private_account' else 'app_attest' end) stored;

-- Replace only the proof predicates and counter writes in the established
-- session, gate, replay, source, agreement, time and revision transactions.
do $$
declare d text; marker text;
begin
  d := pg_get_functiondef('public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean,bigint)'::regprocedure);
  marker := 'response jsonb;';
  if position(marker in d)=0 then raise exception 'Unexpected readiness declaration'; end if;
  d := replace(d, marker, marker || E'\n  private_account boolean := p_device_key_id is null;');
  marker := 'or p_device_key_id is null or octet_length(p_device_key_id) <> 32';
  if position(marker in d)=0 then raise exception 'Unexpected readiness key check'; end if;
  d := replace(d, marker,
    'or (p_device_key_id is not null and octet_length(p_device_key_id) <> 32)');
  marker := 'or p_assertion_counter is null or p_assertion_counter <= 0';
  if position(marker in d)=0 then raise exception 'Unexpected readiness counter check'; end if;
  d := replace(d, marker,
    'or (p_device_key_id is null) <> (p_assertion_counter is null)
     or (p_assertion_counter is not null and p_assertion_counter <= 0)');
  marker := 'perform pg_catalog.pg_advisory_xact_lock(';
  if position(marker in d)=0 then raise exception 'Unexpected readiness lock'; end if;
  d := replace(d, marker,
    'if private_account then perform app.challenge_private_account_health_require_v1(p_actor_id); end if;
  ' || marker);
  marker := 'or device.key_id is null or device.user_id <> p_actor_id or device.revoked_at is not null';
  if position(marker in d)=0 then raise exception 'Unexpected readiness device gate'; end if;
  d := replace(d, marker,
    'or (not private_account and (device.key_id is null or device.user_id <> p_actor_id or device.revoked_at is not null))');
  marker := 'or not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id and receipt.current_receipt_verified_at is not null
     )';
  if position(marker in d)=0 then raise exception 'Unexpected readiness receipt gate'; end if;
  d := replace(d, marker, 'or (not private_account and not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id and receipt.current_receipt_verified_at is not null
     ))');
  marker := 'if p_assertion_counter <= device.sign_count then';
  if position(marker in d)=0 then raise exception 'Unexpected readiness replay gate'; end if;
  d := replace(d, marker, 'if not private_account and p_assertion_counter <= device.sign_count then');
  marker := 'or device.revoked_at is not null
     or not exists (';
  if position(marker in d)=0 then raise exception 'Unexpected readiness recheck'; end if;
  d := replace(d, marker, 'or (not private_account and device.revoked_at is not null)
     or not exists (');
  marker := 'update public.device_attestations
    set sign_count = p_assertion_counter, last_asserted_at = now_at
    where key_id = p_device_key_id;';
  if position(marker in d)=0 then raise exception 'Unexpected readiness counter write'; end if;
  d := replace(d, marker, 'if not private_account then ' || marker || ' end if;');
  execute d;

  d := pg_get_functiondef('public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)'::regprocedure);
  marker := 'response jsonb;';
  if position(marker in d)=0 then raise exception 'Unexpected ingest declaration'; end if;
  d := replace(d, marker, marker || E'\n  private_account boolean := p_device_key_id is null;');
  marker := 'or p_device_key_id is null or octet_length(p_device_key_id) <> 32';
  if position(marker in d)=0 then raise exception 'Unexpected ingest key check'; end if;
  d := replace(d, marker,
    'or (p_device_key_id is not null and octet_length(p_device_key_id) <> 32)');
  marker := 'or p_assertion_counter is null or p_assertion_counter <= 0';
  if position(marker in d)=0 then raise exception 'Unexpected ingest counter check'; end if;
  d := replace(d, marker,
    'or (p_device_key_id is null) <> (p_assertion_counter is null)
     or (p_assertion_counter is not null and p_assertion_counter <= 0)');
  marker := 'perform pg_catalog.pg_advisory_xact_lock(';
  if position(marker in d)=0 then raise exception 'Unexpected ingest lock'; end if;
  d := replace(d, marker,
    'if private_account then perform app.challenge_private_account_health_require_v1(actor); end if;
  ' || marker);
  marker := 'or device.key_id is null
     or device.user_id <> actor
     or device.revoked_at is not null
     or not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id
         and receipt.current_receipt_verified_at is not null
     )';
  if position(marker in d)=0 then raise exception 'Unexpected ingest device gate'; end if;
  d := replace(d, marker, 'or (not private_account and (device.key_id is null
     or device.user_id <> actor
     or device.revoked_at is not null
     or not exists (
       select 1 from app.device_attestation_receipts receipt
       where receipt.key_id = p_device_key_id
         and receipt.current_receipt_verified_at is not null
     )))');
  marker := 'if p_assertion_counter <= device.sign_count then';
  if position(marker in d)=0 then raise exception 'Unexpected ingest replay gate'; end if;
  d := replace(d, marker, 'if not private_account and p_assertion_counter <= device.sign_count then');
  marker := 'or device.revoked_at is not null
  then';
  if position(marker in d)=0 then raise exception 'Unexpected ingest recheck'; end if;
  d := replace(d, marker, 'or (not private_account and device.revoked_at is not null)
  then');
  marker := 'update public.device_attestations
  set sign_count = p_assertion_counter,
      last_asserted_at = now_at
  where key_id = p_device_key_id;';
  if position(marker in d)=0 then raise exception 'Unexpected ingest counter write'; end if;
  d := replace(d, marker, 'if not private_account then ' || marker || ' end if;');
  execute d;
end;
$$;
