-- M6.5 — quarantine Apple's attestation receipt beside the verified device
-- key.
--
-- The attestation proves the device key, but that proof does not authenticate
-- the separate PKCS#7 receipt field. Apple requires its signature, certificate
-- chain, App ID, creation time, and public-key binding to be checked
-- independently before fraud decisions use it. Retain the bytes so that
-- verifier can be added without asking the device for a new key, but mark them
-- unverified and keep them outside every client-accessible schema.

create table app.device_attestation_receipts (
  key_id                       bytea primary key
    references public.device_attestations (key_id) on delete cascade,
  initial_receipt              bytea not null,
  current_receipt              bytea not null,
  received_at                  timestamptz not null default now(),
  current_receipt_verified_at  timestamptz,
  refreshed_at                 timestamptz,

  constraint device_attestation_initial_receipt_size
    check (octet_length(initial_receipt) between 1 and 32768),
  constraint device_attestation_current_receipt_size
    check (octet_length(current_receipt) between 1 and 32768),
  constraint device_attestation_receipt_verification_order
    check (
      current_receipt_verified_at is null
      or current_receipt_verified_at >= received_at
    ),
  constraint device_attestation_receipt_refresh_order
    check (refreshed_at is null or refreshed_at >= received_at)
);

comment on table app.device_attestation_receipts is
  'Quarantined Apple App Attest receipts. Bytes are untrusted until an independent PKCS#7 verifier records current_receipt_verified_at.';
comment on column app.device_attestation_receipts.initial_receipt is
  'Original untrusted attStmt.receipt bytes retained for audit; never exposed through the client Data API.';
comment on column app.device_attestation_receipts.current_receipt is
  'Receipt candidate used by a future Apple fraud-assessment refresh flow; untrusted while current_receipt_verified_at is null.';

revoke all on table app.device_attestation_receipts
  from public, anon, authenticated, service_role;

-- A future receipt verifier may replace the current receipt and its validation
-- timestamp, but it may not erase the original audit source or move the row to
-- another device identity.
create trigger device_attestation_receipts_freeze_capture
  before update on app.device_attestation_receipts
  for each row execute function app.forbid_column_change(
    'key_id', 'initial_receipt', 'received_at'
  );

create function app.require_receipt_revalidation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_receipt is distinct from old.current_receipt
     and new.current_receipt_verified_at is not null then
    raise exception
      'replacing a current App Attest receipt must clear its verification timestamp'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

comment on function app.require_receipt_revalidation() is
  'Prevents a refreshed receipt from inheriting the previous receipt''s verification timestamp.';

create trigger device_attestation_receipts_require_revalidation
  before update on app.device_attestation_receipts
  for each row execute function app.require_receipt_revalidation();

-- Replace M3's four-argument registration RPC: a verified key without the
-- receipt Apple returned beside it is now an incomplete capture.
drop function public.register_device_key(
  uuid, bytea, bytea, public.attestation_environment
);

create function public.register_device_key(
  p_user_id             uuid,
  p_key_id              bytea,
  p_public_key          bytea,
  p_attestation_receipt bytea,
  p_environment         public.attestation_environment
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing public.device_attestations;
  v_receipt  bytea;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'complete onboarding before registering a device'
      using errcode = 'insufficient_privilege';
  end if;

  if p_attestation_receipt is null
     or octet_length(p_attestation_receipt) not between 1 and 32768 then
    raise exception 'App Attest receipt bytes are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- INSERT-first makes two concurrent copies of the same verified request
  -- idempotent too: the loser waits on the primary key, then inspects the row
  -- that won. A select-before-insert would let both see "missing" and turn an
  -- ordinary network retry into a unique-violation race.
  insert into public.device_attestations (key_id, user_id, public_key, environment)
  values (p_key_id, p_user_id, p_public_key, p_environment)
  on conflict (key_id) do nothing;

  select * into strict v_existing
  from public.device_attestations
  where key_id = p_key_id;

  if v_existing.user_id <> p_user_id then
    raise exception 'this device key is already registered to another account'
      using errcode = 'unique_violation';
  end if;

  if v_existing.public_key <> p_public_key
     or v_existing.environment <> p_environment then
    raise exception 'this device key was already registered with different key metadata'
      using errcode = 'unique_violation';
  end if;

  insert into app.device_attestation_receipts (
    key_id,
    initial_receipt,
    current_receipt
  )
  values (p_key_id, p_attestation_receipt, p_attestation_receipt)
  on conflict (key_id) do nothing;

  select initial_receipt into strict v_receipt
  from app.device_attestation_receipts
  where key_id = p_key_id;

  if v_receipt <> p_attestation_receipt then
    raise exception 'this device key was already registered with another receipt'
      using errcode = 'unique_violation';
  end if;
end;
$$;

comment on function public.register_device_key is
  'Records a verified App Attest key and quarantined unverified receipt bytes. service_role only; idempotent for its owner.';

revoke all on function public.register_device_key(
  uuid, bytea, bytea, bytea, public.attestation_environment
) from public, anon, authenticated;

grant execute on function public.register_device_key(
  uuid, bytea, bytea, bytea, public.attestation_environment
) to service_role;
