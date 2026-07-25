-- Device attestation: the key, its owner, and its replay counter.
--
-- The properties that matter, in rough order of how much damage getting them
-- wrong would do:
--
--   * the assertion counter only ever goes up, because that single fact is what
--     stands between a captured ingest request and unlimited replay of it
--   * a key id is the digest of the key it names, so one key's id cannot be
--     pinned onto another key's bytes
--   * a key belongs to one account for life; a second claimant is refused
--   * re-registering your own key does not rewind the counter
--   * no client holds any verb but SELECT, and only on its own rows

begin;
select plan(33);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob');

-- Two well-formed uncompressed P-256 points. The coordinates are nonsense —
-- nothing here does elliptic-curve arithmetic — but the *shape* is what the
-- constraints are about, so it has to be right: 0x04 followed by 64 bytes.
create temporary table t_keys as
select
  ('\x04' || repeat('a1', 64))::bytea as alice_key,
  ('\x04' || repeat('b2', 64))::bytea as bob_key;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'device_attestations',
  'public.device_attestations exists');
select col_is_pk('public', 'device_attestations', 'key_id',
  'a key is identified by Apple''s key id');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.device_attestations'::regclass),
  'row level security is enabled on device_attestations'
);
select col_type_is('public', 'device_attestations', 'key_id', 'bytea',
  'the key id is stored as raw bytes, not base64, so it can be held to the key');

-- ---------------------------------------------------------------------------
-- The key id is the digest of the key
-- ---------------------------------------------------------------------------
-- This is the constraint that makes key substitution a database-level
-- impossibility rather than something the ingest function has to remember to
-- check. Apple derives the key id as SHA-256 over the uncompressed point, so
-- the two are not independent facts and are not stored as though they were.
select lives_ok(
  $$ insert into public.device_attestations (key_id, user_id, public_key, environment)
     select extensions.digest(alice_key, 'sha256'),
            '11111111-1111-1111-1111-111111111111', alice_key, 'production'
     from t_keys $$,
  'a key whose id is its own digest registers'
);

select throws_ok(
  $$ insert into public.device_attestations (key_id, user_id, public_key, environment)
     select extensions.digest(alice_key, 'sha256'),
            '22222222-2222-2222-2222-222222222222', bob_key, 'production'
     from t_keys $$,
  '23514',
  null,
  'one key''s id cannot be pinned onto another key''s bytes'
);

select throws_ok(
  $$ insert into public.device_attestations (key_id, user_id, public_key, environment)
     values (extensions.digest('x'::bytea, 'sha256'),
             '22222222-2222-2222-2222-222222222222',
             '\xdeadbeef'::bytea, 'production') $$,
  '23514',
  null,
  'a public key that is not a 65-byte uncompressed point is refused'
);

-- 0x02 and 0x03 are the compressed-point prefixes. They are the plausible wrong
-- answer here — the right length, the wrong encoding — and the digest Apple
-- publishes is over the uncompressed form, so accepting one would store a key
-- whose id could never match.
select throws_ok(
  $$ insert into public.device_attestations (key_id, user_id, public_key, environment)
     select extensions.digest(('\x02' || repeat('c3', 64))::bytea, 'sha256'),
            '22222222-2222-2222-2222-222222222222',
            ('\x02' || repeat('c3', 64))::bytea, 'production'
     from t_keys $$,
  '23514',
  null,
  'a compressed point is refused even though its length is right'
);

-- ---------------------------------------------------------------------------
-- The counter
-- ---------------------------------------------------------------------------
select is(
  (select sign_count from public.device_attestations),
  0::bigint,
  'a freshly registered key starts at counter zero'
);

select lives_ok(
  $$ update public.device_attestations set sign_count = 7 $$,
  'the counter moves forward'
);

select throws_ok(
  $$ update public.device_attestations set sign_count = 6 $$,
  '23001',
  null,
  'the counter cannot move backward'
);

-- Equal is refused at the ingest function rather than here, because "no
-- movement" is only a replay in the context of consuming an assertion, and this
-- trigger also has to tolerate the updates that touch other columns. The
-- strictly-greater rule is asserted in 110.
select lives_ok(
  $$ update public.device_attestations set sign_count = 7 $$,
  'rewriting the counter to its current value is not itself a violation'
);

select lives_ok(
  $$ update public.device_attestations set revoked_at = now() $$,
  'a key can be revoked without touching the counter'
);

select is(
  (select sign_count from public.device_attestations),
  7::bigint,
  'and revoking left the counter where it was'
);

update public.device_attestations set revoked_at = null;

-- ---------------------------------------------------------------------------
-- Frozen identity
-- ---------------------------------------------------------------------------
-- Two mechanisms as always (D21): the missing grant stops a client and the
-- trigger stops a privileged writer. These run as superuser, which is the layer
-- the missing grant cannot test.
select throws_ok(
  $$ update public.device_attestations
     set user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23001',
  null,
  'a key cannot be handed to another account'
);

select throws_ok(
  $$ update public.device_attestations
     set public_key = (select bob_key from t_keys) $$,
  '23001',
  null,
  'the public key behind a key id is immutable'
);

select throws_ok(
  $$ update public.device_attestations set environment = 'development' $$,
  '23001',
  null,
  'a production key cannot be relabelled as a development one'
);

select throws_ok(
  $$ update public.device_attestations set attested_at = now() - interval '1 year' $$,
  '23001',
  null,
  'the attestation timestamp cannot be backdated'
);

-- ---------------------------------------------------------------------------
-- register_device_key()
-- ---------------------------------------------------------------------------
select has_function('public', 'register_device_key',
  array['uuid', 'bytea', 'bytea', 'public.attestation_environment'],
  'public.register_device_key() exists');

-- Idempotent for its owner: a client whose response was lost retries, and being
-- refused would leave it unable to ingest at all.
select lives_ok(
  $$ select public.register_device_key(
       '11111111-1111-1111-1111-111111111111',
       (select extensions.digest(alice_key, 'sha256') from t_keys),
       (select alice_key from t_keys),
       'production') $$,
  're-registering your own key is idempotent'
);

select is(
  (select sign_count from public.device_attestations),
  7::bigint,
  'and it does not rewind the counter, which would undo the replay defence'
);

select throws_ok(
  $$ select public.register_device_key(
       '22222222-2222-2222-2222-222222222222',
       (select extensions.digest(alice_key, 'sha256') from t_keys),
       (select alice_key from t_keys),
       'production') $$,
  '23505',
  null,
  'a second account claiming the same key is refused'
);

select throws_ok(
  $$ select public.register_device_key(
       '99999999-9999-9999-9999-999999999999',
       (select extensions.digest(bob_key, 'sha256') from t_keys),
       (select bob_key from t_keys),
       'production') $$,
  '42501',
  null,
  'a device cannot be registered against an account that has not onboarded'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.device_attestations', 'select'),
  'authenticated may read its own device keys'
);
select ok(
  not has_table_privilege('authenticated', 'public.device_attestations', 'insert'),
  'authenticated cannot register a key directly; registration is attested'
);
select ok(
  not has_table_privilege('authenticated', 'public.device_attestations', 'update'),
  'authenticated cannot move the replay counter'
);
select ok(
  not has_table_privilege('authenticated', 'public.device_attestations', 'delete'),
  'authenticated cannot delete a key; keys are revoked'
);
select ok(
  not has_table_privilege('anon', 'public.device_attestations', 'select'),
  'anon holds nothing here'
);

-- register_device_key writes a table no client may write, so the default PUBLIC
-- EXECUTE grant on a new function has to go — the same reasoning D32 recorded
-- for app.activate_due_contests(). Without the revoke, any signed-in user could
-- register a key against any account.
select ok(
  not has_function_privilege('authenticated',
    'public.register_device_key(uuid, bytea, bytea, public.attestation_environment)',
    'execute'),
  'authenticated cannot call register_device_key'
);
select ok(
  has_function_privilege('service_role',
    'public.register_device_key(uuid, bytea, bytea, public.attestation_environment)',
    'execute'),
  'service_role can, which is how the Edge Function reaches it'
);

-- ---------------------------------------------------------------------------
-- RLS: your own keys, and only yours
-- ---------------------------------------------------------------------------
-- A public key is not a secret and a counter is not interesting, so the reason
-- this is scoped is narrower: the set of devices someone signs in from is
-- closer to a movement record than it looks.
insert into public.device_attestations (key_id, user_id, public_key, environment)
select extensions.digest(bob_key, 'sha256'),
       '22222222-2222-2222-2222-222222222222', bob_key, 'production'
from t_keys;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select is(
  (select count(*) from public.device_attestations),
  1::bigint,
  'alice sees one key: her own'
);

select is(
  (select user_id from public.device_attestations),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'and it is hers'
);

reset role;
select is(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'device_attestations'),
  1::bigint,
  'device_attestations carries exactly one policy: read your own'
);

select * from finish();
rollback;
