-- Migration 3 audits clearances that already exist. Install the forward guard
-- first in this transaction, then repeat that narrow audit so a clearance made
-- between the two migrations cannot escape either the audit or the trigger.

create function app.require_production_personal_diagnostic_clearance_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.cleared_at is null
     and new.cleared_at is not null
     and not exists (
       select 1
       from public.personal_trusted_diagnostics diagnostic
       where diagnostic.id = new.cleared_by_diagnostic_id
         and diagnostic.attestation_environment = 'production'
     )
  then
    raise exception 'only a production-origin trusted diagnostic may clear Personal eligibility'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.require_production_personal_diagnostic_clearance_v1() is
  'Fail-closed hold-clearance guard: only a diagnostic with durable production App Attest provenance may clear Personal eligibility.';

create trigger personal_holds_require_production_diagnostic
  before update on public.personal_eligibility_holds
  for each row execute function app.require_production_personal_diagnostic_clearance_v1();

-- CREATE TRIGGER and this audit commit together. Existing clearances that raced
-- migration 3 are now visible, while later clearances must pass the trigger.
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

revoke all on function
  app.require_production_personal_diagnostic_clearance_v1()
from public, anon, authenticated, service_role;
