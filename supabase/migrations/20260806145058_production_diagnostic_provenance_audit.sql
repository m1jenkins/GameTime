-- Diagnostics do not contribute steps or coverage, but a trusted diagnostic
-- can clear the hold that gates entry into another Personal V1 challenge.
-- Production Edge handlers now refuse development/unknown keys for new calls.
-- This one-time audit prevents an older staging/development clearance from
-- being silently promoted into the production eligibility state.

do $$
begin
  if exists (
    select 1
    from public.personal_eligibility_holds hold
    join public.personal_trusted_diagnostics diagnostic
      on diagnostic.id = hold.cleared_by_diagnostic_id
    where hold.cleared_at is not null
      and diagnostic.attestation_environment is distinct from 'production'
  ) then
    raise exception 'existing Personal V1 eligibility hold was cleared by non-production or unknown diagnostic provenance; audit before migration'
      using errcode = 'check_violation';
  end if;
end;
$$;
