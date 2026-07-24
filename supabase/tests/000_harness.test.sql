-- Proves the pgTAP harness itself works and the baseline migration applied.
-- If this file fails, nothing downstream can be trusted.

begin;
select plan(9);

-- ---------------------------------------------------------------------------
-- Extensions landed in `extensions`, not `public`
-- ---------------------------------------------------------------------------
select has_extension('extensions', 'pgcrypto', 'pgcrypto is installed in extensions');
select has_extension('extensions', 'citext', 'citext is installed in extensions');
select has_extension('extensions', 'btree_gist', 'btree_gist is installed in extensions');

-- ---------------------------------------------------------------------------
-- Private helper schema
-- ---------------------------------------------------------------------------
select has_schema('app', 'app schema exists');
select has_function('app', 'set_updated_at', 'app.set_updated_at() exists');
select has_function('app', 'forbid_mutation', 'app.forbid_mutation() exists');

-- The Data API must not expose `app`. PostgREST reaches a schema only when the
-- API roles hold USAGE on it, so absence of that grant is the real assertion.
select ok(
  not has_schema_privilege('anon', 'app', 'usage'),
  'anon cannot use the app schema'
);

-- ---------------------------------------------------------------------------
-- The append-only trigger actually rejects writes
-- ---------------------------------------------------------------------------
create table app._harness_ledger (id int primary key, note text);
create trigger _harness_append_only
  before update or delete on app._harness_ledger
  for each row execute function app.forbid_mutation();

insert into app._harness_ledger values (1, 'inserted');

select throws_ok(
  $$ update app._harness_ledger set note = 'rewritten' where id = 1 $$,
  '23001', -- restrict_violation. pgTAP matches on SQLSTATE, not condition name.
  null,
  'forbid_mutation blocks UPDATE on an append-only table'
);

select throws_ok(
  $$ delete from app._harness_ledger where id = 1 $$,
  '23001', -- restrict_violation. pgTAP matches on SQLSTATE, not condition name.
  null,
  'forbid_mutation blocks DELETE on an append-only table'
);

select * from finish();
rollback;
