-- Step 2A Solo contract foundation: locked owner terms, rollout gates,
-- exact-request creation, owner-only reads, and a service-owned write surface.

begin;
select no_plan();

set local timezone = 'UTC';

-- ---------------------------------------------------------------------------
-- Schema, policy, RLS, and privilege shape
-- ---------------------------------------------------------------------------

select has_table(
  'public', 'solo_contracts',
  'Solo contracts have a dedicated owner aggregate'
);

select has_table(
  'public', 'solo_evaluations',
  'Solo preliminary evaluations have a dedicated append-only ledger'
);

select has_table(
  'public', 'solo_appeals',
  'Solo appeal filings and decisions have a dedicated append-only ledger'
);

select has_table(
  'app', 'solo_contract_policy_versions',
  'Solo policy versions live in a private append-only registry'
);

select has_table(
  'app', 'solo_contract_runtime',
  'the Solo creation switch is database authoritative'
);

select has_table(
  'app', 'solo_beta_eligibility',
  'Solo beta eligibility is database authoritative'
);

select has_table(
  'app', 'solo_rpc_requests',
  'Solo mutations share an exact-request ledger'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid = 'public.solo_contract_status'::regtype
  ),
  '{scheduled,active,awaiting_evaluation,preliminary_failure,appeal_pending,ready_to_settle,settled,cancelled}',
  'the Solo lifecycle has only the reviewed states'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid = 'public.solo_settlement_mode'::regtype
  ),
  '{test_only}',
  'Step 2A has no live-money settlement mode'
);

select ok(
  (
    select policy.minimum_commitment_minor = 1000
       and policy.maximum_commitment_minor = 5000
       and policy.minimum_duration_days = 1
       and policy.maximum_duration_days = 7
       and policy.evidence_grace = interval '24 hours'
       and policy.appeal_window = interval '7 days'
       and octet_length(policy.policy_digest) = 32
    from app.solo_contract_policy_versions policy
    where policy.version = 'solo-test-v1'
  ),
  'the seeded policy locks the reviewed commitment, duration, and review windows'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_def
    where index_def.schemaname = 'public'
      and index_def.indexname = 'solo_contracts_one_unsettled_owner_idx'
      and index_def.indexdef like '%WHERE (closed_at IS NULL)%'
  ),
  'one unsettled Solo slot per owner is backed by a partial unique index'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'public.solo_contracts'::regclass
      and constraint_def.conname = 'solo_contract_cadence_locked'
      and pg_catalog.pg_get_constraintdef(constraint_def.oid)
        like '%cadence = ANY%daily%cumulative%'
  ),
  'the locked Solo policy fails closed if the shared Social cadence enum expands'
);

select has_function(
  'public', 'create_solo_contract_v1',
  array[
    'uuid',
    'text',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'date',
    'smallint'
  ],
  'owner creation has a versioned RPC'
);

select has_function(
  'public', 'cancel_solo_contract_v1',
  array['uuid', 'uuid'],
  'owner cancellation has a versioned RPC'
);

select has_function(
  'public', 'file_solo_appeal_v1',
  array['uuid', 'uuid', 'uuid', 'text'],
  'owner appeal filing has a versioned RPC'
);

select has_function(
  'public', 'set_solo_contract_runtime_v1',
  array['uuid', 'boolean', 'text'],
  'the runtime switch has a versioned service RPC'
);

select has_function(
  'public', 'set_solo_beta_eligibility_v1',
  array['uuid', 'uuid', 'boolean'],
  'beta eligibility has a versioned service RPC'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'solo_contracts',
        'solo_evaluations',
        'solo_appeals'
      )
      and relation.relrowsecurity
  ),
  3::bigint,
  'RLS is enabled on every owner-readable Solo table'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename in (
        'solo_contracts',
        'solo_evaluations',
        'solo_appeals'
      )
      and policy.cmd = 'SELECT'
      and policy.roles = array['authenticated']::name[]
  ),
  3::bigint,
  'each public Solo table has one authenticated owner-read policy'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('public.solo_contracts'),
        ('public.solo_evaluations'),
        ('public.solo_appeals')
    ) as relation(relation_name)
    cross join (
      values ('insert'), ('update'), ('delete'), ('truncate')
    ) as operation(privilege_name)
    where has_table_privilege(
      'authenticated',
      relation.relation_name,
      operation.privilege_name
    )
  )
  and not exists (
    select 1
    from (
      values
        ('public.solo_contracts'),
        ('public.solo_evaluations'),
        ('public.solo_appeals')
    ) as relation(relation_name)
    where not has_table_privilege(
      'authenticated', relation.relation_name, 'select'
    )
  )
  and not exists (
    select 1
    from (values ('anon'), ('service_role')) as actor(role_name)
    cross join (
      values
        ('public.solo_contracts'),
        ('public.solo_evaluations'),
        ('public.solo_appeals')
    ) as relation(relation_name)
    cross join (
      values ('select'), ('insert'), ('update'), ('delete'), ('truncate')
    ) as operation(privilege_name)
    where has_table_privilege(
      actor.role_name,
      relation.relation_name,
      operation.privilege_name
    )
  ),
  'clients can only select public Solo rows and no service role bypasses RPCs through table grants'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('anon'),
        ('authenticated'),
        ('service_role')
    ) as actor(role_name)
    cross join (
      values
        ('app.solo_contract_policy_versions'),
        ('app.solo_contract_runtime'),
        ('app.solo_beta_eligibility'),
        ('app.solo_rpc_requests')
    ) as relation(relation_name)
    cross join (
      values ('select'), ('insert'), ('update'), ('delete'), ('truncate')
    ) as operation(privilege_name)
    where has_table_privilege(
      actor.role_name,
      relation.relation_name,
      operation.privilege_name
    )
  ),
  'private Solo policy, rollout, eligibility, and idempotency state has no direct API-role grants'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.set_solo_contract_runtime_v1(uuid,boolean,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_solo_contract_runtime_v1(uuid,boolean,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.set_solo_contract_runtime_v1(uuid,boolean,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.set_solo_beta_eligibility_v1(uuid,uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_solo_beta_eligibility_v1(uuid,uuid,boolean)',
    'execute'
  ),
  'owner and service RPC privileges are mutually bounded'
);

select ok(
  not exists (
    select 1
    from (
      values
        (
          'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure,
          'authenticated'::name
        ),
        ('public.cancel_solo_contract_v1(uuid,uuid)'::regprocedure, 'authenticated'::name),
        ('public.file_solo_appeal_v1(uuid,uuid,uuid,text)'::regprocedure, 'authenticated'::name),
        ('public.set_solo_contract_runtime_v1(uuid,boolean,text)'::regprocedure, 'service_role'::name),
        ('public.set_solo_beta_eligibility_v1(uuid,uuid,boolean)'::regprocedure, 'service_role'::name),
        (
          'public.advance_solo_contract_v1(uuid,uuid,public.solo_contract_status)'::regprocedure,
          'service_role'::name
        ),
        (
          'public.record_solo_evaluation_v1(uuid,uuid,public.solo_evaluation_outcome,text,text,bytea)'::regprocedure,
          'service_role'::name
        ),
        (
          'public.decide_solo_appeal_v1(uuid,uuid,public.solo_appeal_decision,text,text,bytea)'::regprocedure,
          'service_role'::name
        ),
        ('public.settle_solo_contract_v1(uuid,uuid)'::regprocedure, 'service_role'::name)
    ) expected(procedure_oid, allowed_role)
    cross join (
      values ('anon'::name), ('authenticated'::name), ('service_role'::name)
    ) actor(role_name)
    where has_function_privilege(
            actor.role_name,
            expected.procedure_oid,
            'execute'
          ) is distinct from (actor.role_name = expected.allowed_role)
  ),
  'every public Solo RPC is executable by exactly its reviewed API role'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('app.assert_solo_write_path()'::regprocedure),
        ('app.validate_solo_contract_insert()'::regprocedure),
        ('app.enforce_solo_contract_lifecycle()'::regprocedure),
        ('app.validate_solo_evaluation_insert()'::regprocedure),
        ('app.validate_solo_appeal_insert()'::regprocedure),
        ('app.solo_payload_digest_v1(jsonb)'::regprocedure),
        ('app.cancel_solo_contract_at_v1(uuid,uuid,timestamptz)'::regprocedure),
        (
          'app.advance_solo_contract_at_v1(uuid,uuid,public.solo_contract_status,timestamptz)'::regprocedure
        ),
        (
          'app.record_solo_evaluation_at_v1(uuid,uuid,public.solo_evaluation_outcome,text,text,bytea,timestamptz)'::regprocedure
        ),
        ('app.file_solo_appeal_at_v1(uuid,uuid,uuid,text,timestamptz)'::regprocedure),
        (
          'app.decide_solo_appeal_at_v1(uuid,uuid,public.solo_appeal_decision,text,text,bytea,timestamptz)'::regprocedure
        ),
        ('app.settle_solo_contract_at_v1(uuid,uuid,timestamptz)'::regprocedure),
        ('app.resolve_solo_contracts_on_account_deletion_v1()'::regprocedure)
    ) internal(procedure_oid)
    cross join (
      values ('anon'::name), ('authenticated'::name), ('service_role'::name)
    ) actor(role_name)
    where has_function_privilege(
      actor.role_name,
      internal.procedure_oid,
      'execute'
    )
  ),
  'no API role can invoke a private Solo helper or deterministic test-time boundary'
);

select ok(
  (
    select bool_and(routine.prosecdef and routine.provolatile = 'v')
    from pg_catalog.pg_proc routine
    where routine.oid in (
      'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure,
      'public.cancel_solo_contract_v1(uuid,uuid)'::regprocedure,
      'public.file_solo_appeal_v1(uuid,uuid,uuid,text)'::regprocedure,
      'public.set_solo_contract_runtime_v1(uuid,boolean,text)'::regprocedure,
      'public.set_solo_beta_eligibility_v1(uuid,uuid,boolean)'::regprocedure,
      'public.advance_solo_contract_v1(uuid,uuid,public.solo_contract_status)'::regprocedure,
      'public.record_solo_evaluation_v1(uuid,uuid,public.solo_evaluation_outcome,text,text,bytea)'::regprocedure,
      'public.decide_solo_appeal_v1(uuid,uuid,public.solo_appeal_decision,text,text,bytea)'::regprocedure,
      'public.settle_solo_contract_v1(uuid,uuid)'::regprocedure
    )
  ),
  'the reviewed Solo mutation surface is volatile and security definer'
);

-- ---------------------------------------------------------------------------
-- Fixtures and creation gate truth table
-- ---------------------------------------------------------------------------

insert into auth.users (id)
values
  ('b3111111-1111-1111-1111-111111111111'),
  ('b3222222-2222-2222-2222-222222222222'),
  ('b3333333-3333-3333-3333-333333333333');

insert into public.profiles (id, handle, display_name, timezone)
values
  (
    'b3111111-1111-1111-1111-111111111111',
    'solodomainalice',
    'Solo Domain Alice',
    'UTC'
  ),
  (
    'b3222222-2222-2222-2222-222222222222',
    'solodomainbob',
    'Solo Domain Bob',
    'UTC'
  ),
  (
    'b3333333-3333-3333-3333-333333333333',
    'solodomaincarol',
    'Solo Domain Carol',
    'UTC'
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000001',
       'solo-test-v1',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '42501',
  null,
  'creation is denied when both the runtime switch and beta eligibility are off'
);

reset role;
set local role service_role;

select is(
  public.set_solo_beta_eligibility_v1(
    'b3000000-0000-0000-0000-000000000002',
    'b3111111-1111-1111-1111-111111111111',
    true
  ),
  true,
  'the service can add an active owner to the database beta allowlist'
);

select is(
  public.set_solo_beta_eligibility_v1(
    'b3000000-0000-0000-0000-000000000002',
    'b3111111-1111-1111-1111-111111111111',
    true
  ),
  true,
  'an exact beta-eligibility retry returns its committed result'
);

select throws_ok(
  $$ select public.set_solo_beta_eligibility_v1(
       'b3000000-0000-0000-0000-000000000002',
       'b3111111-1111-1111-1111-111111111111',
       false
     ) $$,
  '22023',
  null,
  'a beta-eligibility request UUID cannot be reused with another value'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000003',
       'solo-test-v1',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '42501',
  null,
  'beta eligibility cannot bypass a disabled creation switch'
);

reset role;
set local role service_role;

select is(
  public.set_solo_contract_runtime_v1(
    'b3000000-0000-0000-0000-000000000004',
    true,
    'solo-test-v1'
  ),
  true,
  'the service can enable creation for the active reviewed policy'
);

select is(
  public.set_solo_contract_runtime_v1(
    'b3000000-0000-0000-0000-000000000004',
    true,
    'solo-test-v1'
  ),
  true,
  'an exact runtime-switch retry returns its committed result'
);

select throws_ok(
  $$ select public.set_solo_contract_runtime_v1(
       'b3000000-0000-0000-0000-000000000004',
       false,
       'solo-test-v1'
     ) $$,
  '22023',
  null,
  'a runtime-switch request UUID cannot be reused with other settings'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3333333-3333-3333-3333-333333333333","user_metadata":{"solo_beta":true}}',
  true
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000005',
       'solo-test-v1',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '42501',
  null,
  'JWT metadata cannot fabricate database beta eligibility'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b3111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000006',
       'solo-test-v0',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '23001',
  null,
  'creation fails closed when the client policy version is stale'
);

create temporary table t_solo_alice as
select public.create_solo_contract_v1(
  'b3000000-0000-0000-0000-000000000010',
  'solo-test-v1',
  'daily',
  10000,
  1000,
  'UTC',
  '2098-05-01',
  1::smallint
) as id;

select ok(
  (select id is not null from t_solo_alice),
  'an eligible owner can create the minimum commitment and one-day contract'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000011',
       'solo-test-v1',
       'daily',
       10000,
       999,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '22023',
  null,
  'the owner RPC rejects a commitment below $10'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000012',
       'solo-test-v1',
       'daily',
       10000,
       5001,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '22023',
  null,
  'the owner RPC rejects a commitment above $50'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000013',
       'solo-test-v1',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       0::smallint
     ) $$,
  '22023',
  null,
  'the owner RPC rejects a zero-day contract'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000014',
       'solo-test-v1',
       'daily',
       10000,
       1000,
       'UTC',
       '2098-05-01',
       8::smallint
     ) $$,
  '22023',
  null,
  'the owner RPC rejects a contract longer than seven days'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000015',
       'solo-test-v1',
       'cumulative',
       50000,
       2500,
       'UTC',
       '2098-06-01',
       5::smallint
     ) $$,
  '23505',
  null,
  'a distinct request cannot create a second unsettled contract'
);

reset role;
set local role service_role;

select is(
  public.set_solo_beta_eligibility_v1(
    'b3000000-0000-0000-0000-000000000020',
    'b3222222-2222-2222-2222-222222222222',
    true
  ),
  true,
  'a second active owner can be added to the beta allowlist'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3222222-2222-2222-2222-222222222222"}',
  true
);

create temporary table t_solo_bob as
select public.create_solo_contract_v1(
  'b3000000-0000-0000-0000-000000000021',
  'solo-test-v1',
  'cumulative',
  70000,
  5000,
  'America/Chicago',
  '2098-07-01',
  7::smallint
) as id;

select ok(
  (select id is not null from t_solo_bob),
  'an eligible owner can create the maximum commitment and seven-day contract'
);

-- ---------------------------------------------------------------------------
-- Locked terms, owner isolation, and direct write enforcement
-- ---------------------------------------------------------------------------

reset role;

select ok(
  (
    select contract.owner_id = 'b3111111-1111-1111-1111-111111111111'
       and contract.policy_version = 'solo-test-v1'
       and contract.policy_digest = policy.policy_digest
       and contract.metric = 'steps'
       and contract.cadence = 'daily'
       and contract.target_steps = 10000
       and contract.commitment_amount_minor = 1000
       and contract.currency = 'USD'
       and contract.settlement_mode = 'test_only'
       and contract.timezone = 'UTC'
       and contract.duration_days = 1
       and contract.ends_at - contract.starts_at = interval '1 day'
       and contract.evidence_cutoff - contract.ends_at = interval '24 hours'
       and contract.status = 'scheduled'
       and contract.closed_at is null
    from public.solo_contracts contract
    join app.solo_contract_policy_versions policy
      on policy.version = contract.policy_version
    where contract.id = (select id from t_solo_alice)
  ),
  'the minimum contract persists an exact policy digest and complete locked terms'
);

select ok(
  (
    select contract.commitment_amount_minor = 5000
       and contract.duration_days = 7
       and (
         (contract.ends_at at time zone contract.timezone)::date
         - (contract.starts_at at time zone contract.timezone)::date
       ) = 7
       and contract.evidence_cutoff - contract.ends_at = interval '24 hours'
    from public.solo_contracts contract
    where contract.id = (select id from t_solo_bob)
  ),
  'the maximum contract spans seven complete local days'
);

-- PostgreSQL CHECK constraints accept UNKNOWN. Inspect the canonical catalog
-- definitions so nullable terminal and decision metadata cannot reopen that
-- loophole even if ordinary write-path triggers are bypassed by maintenance.
select ok(
  (
    select pg_catalog.regexp_count(
             pg_catalog.pg_get_constraintdef(constraint_def.oid),
             'settlement_disposition IS NOT NULL'
           ) = 2
       and pg_catalog.regexp_count(
             pg_catalog.pg_get_constraintdef(constraint_def.oid),
             'closed_at IS NOT NULL'
           ) = 2
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%cancelled_at < starts_at%'
       and pg_catalog.regexp_count(
             pg_catalog.pg_get_constraintdef(constraint_def.oid),
             'state_changed_at = '
           ) = 2
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'public.solo_contracts'::regclass
      and constraint_def.conname = 'solo_contract_lifecycle_shape'
  ),
  'terminal contract shape makes every nullable closure field explicit'
);

select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%decision_reason_code IS NOT NULL%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%reviewer_version IS NOT NULL%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%decision_digest IS NOT NULL%'
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'public.solo_appeals'::regclass
      and constraint_def.conname = 'solo_appeal_event_shape'
  ),
  'appeal decision shape makes every nullable decision field explicit'
);

select set_config('app.solo_write_path', '', true);

select throws_ok(
  $$ insert into public.solo_contracts (owner_id)
     values ('b3333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'even a privileged direct insert cannot bypass the versioned creation path'
);

select throws_ok(
  format(
    'update public.solo_contracts set status = %L where id = %L',
    'active',
    (select id from t_solo_alice)
  ),
  '42501',
  null,
  'clients and privileged SQL cannot write lifecycle state outside a versioned path'
);

select throws_ok(
  format(
    'update public.solo_contracts set target_steps = 12000 where id = %L',
    (select id from t_solo_alice)
  ),
  '23001',
  null,
  'locked contract terms are immutable after insert'
);

select throws_ok(
  $$ insert into public.solo_evaluations (owner_id)
     values ('b3111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'evaluation rows can only be inserted by the versioned service path'
);

select throws_ok(
  $$ insert into public.solo_appeals (owner_id)
     values ('b3111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'appeal events can only be inserted by a versioned owner or service path'
);

select throws_ok(
  $$ update app.solo_contract_policy_versions
     set appeal_window = interval '8 days'
     where version = 'solo-test-v1' $$,
  '23001',
  null,
  'a published Solo policy version cannot be rewritten'
);

select throws_ok(
  format(
    'delete from public.solo_contracts where id = %L',
    (select id from t_solo_alice)
  ),
  '23001',
  null,
  'Solo contract history cannot be deleted directly'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.solo_contracts),
  1::bigint,
  'an authenticated owner can read exactly their own Solo contract'
);

select is(
  (
    select contract.id
    from public.solo_contracts contract
  ),
  (select id from t_solo_alice),
  'the first owner cannot read the second owner contract'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b3222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (select count(*) from public.solo_contracts),
  1::bigint,
  'the second authenticated owner also sees exactly one contract'
);

select is(
  (
    select contract.id
    from public.solo_contracts contract
  ),
  (select id from t_solo_bob),
  'the second owner cannot read the first owner contract'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b3333333-3333-3333-3333-333333333333"}',
  true
);

select is(
  (select count(*) from public.solo_contracts),
  0::bigint,
  'an owner with no contract cannot enumerate another owner records'
);

-- ---------------------------------------------------------------------------
-- Exact retry recovery remains stronger than mutable rollout gates
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;

select is(
  public.set_solo_beta_eligibility_v1(
    'b3000000-0000-0000-0000-000000000030',
    'b3111111-1111-1111-1111-111111111111',
    false
  ),
  false,
  'the service can revoke future Solo creation eligibility'
);

select is(
  public.set_solo_contract_runtime_v1(
    'b3000000-0000-0000-0000-000000000031',
    false,
    'solo-test-v1'
  ),
  false,
  'the service can disable new Solo creation'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b3111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.create_solo_contract_v1(
    'b3000000-0000-0000-0000-000000000010',
    'solo-test-v1',
    'daily',
    10000,
    1000,
    'UTC',
    '2098-05-01',
    1::smallint
  ),
  (select id from t_solo_alice),
  'an exact committed creation retry recovers after both rollout gates turn off'
);

select throws_ok(
  $$ select public.create_solo_contract_v1(
       'b3000000-0000-0000-0000-000000000010',
       'solo-test-v1',
       'daily',
       11000,
       1000,
       'UTC',
       '2098-05-01',
       1::smallint
     ) $$,
  '22023',
  null,
  'a reused request UUID cannot change locked terms even after gates turn off'
);

reset role;

select is(
  (
    select count(*)
    from public.solo_contracts
    where owner_id in (
      'b3111111-1111-1111-1111-111111111111',
      'b3222222-2222-2222-2222-222222222222'
    )
  ),
  2::bigint,
  'idempotent retries and rejected requests leave exactly one contract per owner'
);

select * from finish();
rollback;
