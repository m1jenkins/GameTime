-- P8 real-source rows use the established challenge-v1 deletion clocks.  A
-- readiness receipt is pre-consent operational state, and normalized facts plus
-- their value-bearing ingress envelopes are detailed case material. Admissions
-- remain only for the existing pseudonymous agreement/consent window. The source-policy
-- registry and real runtime contain no actor data and remain immutable.
begin;

create or replace function app.challenge_real_health_retention_guard_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid = tg_relid))
     or coalesce(current_setting('app.challenge_write_v1', true), '') <> 'on'
  then
    raise exception 'challenge_rpc_required' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;
  if tg_op = 'DELETE'
     and coalesce(current_setting('app.challenge_deletion_cleanup_v1', true), '') = 'on'
  then
    return old;
  end if;
  raise exception 'challenge_immutable' using errcode = '23001';
end;
$$;

-- Readiness remains the only mutable real-source record.  Deletion is still
-- confined to the account-deletion cleanup transaction; no ordinary source
-- command gains erase access.
create or replace function app.challenge_real_health_runtime_guard_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> pg_catalog.pg_get_userbyid((select relowner from pg_catalog.pg_class where oid = tg_relid))
     or coalesce(current_setting('app.challenge_write_v1', true), '') <> 'on'
  then
    raise exception 'challenge_rpc_required' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    return new;
  end if;
  if tg_op = 'DELETE'
     and tg_table_name = 'challenge_real_health_readiness_v1'
     and coalesce(current_setting('app.challenge_deletion_cleanup_v1', true), '') = 'on'
  then
    return old;
  end if;
  raise exception 'challenge_immutable' using errcode = '23001';
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'real_health_admissions', 'real_health_readiness_requests',
    'real_health_facts', 'real_health_requests'
  ] loop
    execute format('drop trigger challenge_%s_guard on app.challenge_%s_v1', table_name, table_name);
    execute format('drop trigger challenge_%s_no_truncate on app.challenge_%s_v1', table_name, table_name);
    execute format('create trigger challenge_%s_guard before insert or update or delete on app.challenge_%s_v1 for each row execute function app.challenge_real_health_retention_guard_v1()', table_name, table_name);
    execute format('create trigger challenge_%s_no_truncate before truncate on app.challenge_%s_v1 for each statement execute function app.challenge_real_health_retention_guard_v1()', table_name, table_name);
  end loop;
end;
$$;

drop trigger challenge_real_health_readiness_no_truncate on app.challenge_real_health_readiness_v1;
create trigger challenge_real_health_readiness_no_truncate
  before truncate on app.challenge_real_health_readiness_v1
  for each statement execute function app.challenge_real_health_runtime_guard_v1();

-- These helpers are deliberately private.  The public deletion state machine
-- already owns its locks, receipt retries, hold checks, and audit markers.
create function app.challenge_real_health_cleanup_identity_v1(p_actor_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  delete from app.challenge_real_health_readiness_requests_v1
  where actor_id = p_actor_id;
  delete from app.challenge_real_health_readiness_v1
  where actor_id = p_actor_id;
end;
$$;

create function app.challenge_real_health_cleanup_case_content_v1(p_actor_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  delete from app.challenge_real_health_facts_v1
  where actor_id = p_actor_id;
  delete from app.challenge_real_health_requests_v1
  where actor_id = p_actor_id;
end;
$$;

do $$
declare definition text;
declare marker text := 'delete from app.challenge_readiness_v1 where actor_id = p_actor_id;';
begin
  definition := pg_get_functiondef('public.challenge_cleanup_account_deletion_v1(uuid)'::regprocedure);
  if position(marker in definition) = 0 then
    raise exception 'Unexpected account deletion identity cleanup source';
  end if;
  definition := replace(
    definition,
    marker,
    marker || E'\n  perform app.challenge_real_health_cleanup_identity_v1(p_actor_id);'
  );
  execute definition;
end;
$$;

do $$
declare definition text;
declare marker text := 'delete from app.challenge_facts_v1 where actor_id = p_actor_id;';
begin
  definition := pg_get_functiondef('public.challenge_cleanup_account_deletion_case_content_v1(uuid)'::regprocedure);
  if position(marker in definition) = 0 then
    raise exception 'Unexpected account deletion case cleanup source';
  end if;
  definition := replace(
    definition,
    marker,
    marker || E'\n  perform app.challenge_real_health_cleanup_case_content_v1(p_actor_id);'
  );
  execute definition;
end;
$$;

-- `app.challenge_fact_projection_v1` remains the sole actor projection: it
-- returns the existing normalized fact shape after membership/privacy checks.
-- Admissions, readiness and request payloads stay private and no direct table
-- grant is introduced by this retention integration.
alter table app.challenge_real_health_admissions_v1 enable row level security;
alter table app.challenge_real_health_readiness_v1 enable row level security;
alter table app.challenge_real_health_readiness_requests_v1 enable row level security;
alter table app.challenge_real_health_facts_v1 enable row level security;
alter table app.challenge_real_health_requests_v1 enable row level security;
revoke all on table
  app.challenge_real_health_admissions_v1,
  app.challenge_real_health_readiness_v1,
  app.challenge_real_health_readiness_requests_v1,
  app.challenge_real_health_facts_v1,
  app.challenge_real_health_requests_v1
from public, anon, authenticated, service_role;
revoke all on function
  app.challenge_real_health_retention_guard_v1(),
  app.challenge_real_health_runtime_guard_v1(),
  app.challenge_real_health_cleanup_identity_v1(uuid),
  app.challenge_real_health_cleanup_case_content_v1(uuid)
from public, anon, authenticated, service_role;

commit;
