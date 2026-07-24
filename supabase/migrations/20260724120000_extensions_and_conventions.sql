-- Baseline: extensions and repo-wide conventions.
--
-- No domain tables live here. This migration only establishes the ground rules
-- every later migration relies on.
--
-- Convention 1: extensions live in the `extensions` schema, never `public`.
-- Convention 2: helper functions used by RLS policies live in `app`, which is
--   NOT exposed through PostgREST (see config.toml `[api].schemas`). A policy
--   can still call them; a client cannot.
-- Convention 3: every function is created with an explicit `search_path` so a
--   caller cannot shadow a referenced object with a same-named local one.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;
-- btree_gist lets a GiST exclusion constraint mix an equality column (user_id)
-- with a range column. M6 needs it to forbid overlapping venue check-ins.
create extension if not exists btree_gist with schema extensions;

-- Private schema for security-definer helpers and RLS predicates.
create schema if not exists app;

comment on schema app is
  'Internal helpers (RLS predicates, trigger functions). Never exposed via the Data API.';

revoke all on schema app from public, anon, authenticated;
grant usage on schema app to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Shared trigger: maintain updated_at
-- ---------------------------------------------------------------------------
create or replace function app.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.set_updated_at() is
  'BEFORE UPDATE trigger. Stamps updated_at from the transaction clock.';

-- ---------------------------------------------------------------------------
-- Shared trigger: hard append-only enforcement
-- ---------------------------------------------------------------------------
-- metric_snapshots (M3) is the evidence ledger. "Append-only" is a property we
-- assert in tests and enforce here, at the one layer a compromised client or a
-- careless service-role query cannot route around. Attached as a BEFORE
-- UPDATE OR DELETE trigger on any table that must never be rewritten.
create or replace function app.forbid_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception
    'table %.% is append-only; % is not permitted',
    tg_table_schema, tg_table_name, tg_op
    using errcode = 'restrict_violation';
end;
$$;

comment on function app.forbid_mutation() is
  'BEFORE UPDATE OR DELETE trigger. Rejects any mutation. Used on append-only ledgers.';
