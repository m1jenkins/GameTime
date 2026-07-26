-- M6.5 — admit trust in an App Attest receipt through one digest-bound,
-- server-only write.
--
-- Receipt verification itself needs PKCS#7, X.509, and ASN.1 support, so it
-- remains in the Edge Function. The database owns the two facts application
-- code cannot make race-free:
--
--   * the time at which this exact receipt was first quarantined; and
--   * whether the exact current candidate, rather than a replaced receipt, is
--     the candidate the verifier just checked.
--
-- No role receives SELECT or UPDATE on the private receipt table. The verifier
-- reaches only the narrowly scoped function below.

-- A refreshed candidate is not verified before it was received. Clear any
-- legacy marker that could only have been written under the older, weaker
-- ordering constraint, then make that invariant executable for future writes.
update app.device_attestation_receipts
set current_receipt_verified_at = null
where current_receipt_verified_at is not null
  and current_receipt_verified_at < coalesce(refreshed_at, received_at);

alter table app.device_attestation_receipts
  drop constraint device_attestation_receipt_verification_order;

alter table app.device_attestation_receipts
  add constraint device_attestation_receipt_verification_order
  check (
    current_receipt_verified_at is null
    or current_receipt_verified_at >= coalesce(refreshed_at, received_at)
  );

-- Changing a function's return type requires replacing the function itself.
-- Its arguments and authorization boundary are unchanged. Returning the
-- immutable first-capture time lets receipt freshness be evaluated against
-- when the server actually received the bytes, including after a lost-response
-- retry.
drop function public.register_device_key(
  uuid, bytea, bytea, bytea, public.attestation_environment
);

create function public.register_device_key(
  p_user_id             uuid,
  p_key_id              bytea,
  p_public_key          bytea,
  p_attestation_receipt bytea,
  p_environment         public.attestation_environment
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing    public.device_attestations;
  v_receipt     bytea;
  v_received_at timestamptz;
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
  -- idempotent: the loser waits on the primary key, then inspects the row that
  -- won rather than manufacturing a second capture time.
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

  select receipt.initial_receipt, receipt.received_at
  into strict v_receipt, v_received_at
  from app.device_attestation_receipts receipt
  where receipt.key_id = p_key_id;

  if v_receipt <> p_attestation_receipt then
    raise exception 'this device key was already registered with another receipt'
      using errcode = 'unique_violation';
  end if;

  return v_received_at;
end;
$$;

comment on function public.register_device_key is
  'Records a verified App Attest key and quarantined receipt, returning its immutable first-capture time. service_role only; idempotent for its owner.';

revoke all on function public.register_device_key(
  uuid, bytea, bytea, bytea, public.attestation_environment
) from public, anon, authenticated, service_role;

grant execute on function public.register_device_key(
  uuid, bytea, bytea, bytea, public.attestation_environment
) to service_role;

create function public.mark_device_receipt_verified(
  p_key_id        bytea,
  p_receipt_sha256 bytea
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current_sha256 bytea;
  v_verified_at    timestamptz;
begin
  if p_key_id is null
     or octet_length(p_key_id) <> 32
     or p_receipt_sha256 is null
     or octet_length(p_receipt_sha256) <> 32 then
    raise exception 'the App Attest receipt candidate does not match'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The row lock closes the verifier/refresh race. Once the digest comparison
  -- succeeds, no refresh can replace current_receipt until this transaction has
  -- written the marker.
  select
    extensions.digest(receipt.current_receipt, 'sha256'),
    receipt.current_receipt_verified_at
  into v_current_sha256, v_verified_at
  from app.device_attestation_receipts receipt
  where receipt.key_id = p_key_id
  for update;

  if not found or v_current_sha256 <> p_receipt_sha256 then
    -- Missing and mismatched candidates intentionally share one result. The
    -- caller has no need for a private-receipt existence oracle.
    raise exception 'the App Attest receipt candidate does not match'
      using errcode = 'invalid_parameter_value';
  end if;

  -- An exact retry after a lost response returns the original proof time. It
  -- never makes an old receipt look newly verified.
  if v_verified_at is not null then
    return v_verified_at;
  end if;

  v_verified_at := clock_timestamp();

  update app.device_attestation_receipts receipt
  set current_receipt_verified_at = v_verified_at
  where receipt.key_id = p_key_id;

  return v_verified_at;
end;
$$;

comment on function public.mark_device_receipt_verified(bytea, bytea) is
  'Marks only the exact SHA-256-bound current App Attest receipt candidate verified, using a database-owned timestamp. service_role only.';

revoke all on function public.mark_device_receipt_verified(bytea, bytea)
  from public, anon, authenticated, service_role;

grant execute on function public.mark_device_receipt_verified(bytea, bytea)
  to service_role;
