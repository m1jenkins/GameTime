-- Step 2B Solo fake authorization foundation: exact private schema, immutable
-- typed linkage, deterministic adapter behavior, and a closed privilege surface.

begin;
select no_plan();

set local timezone = 'UTC';

-- ---------------------------------------------------------------------------
-- Exact schema, enum, column, and composite-constraint shape
-- ---------------------------------------------------------------------------

select has_type(
  'app',
  'solo_fake_authorization_scenario',
  'the private fake adapter has a closed scenario enum'
);

select has_type(
  'app',
  'solo_fake_authorization_outcome',
  'the private fake adapter has a closed outcome enum'
);

select has_type(
  'app',
  'solo_authorization_event_kind',
  'the private authorization ledger has a closed event enum'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid =
      'app.solo_fake_authorization_scenario'::regtype
  ),
  '{authorize,refuse,retryable,injected_failure}',
  'the fake adapter exposes only the four reviewed deterministic scenarios'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid =
      'app.solo_fake_authorization_outcome'::regtype
  ),
  '{authorized,refused,retryable}',
  'the fake adapter outcome enum contains no processor state'
);

select is(
  (
    select array_agg(value.enumlabel order by value.enumsortorder)::text
    from pg_catalog.pg_enum value
    where value.enumtypid =
      'app.solo_authorization_event_kind'::regtype
  ),
  '{authorized,cancelled,released,forfeited,waived}',
  'authorization events are limited to one fake opening and logical finality'
);

select has_table(
  'app',
  'solo_authorizations',
  'fake authorizations use one private immutable aggregate'
);

select has_table(
  'app',
  'solo_authorization_events',
  'fake authorization transitions use one private append-only ledger'
);

select is(
  (
    select array_agg(attribute.attname::text order by attribute.attnum)
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = 'app.solo_authorizations'::regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id',
    'contract_id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode',
    'adapter_kind',
    'adapter_version',
    'authorization_digest',
    'create_request_id',
    'create_request_digest',
    'created_at'
  ]::text[],
  'the authorization aggregate has only the reviewed typed fact columns'
);

select is(
  (
    select array_agg(attribute.attname::text order by attribute.attnum)
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = 'app.solo_authorization_events'::regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id',
    'authorization_id',
    'contract_id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode',
    'sequence_number',
    'event_kind',
    'source_operation',
    'event_digest',
    'event_at'
  ]::text[],
  'the event ledger has only copied binding facts and lifecycle metadata'
);

select ok(
  (
    select bool_and(attribute.attnotnull)
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid in (
      'app.solo_authorizations'::regclass,
      'app.solo_authorization_events'::regclass
    )
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  'every fake authorization and event fact is structurally required'
);

create function pg_temp.solo_constraint_columns(
  p_relation regclass,
  p_constraint_name text,
  p_referenced boolean default false
)
returns text[]
language sql
stable
set search_path = ''
as $$
  select array_agg(attribute.attname::text order by key.ordinality)
  from pg_catalog.pg_constraint constraint_def
  cross join lateral pg_catalog.unnest(
    case
      when p_referenced then constraint_def.confkey
      else constraint_def.conkey
    end
  ) with ordinality as key(attnum, ordinality)
  join pg_catalog.pg_attribute attribute
    on attribute.attrelid = case
         when p_referenced then constraint_def.confrelid
         else constraint_def.conrelid
       end
   and attribute.attnum = key.attnum
  where constraint_def.conrelid = p_relation
    and constraint_def.conname = p_constraint_name;
$$;

select is(
  pg_temp.solo_constraint_columns(
    'public.solo_contracts',
    'solo_contracts_authorization_binding_key'
  ),
  array[
    'id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode'
  ]::text[],
  'the contract publishes exactly the immutable authorization binding key'
);

select is(
  pg_temp.solo_constraint_columns(
    'app.solo_authorizations',
    'solo_authorization_contract_fkey'
  ),
  array[
    'contract_id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode'
  ]::text[],
  'the authorization child key copies every immutable contract binding fact'
);

select is(
  pg_temp.solo_constraint_columns(
    'app.solo_authorizations',
    'solo_authorization_contract_fkey',
    true
  ),
  array[
    'id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode'
  ]::text[],
  'the authorization foreign key maps every copied fact to its contract peer'
);

select ok(
  (
    select constraint_def.contype = 'f'
       and constraint_def.confdeltype = 'r'
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'app.solo_authorizations'::regclass
      and constraint_def.conname = 'solo_authorization_contract_fkey'
  ),
  'authorization linkage restricts contract deletion'
);

select is(
  pg_temp.solo_constraint_columns(
    'app.solo_authorization_events',
    'solo_authorization_event_parent_fkey'
  ),
  array[
    'authorization_id',
    'contract_id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode'
  ]::text[],
  'each event copies the complete immutable authorization identity'
);

select is(
  pg_temp.solo_constraint_columns(
    'app.solo_authorization_events',
    'solo_authorization_event_parent_fkey',
    true
  ),
  array[
    'id',
    'contract_id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'commitment_amount_minor',
    'currency',
    'settlement_mode'
  ]::text[],
  'the event foreign key maps every copied fact to its authorization peer'
);

select ok(
  (
    select constraint_def.contype = 'f'
       and constraint_def.confdeltype = 'r'
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid =
      'app.solo_authorization_events'::regclass
      and constraint_def.conname =
        'solo_authorization_event_parent_fkey'
  ),
  'event linkage restricts authorization deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'app.solo_authorizations'::regclass
      and constraint_def.contype = 'u'
      and pg_temp.solo_constraint_columns(
            constraint_def.conrelid,
            constraint_def.conname
          ) = array['contract_id']::text[]
  ),
  'one contract can have at most one fake authorization'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid =
      'app.solo_authorization_events'::regclass
      and constraint_def.contype = 'u'
      and pg_temp.solo_constraint_columns(
            constraint_def.conrelid,
            constraint_def.conname
          ) = array['authorization_id', 'sequence_number']::text[]
  ),
  'one authorization can have only one event at each lifecycle sequence'
);

select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%processor_neutral_fake%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%local-fake-v1%'
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid = 'app.solo_authorizations'::regclass
      and constraint_def.conname = 'solo_authorization_adapter_fixed'
  ),
  'the private aggregate structurally fixes the only local fake adapter'
);

select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%sequence_number = 1%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%sequence_number = 2%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%create_solo_contract_with_fake_authorization_v2%'
       and pg_catalog.pg_get_constraintdef(constraint_def.oid)
             like '%settle_solo_contract_v1%'
    from pg_catalog.pg_constraint constraint_def
    where constraint_def.conrelid =
      'app.solo_authorization_events'::regclass
      and constraint_def.conname = 'solo_authorization_event_shape'
  ),
  'the event CHECK exposes only the reviewed first and terminal transitions'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger trigger_def
    where trigger_def.tgrelid = 'app.solo_authorizations'::regclass
      and trigger_def.tgname = 'solo_authorizations_forbid_mutation'
      and not trigger_def.tgisinternal
  )
  and exists (
    select 1
    from pg_catalog.pg_trigger trigger_def
    where trigger_def.tgrelid =
      'app.solo_authorization_events'::regclass
      and trigger_def.tgname =
        'solo_authorization_events_forbid_mutation'
      and not trigger_def.tgisinternal
  ),
  'both private relations have hard append-only enforcement'
);

-- ---------------------------------------------------------------------------
-- RLS, no policies, and complete PostgreSQL 17 privilege matrices
-- ---------------------------------------------------------------------------

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    where relation.oid in (
      'app.solo_authorizations'::regclass,
      'app.solo_authorization_events'::regclass
    )
      and relation.relrowsecurity
  ),
  2::bigint,
  'RLS is enabled on both private fake authorization tables'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'app'
      and policy.tablename in (
        'solo_authorizations',
        'solo_authorization_events'
      )
  ),
  0::bigint,
  'private fake authorization tables expose no row policy'
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
        ('app.solo_authorizations'),
        ('app.solo_authorization_events')
    ) as relation(relation_name)
    cross join (
      values
        ('select'),
        ('insert'),
        ('update'),
        ('delete'),
        ('truncate'),
        ('references'),
        ('trigger'),
        ('maintain')
    ) as operation(privilege_name)
    where pg_catalog.has_table_privilege(
      actor.role_name,
      relation.relation_name,
      operation.privilege_name
    )
  ),
  'all eight PostgreSQL 17 table privileges are denied to every API role'
);

-- PUBLIC is ACL grantee 0 rather than a pg_authid role. Its branch therefore
-- inspects effective table/column ACLs directly; named API-role branches use
-- has_column_privilege across the same complete column/verb cross-product.
select ok(
  not exists (
    select 1
    from (
      values
        ('public'),
        ('anon'),
        ('authenticated'),
        ('service_role')
    ) as actor(role_name)
    cross join (
      values
        ('app.solo_authorizations'::regclass),
        ('app.solo_authorization_events'::regclass)
    ) as target(relation_oid)
    join pg_catalog.pg_class relation
      on relation.oid = target.relation_oid
    cross join lateral (
      select attribute.attnum, attribute.attname
      from pg_catalog.pg_attribute attribute
      where attribute.attrelid = target.relation_oid
        and attribute.attnum > 0
        and not attribute.attisdropped
    ) as column_def
    cross join (
      values
        ('select'),
        ('insert'),
        ('update'),
        ('references')
    ) as operation(privilege_name)
    where case
      when actor.role_name = 'public' then
        exists (
          select 1
          from pg_catalog.aclexplode(
            coalesce(
              relation.relacl,
              pg_catalog.acldefault('r', relation.relowner)
            )
          ) table_acl
          where table_acl.grantee = 0
            and pg_catalog.lower(table_acl.privilege_type) =
                  operation.privilege_name
        )
        or exists (
          select 1
          from pg_catalog.aclexplode(
            (
              select attribute.attacl
              from pg_catalog.pg_attribute attribute
              where attribute.attrelid = target.relation_oid
                and attribute.attnum = column_def.attnum
            )
          ) column_acl
          where column_acl.grantee = 0
            and pg_catalog.lower(column_acl.privilege_type) =
                  operation.privilege_name
        )
      else pg_catalog.has_column_privilege(
        actor.role_name,
        target.relation_oid,
        column_def.attnum,
        operation.privilege_name
      )
    end
  ),
  'PUBLIC and every API role lack all four privileges on every private column'
);

-- The same grantee-0 handling is required for PUBLIC type USAGE.
select ok(
  not exists (
    select 1
    from (
      values
        ('public'),
        ('anon'),
        ('authenticated'),
        ('service_role')
    ) as actor(role_name)
    cross join (
      values
        ('app.solo_fake_authorization_scenario'::regtype),
        ('app.solo_fake_authorization_outcome'::regtype),
        ('app.solo_authorization_event_kind'::regtype)
    ) as target(type_oid)
    join pg_catalog.pg_type type_def
      on type_def.oid = target.type_oid
    where case
      when actor.role_name = 'public' then
        exists (
          select 1
          from pg_catalog.aclexplode(
            coalesce(
              type_def.typacl,
              pg_catalog.acldefault('T', type_def.typowner)
            )
          ) type_acl
          where type_acl.grantee = 0
            and type_acl.privilege_type = 'USAGE'
        )
      else pg_catalog.has_type_privilege(
        actor.role_name,
        target.type_oid,
        'USAGE'
      )
    end
  ),
  'PUBLIC and every API role lack USAGE on all private Step 2B enum types'
);

select has_function(
  'public',
  'create_solo_contract_with_fake_authorization_v2',
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
  'atomic owner creation has a distinct versioned public RPC'
);

select has_function(
  'app',
  'solo_authorization_fact_digest_v1',
  array[
    'uuid',
    'uuid',
    'text',
    'bytea',
    'integer',
    'text',
    'public.solo_settlement_mode',
    'text',
    'text'
  ],
  'authorization facts have one private canonical digest helper'
);

select has_function(
  'app',
  'solo_authorization_event_digest_v1',
  array[
    'uuid',
    'uuid',
    'uuid',
    'text',
    'bytea',
    'integer',
    'text',
    'public.solo_settlement_mode',
    'smallint',
    'app.solo_authorization_event_kind',
    'text',
    'timestamp with time zone'
  ],
  'authorization events have one private canonical digest helper'
);

select has_function(
  'app',
  'run_solo_fake_authorization_v1',
  array[
    'uuid',
    'uuid',
    'text',
    'bytea',
    'integer',
    'text',
    'public.solo_settlement_mode',
    'app.solo_fake_authorization_scenario'
  ],
  'the deterministic typed fake adapter is private'
);

select has_function(
  'app',
  'assert_solo_authorization_write_path',
  array[]::text[],
  'authorization inserts have a private write-path guard'
);

select has_function(
  'app',
  'validate_solo_authorization_insert_v1',
  array[]::text[],
  'authorization linkage has a private validation trigger'
);

select has_function(
  'app',
  'validate_solo_authorization_event_insert_v1',
  array[]::text[],
  'authorization transitions have a private validation trigger'
);

select has_function(
  'app',
  'append_solo_authorization_resolution_v1',
  array[]::text[],
  'contract finality has one private authorization-event bridge'
);

select has_function(
  'app',
  'create_solo_contract_with_fake_authorization_at_v2',
  array[
    'uuid',
    'text',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'date',
    'smallint',
    'app.solo_fake_authorization_scenario'
  ],
  'deterministic test scenarios remain behind an ungranted private helper'
);

select ok(
  not exists (
    select 1
    from (
      values (
        'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure,
        'authenticated'::name
      )
    ) expected(procedure_oid, allowed_role)
    cross join (
      values
        ('anon'::name),
        ('authenticated'::name),
        ('service_role'::name)
    ) actor(role_name)
    where pg_catalog.has_function_privilege(
            actor.role_name,
            expected.procedure_oid,
            'execute'
          ) is distinct from (actor.role_name = expected.allowed_role)
  ),
  'the public v2 RPC is executable only by authenticated owners'
);

select ok(
  not exists (
    select 1
    from (
      values
        (
          'app.solo_authorization_fact_digest_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,text,text)'::regprocedure
        ),
        (
          'app.solo_authorization_event_digest_v1(uuid,uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,smallint,app.solo_authorization_event_kind,text,timestamptz)'::regprocedure
        ),
        (
          'app.run_solo_fake_authorization_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,app.solo_fake_authorization_scenario)'::regprocedure
        ),
        ('app.assert_solo_authorization_write_path()'::regprocedure),
        ('app.validate_solo_authorization_insert_v1()'::regprocedure),
        (
          'app.validate_solo_authorization_event_insert_v1()'::regprocedure
        ),
        ('app.append_solo_authorization_resolution_v1()'::regprocedure),
        (
          'app.create_solo_contract_with_fake_authorization_at_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint,app.solo_fake_authorization_scenario)'::regprocedure
        )
    ) private_helper(procedure_oid)
    cross join (
      values
        ('anon'::name),
        ('authenticated'::name),
        ('service_role'::name)
    ) actor(role_name)
    where pg_catalog.has_function_privilege(
      actor.role_name,
      private_helper.procedure_oid,
      'execute'
    )
  ),
  'no API role can execute any private digest, adapter, trigger, or test helper'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('app.validate_solo_authorization_insert_v1()'::regprocedure),
        (
          'app.validate_solo_authorization_event_insert_v1()'::regprocedure
        ),
        ('app.append_solo_authorization_resolution_v1()'::regprocedure),
        (
          'app.create_solo_contract_with_fake_authorization_at_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint,app.solo_fake_authorization_scenario)'::regprocedure
        )
    ) expected(procedure_oid)
    join pg_catalog.pg_proc routine
      on routine.oid = expected.procedure_oid
    where routine.proowner <> 'postgres'::regrole
       or not routine.prosecdef
       or routine.provolatile <> 'v'
       or routine.proconfig is distinct from
            array['search_path=""']::text[]
  ),
  'every private Step 2B definer is postgres-owned, volatile, and exactly search-path closed'
);

select ok(
  (
    select routine.proowner = 'postgres'::regrole
       and routine.prosecdef
       and routine.provolatile = 'v'
       and routine.proconfig is not distinct from
            array['search_path=""']::text[]
    from pg_catalog.pg_proc routine
    where routine.oid =
      'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
  ),
  'the public v2 wrapper is postgres-owned, volatile, security definer, and exactly search-path closed'
);

select ok(
  (
    select bool_and(
      routine.provolatile = 'i'
      and routine.proisstrict
      and not routine.prosecdef
    )
    from pg_catalog.pg_proc routine
    where routine.oid in (
      'app.solo_authorization_fact_digest_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,text,text)'::regprocedure,
      'app.solo_authorization_event_digest_v1(uuid,uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,smallint,app.solo_authorization_event_kind,text,timestamptz)'::regprocedure,
      'app.run_solo_fake_authorization_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,app.solo_fake_authorization_scenario)'::regprocedure
    )
  ),
  'typed digests and the fake adapter are strict immutable invoker functions'
);

-- ---------------------------------------------------------------------------
-- No provider-shaped storage, raw payload input, or explicit logging surface
-- ---------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid in (
      'app.solo_authorizations'::regclass,
      'app.solo_authorization_events'::regclass
    )
      and attribute.attnum > 0
      and not attribute.attisdropped
      and attribute.attname ~* (
        'provider|secret|credential|password|token|payment|instrument|card|'
        || 'customer|mandate|webhook|capture|charge|transfer|payout|'
        || '(^|_)raw($|_)|payload'
      )
  ),
  'no private authorization column can store a provider secret or instrument'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid in (
      'app.solo_authorizations'::regclass,
      'app.solo_authorization_events'::regclass
    )
      and attribute.attnum > 0
      and not attribute.attisdropped
      and attribute.atttypid in (
        'json'::regtype,
        'jsonb'::regtype
      )
  ),
  'private authorization tables have no arbitrary JSON payload column'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    cross join lateral pg_catalog.unnest(
      coalesce(routine.proargnames, array[]::text[])
    ) argument(argument_name)
    where routine.oid in (
      'app.solo_authorization_fact_digest_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,text,text)'::regprocedure,
      'app.solo_authorization_event_digest_v1(uuid,uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,smallint,app.solo_authorization_event_kind,text,timestamptz)'::regprocedure,
      'app.run_solo_fake_authorization_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,app.solo_fake_authorization_scenario)'::regprocedure,
      'app.assert_solo_authorization_write_path()'::regprocedure,
      'app.validate_solo_authorization_insert_v1()'::regprocedure,
      'app.validate_solo_authorization_event_insert_v1()'::regprocedure,
      'app.append_solo_authorization_resolution_v1()'::regprocedure,
      'app.create_solo_contract_with_fake_authorization_at_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint,app.solo_fake_authorization_scenario)'::regprocedure,
      'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
    )
      and argument.argument_name ~* (
        'provider|secret|credential|password|token|payment|instrument|card|'
        || 'customer|mandate|webhook|capture|charge|transfer|payout|'
        || '(^|_)raw($|_)|payload'
      )
  ),
  'new function signatures accept no provider, instrument, or raw payload argument'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    where routine.oid in (
      'app.solo_authorization_fact_digest_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,text,text)'::regprocedure,
      'app.solo_authorization_event_digest_v1(uuid,uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,smallint,app.solo_authorization_event_kind,text,timestamptz)'::regprocedure,
      'app.run_solo_fake_authorization_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,app.solo_fake_authorization_scenario)'::regprocedure,
      'app.create_solo_contract_with_fake_authorization_at_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint,app.solo_fake_authorization_scenario)'::regprocedure,
      'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
    )
      and pg_catalog.pg_get_function_arguments(routine.oid)
            ~* '(^|, )[a-z0-9_]+ (json|jsonb)(,|$)'
  ),
  'new callable boundaries accept typed scalar facts rather than JSON input'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    where routine.oid in (
      'app.solo_authorization_fact_digest_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,text,text)'::regprocedure,
      'app.solo_authorization_event_digest_v1(uuid,uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,smallint,app.solo_authorization_event_kind,text,timestamptz)'::regprocedure,
      'app.run_solo_fake_authorization_v1(uuid,uuid,text,bytea,integer,text,public.solo_settlement_mode,app.solo_fake_authorization_scenario)'::regprocedure,
      'app.assert_solo_authorization_write_path()'::regprocedure,
      'app.validate_solo_authorization_insert_v1()'::regprocedure,
      'app.validate_solo_authorization_event_insert_v1()'::regprocedure,
      'app.append_solo_authorization_resolution_v1()'::regprocedure,
      'app.create_solo_contract_with_fake_authorization_at_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint,app.solo_fake_authorization_scenario)'::regprocedure,
      'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
    )
      and (
        routine.prosrc ~* 'raise[[:space:]]+(log|debug|info|notice|warning)'
        or routine.prosrc ~* 'pg_notify[[:space:]]*\('
      )
  ),
  'new authorization functions contain no explicit database logging statement'
);

-- ---------------------------------------------------------------------------
-- Typed fake-adapter purity and denied direct writes
-- ---------------------------------------------------------------------------

select is(
  app.run_solo_fake_authorization_v1(
    'd6000000-0000-0000-0000-000000000001',
    'd6000000-0000-0000-0000-000000000002',
    'solo-test-v1',
    pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
    1000,
    'USD',
    'test_only',
    'authorize'
  ),
  'authorized'::app.solo_fake_authorization_outcome,
  'the typed local adapter deterministically authorizes'
);

select is(
  app.run_solo_fake_authorization_v1(
    'd6000000-0000-0000-0000-000000000001',
    'd6000000-0000-0000-0000-000000000002',
    'solo-test-v1',
    pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
    1000,
    'USD',
    'test_only',
    'refuse'
  ),
  'refused'::app.solo_fake_authorization_outcome,
  'the typed local adapter deterministically refuses'
);

select is(
  app.run_solo_fake_authorization_v1(
    'd6000000-0000-0000-0000-000000000001',
    'd6000000-0000-0000-0000-000000000002',
    'solo-test-v1',
    pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
    1000,
    'USD',
    'test_only',
    'retryable'
  ),
  'retryable'::app.solo_fake_authorization_outcome,
  'the typed local adapter deterministically requests a retry'
);

select throws_ok(
  $$ select app.run_solo_fake_authorization_v1(
       'd6000000-0000-0000-0000-000000000001',
       'd6000000-0000-0000-0000-000000000002',
       'solo-test-v1',
       pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
       1000,
       'USD',
       'test_only',
       'injected_failure'
     ) $$,
  'P2B02',
  null,
  'the typed local adapter deterministically injects a non-echoing failure'
);

select is(
  (select count(*) from app.solo_authorizations)
  + (select count(*) from app.solo_authorization_events)
  + (
    select count(*)
    from app.solo_rpc_requests
    where operation = 'create_solo_contract_with_fake_authorization_v2'
  ),
  0::bigint,
  'pure adapter outcomes store no authorization, event, or request record'
);

select pg_catalog.set_config('app.solo_write_path', '', true);

select throws_ok(
  $$ insert into app.solo_authorizations (id)
     values ('d6000000-0000-0000-0000-000000000010') $$,
  '42501',
  null,
  'even privileged SQL cannot insert an authorization outside v2'
);

select throws_ok(
  $$ insert into app.solo_authorization_events (id)
     values ('d6000000-0000-0000-0000-000000000011') $$,
  '42501',
  null,
  'even privileged SQL cannot append an event outside an approved transition'
);

set local role authenticated;

select throws_ok(
  $$ insert into app.solo_authorizations (id)
     values ('d6000000-0000-0000-0000-000000000012') $$,
  '42501',
  null,
  'authenticated clients have no direct authorization write grant'
);

select throws_ok(
  $$ select app.run_solo_fake_authorization_v1(
       'd6000000-0000-0000-0000-000000000001',
       'd6000000-0000-0000-0000-000000000002',
       'solo-test-v1',
       pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
       1000,
       'USD',
       'test_only',
       'authorize'
     ) $$,
  '42501',
  null,
  'authenticated clients cannot invoke the private scenario adapter'
);

reset role;
set local role service_role;

select throws_ok(
  $$ insert into app.solo_authorization_events (id)
     values ('d6000000-0000-0000-0000-000000000013') $$,
  '42501',
  null,
  'service_role has no direct event write grant'
);

reset role;

-- ---------------------------------------------------------------------------
-- Real v1/v2 fixtures prove contract-only compatibility and immutable linkage
-- ---------------------------------------------------------------------------

insert into auth.users (id)
values
  ('d6111111-1111-1111-1111-111111111111'),
  ('d6222222-2222-2222-2222-222222222222');

insert into public.profiles (id, handle, display_name, timezone)
values
  (
    'd6111111-1111-1111-1111-111111111111',
    'solo_fake_domain_v1',
    'Solo Fake Domain V1',
    'UTC'
  ),
  (
    'd6222222-2222-2222-2222-222222222222',
    'solo_fake_domain_v2',
    'Solo Fake Domain V2',
    'UTC'
  );

set local role service_role;

select is(
  public.set_solo_contract_runtime_v1(
    'd6000000-0000-0000-0000-000000000020',
    true,
    'solo-test-v1'
  ),
  true,
  'the local fixture explicitly enables the otherwise-disabled Solo runtime'
);

select is(
  public.set_solo_beta_eligibility_v1(
    'd6000000-0000-0000-0000-000000000021',
    'd6111111-1111-1111-1111-111111111111',
    true
  ),
  true,
  'the contract-only v1 fixture is explicitly beta eligible'
);

select is(
  public.set_solo_beta_eligibility_v1(
    'd6000000-0000-0000-0000-000000000022',
    'd6222222-2222-2222-2222-222222222222',
    true
  ),
  true,
  'the authorization-backed v2 fixture is explicitly beta eligible'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d6111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_solo_fake_v1_contract as
select public.create_solo_contract_v1(
  'd6000000-0000-0000-0000-000000000030',
  'solo-test-v1',
  'daily',
  10000,
  1000,
  'UTC',
  '2098-11-01',
  1::smallint
) as contract_id;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d6222222-2222-2222-2222-222222222222"}',
  true
);

create temporary table t_solo_fake_v2_result as
select public.create_solo_contract_with_fake_authorization_v2(
  'd6000000-0000-0000-0000-000000000031',
  'solo-test-v1',
  'cumulative',
  70000,
  5000,
  'UTC',
  '2098-12-01',
  7::smallint
) as result;

reset role;

select is(
  (
    select pg_catalog.pg_get_function_result(routine.oid)
    from pg_catalog.pg_proc routine
    where routine.oid =
      'public.create_solo_contract_v1(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
  ),
  'uuid',
  'create_solo_contract_v1 still returns only a contract UUID'
);

select is(
  (
    select pg_catalog.pg_get_function_result(routine.oid)
    from pg_catalog.pg_proc routine
    where routine.oid =
      'public.create_solo_contract_with_fake_authorization_v2(uuid,text,public.contest_cadence,integer,integer,text,date,smallint)'::regprocedure
  ),
  'jsonb',
  'the different atomic contract is explicit in the v2 JSON result'
);

select is(
  (
    select count(*)
    from app.solo_authorizations authorization_row
    where authorization_row.contract_id = (
      select contract_id
      from t_solo_fake_v1_contract
    )
  ),
  0::bigint,
  'a v1 creation remains deliberately contract-only'
);

select is(
  (
    select array_agg(result_key order by result_key)
    from app.solo_rpc_requests request
    cross join lateral pg_catalog.jsonb_object_keys(request.result)
      result_key
    where request.operation = 'create_solo_contract_v1'
      and request.request_scope =
        'd6111111-1111-1111-1111-111111111111'
      and request.request_id =
        'd6000000-0000-0000-0000-000000000030'
  ),
  array['contract_id']::text[],
  'the v1 exact-request result has no authorization field'
);

select is(
  (
    select array_agg(result_key order by result_key)
    from t_solo_fake_v2_result fixture
    cross join lateral pg_catalog.jsonb_object_keys(fixture.result)
      result_key
  ),
  array[
    'adapter_version',
    'authorization_id',
    'contract_id',
    'outcome'
  ]::text[],
  'the v2 result contains only safe fake-adapter and internal aggregate facts'
);

select ok(
  (
    select authorization_row.contract_id =
             (fixture.result ->> 'contract_id')::uuid
       and authorization_row.id =
             (fixture.result ->> 'authorization_id')::uuid
       and authorization_row.owner_id = contract.owner_id
       and authorization_row.policy_version = contract.policy_version
       and authorization_row.policy_digest = contract.policy_digest
       and authorization_row.commitment_amount_minor =
             contract.commitment_amount_minor
       and authorization_row.currency = contract.currency
       and authorization_row.settlement_mode = contract.settlement_mode
       and authorization_row.adapter_kind = 'processor_neutral_fake'
       and authorization_row.adapter_version = 'local-fake-v1'
       and authorization_row.authorization_digest =
             app.solo_authorization_fact_digest_v1(
               contract.id,
               contract.owner_id,
               contract.policy_version,
               contract.policy_digest,
               contract.commitment_amount_minor,
               contract.currency,
               contract.settlement_mode,
               authorization_row.adapter_kind,
               authorization_row.adapter_version
             )
       and authorization_row.create_request_digest = request.payload_hash
    from t_solo_fake_v2_result fixture
    join app.solo_authorizations authorization_row
      on authorization_row.id =
        (fixture.result ->> 'authorization_id')::uuid
    join public.solo_contracts contract
      on contract.id = authorization_row.contract_id
    join app.solo_rpc_requests request
      on request.operation =
        'create_solo_contract_with_fake_authorization_v2'
     and request.request_scope = authorization_row.owner_id
     and request.request_id = authorization_row.create_request_id
  ),
  'the committed authorization is fully bound and both digests recompute'
);

select ok(
  (
    select event.sequence_number = 1
       and event.event_kind = 'authorized'
       and event.source_operation =
             'create_solo_contract_with_fake_authorization_v2'
       and event.contract_id = authorization_row.contract_id
       and event.owner_id = authorization_row.owner_id
       and event.policy_version = authorization_row.policy_version
       and event.policy_digest = authorization_row.policy_digest
       and event.commitment_amount_minor =
             authorization_row.commitment_amount_minor
       and event.currency = authorization_row.currency
       and event.settlement_mode = authorization_row.settlement_mode
       and event.event_at = authorization_row.created_at
       and event.event_digest =
             app.solo_authorization_event_digest_v1(
               event.authorization_id,
               event.contract_id,
               event.owner_id,
               event.policy_version,
               event.policy_digest,
               event.commitment_amount_minor,
               event.currency,
               event.settlement_mode,
               event.sequence_number,
               event.event_kind,
               event.source_operation,
               event.event_at
             )
    from t_solo_fake_v2_result fixture
    join app.solo_authorizations authorization_row
      on authorization_row.id =
        (fixture.result ->> 'authorization_id')::uuid
    join app.solo_authorization_events event
      on event.authorization_id = authorization_row.id
  ),
  'the first append-only event copies and digests every authorization fact'
);

select pg_catalog.set_config(
  'app.solo_write_path',
  'create_with_fake_v2',
  true
);

create function pg_temp.insert_authorization_mismatch(
  p_id uuid,
  p_mismatch text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_authorization app.solo_authorizations;
begin
  select authorization_row.* into strict v_authorization
  from app.solo_authorizations authorization_row
  where authorization_row.id = (
    select (fixture.result ->> 'authorization_id')::uuid
    from pg_temp.t_solo_fake_v2_result fixture
  );

  insert into app.solo_authorizations (
    id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    adapter_kind,
    adapter_version,
    authorization_digest,
    create_request_id,
    create_request_digest,
    created_at
  )
  values (
    p_id,
    case p_mismatch
      when 'contract' then (
        select fixture.contract_id
        from pg_temp.t_solo_fake_v1_contract fixture
      )
      else v_authorization.contract_id
    end,
    case p_mismatch
      when 'owner' then
        'd6111111-1111-1111-1111-111111111111'::uuid
      else v_authorization.owner_id
    end,
    case p_mismatch
      when 'policy_version' then 'solo-test-v1-mismatch'
      else v_authorization.policy_version
    end,
    case p_mismatch
      when 'policy_digest' then
        pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex')
      else v_authorization.policy_digest
    end,
    case p_mismatch
      when 'amount' then 4000
      else v_authorization.commitment_amount_minor
    end,
    case p_mismatch
      when 'currency' then 'EUR'
      else v_authorization.currency
    end,
    v_authorization.settlement_mode,
    v_authorization.adapter_kind,
    v_authorization.adapter_version,
    v_authorization.authorization_digest,
    p_id,
    v_authorization.create_request_digest,
    v_authorization.created_at
  );
end;
$$;

create function pg_temp.insert_authorization_event_mismatch(
  p_id uuid,
  p_mismatch text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_event app.solo_authorization_events;
begin
  select event.* into strict v_event
  from app.solo_authorization_events event
  where event.authorization_id = (
    select (fixture.result ->> 'authorization_id')::uuid
    from pg_temp.t_solo_fake_v2_result fixture
  );

  insert into app.solo_authorization_events (
    id,
    authorization_id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    sequence_number,
    event_kind,
    source_operation,
    event_digest,
    event_at
  )
  values (
    p_id,
    v_event.authorization_id,
    case p_mismatch
      when 'contract' then (
        select fixture.contract_id
        from pg_temp.t_solo_fake_v1_contract fixture
      )
      else v_event.contract_id
    end,
    case p_mismatch
      when 'owner' then
        'd6111111-1111-1111-1111-111111111111'::uuid
      else v_event.owner_id
    end,
    case p_mismatch
      when 'policy_version' then 'solo-test-v1-mismatch'
      else v_event.policy_version
    end,
    case p_mismatch
      when 'policy_digest' then
        pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex')
      else v_event.policy_digest
    end,
    case p_mismatch
      when 'amount' then 4000
      else v_event.commitment_amount_minor
    end,
    case p_mismatch
      when 'currency' then 'EUR'
      else v_event.currency
    end,
    v_event.settlement_mode,
    v_event.sequence_number,
    v_event.event_kind,
    v_event.source_operation,
    v_event.event_digest,
    v_event.event_at
  );
end;
$$;

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000040',
       'owner'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects an owner mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000041',
       'contract'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects a contract mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000042',
       'policy_version'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects a policy-version mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000043',
       'policy_digest'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects a policy-digest mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000044',
       'amount'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects an amount mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_mismatch(
       'd6000000-0000-0000-0000-000000000045',
       'currency'
     ) $$,
  '23001',
  null,
  'the authorization validator rejects a currency mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000046',
       'owner'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied owner mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000047',
       'contract'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied contract mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000048',
       'policy_version'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied policy-version mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000049',
       'policy_digest'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied policy-digest mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000050',
       'amount'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied amount mismatch'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_event_mismatch(
       'd6000000-0000-0000-0000-000000000051',
       'currency'
     ) $$,
  '23001',
  null,
  'the event validator rejects a copied currency mismatch'
);

insert into app.solo_authorizations (
  id,
  contract_id,
  owner_id,
  policy_version,
  policy_digest,
  commitment_amount_minor,
  currency,
  settlement_mode,
  adapter_kind,
  adapter_version,
  authorization_digest,
  create_request_id,
  create_request_digest,
  created_at
)
select
  'd6000000-0000-0000-0000-000000000060',
  contract.id,
  contract.owner_id,
  contract.policy_version,
  contract.policy_digest,
  contract.commitment_amount_minor,
  contract.currency,
  contract.settlement_mode,
  'processor_neutral_fake',
  'local-fake-v1',
  app.solo_authorization_fact_digest_v1(
    contract.id,
    contract.owner_id,
    contract.policy_version,
    contract.policy_digest,
    contract.commitment_amount_minor,
    contract.currency,
    contract.settlement_mode,
    'processor_neutral_fake',
    'local-fake-v1'
  ),
  'd6000000-0000-0000-0000-000000000061',
  pg_catalog.decode(pg_catalog.repeat('cd', 32), 'hex'),
  contract.created_at
from public.solo_contracts contract
where contract.id = (
  select fixture.contract_id
  from t_solo_fake_v1_contract fixture
);

create function pg_temp.insert_authorization_transition(
  p_id uuid,
  p_authorization_id uuid,
  p_sequence_number smallint,
  p_event_kind app.solo_authorization_event_kind,
  p_source_operation text,
  p_event_at timestamptz default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_authorization app.solo_authorizations;
  v_event_at timestamptz;
begin
  select authorization_row.* into strict v_authorization
  from app.solo_authorizations authorization_row
  where authorization_row.id = p_authorization_id;

  v_event_at := case
    when p_event_at is not null then p_event_at
    when p_sequence_number = 1 then v_authorization.created_at
    else clock_timestamp()
  end;

  insert into app.solo_authorization_events (
    id,
    authorization_id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    sequence_number,
    event_kind,
    source_operation,
    event_digest,
    event_at
  )
  values (
    p_id,
    v_authorization.id,
    v_authorization.contract_id,
    v_authorization.owner_id,
    v_authorization.policy_version,
    v_authorization.policy_digest,
    v_authorization.commitment_amount_minor,
    v_authorization.currency,
    v_authorization.settlement_mode,
    p_sequence_number,
    p_event_kind,
    p_source_operation,
    app.solo_authorization_event_digest_v1(
      v_authorization.id,
      v_authorization.contract_id,
      v_authorization.owner_id,
      v_authorization.policy_version,
      v_authorization.policy_digest,
      v_authorization.commitment_amount_minor,
      v_authorization.currency,
      v_authorization.settlement_mode,
      p_sequence_number,
      p_event_kind,
      p_source_operation,
      v_event_at
    ),
    v_event_at
  );
end;
$$;

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000062',
       'd6000000-0000-0000-0000-000000000060',
       2::smallint,
       'cancelled',
       'cancel_solo_contract_v1'
     ) $$,
  '23001',
  null,
  'a terminal transition is forbidden before the initial authorization event'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000063',
       (
         select (fixture.result ->> 'authorization_id')::uuid
         from t_solo_fake_v2_result fixture
       ),
       1::smallint,
       'authorized',
       'create_solo_contract_with_fake_authorization_v2'
     ) $$,
  '23001',
  null,
  'a second initial authorization transition is forbidden'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000064',
       (
         select (fixture.result ->> 'authorization_id')::uuid
         from t_solo_fake_v2_result fixture
       ),
       2::smallint,
       'cancelled',
       'cancel_solo_contract_v1'
     ) $$,
  '23001',
  null,
  'an authorization cannot resolve before contract finality'
);

set local session_replication_role = replica;

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000065',
       (
         select (fixture.result ->> 'authorization_id')::uuid
         from t_solo_fake_v2_result fixture
       ),
       2::smallint,
       'released',
       'cancel_solo_contract_v1'
     ) $$,
  '23514',
  null,
  'a cancellation source cannot claim a settlement terminal kind'
);

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000066',
       (
         select (fixture.result ->> 'authorization_id')::uuid
         from t_solo_fake_v2_result fixture
       ),
       2::smallint,
       'cancelled',
       'settle_solo_contract_v1'
     ) $$,
  '23514',
  null,
  'a cancellation terminal kind cannot claim the settlement source'
);

set local session_replication_role = origin;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d6222222-2222-2222-2222-222222222222"}',
  true
);

create temporary table t_solo_fake_cancelled as
select public.cancel_solo_contract_v1(
  (
    select (fixture.result ->> 'contract_id')::uuid
    from t_solo_fake_v2_result fixture
  ),
  'd6000000-0000-0000-0000-000000000067'
) as contract_id;

reset role;
select pg_catalog.set_config('app.solo_write_path', 'cancel_v1', true);

select throws_ok(
  $$ select pg_temp.insert_authorization_transition(
       'd6000000-0000-0000-0000-000000000068',
       (
         select (fixture.result ->> 'authorization_id')::uuid
         from t_solo_fake_v2_result fixture
       ),
       2::smallint,
       'cancelled',
       'cancel_solo_contract_v1',
       (
         select contract.cancelled_at
         from public.solo_contracts contract
         where contract.id = (
           select fixture.contract_id
           from t_solo_fake_cancelled fixture
         )
       )
     ) $$,
  '23001',
  null,
  'a second terminal transition is forbidden after exact cancellation'
);

select throws_ok(
  $$ update app.solo_authorizations
     set adapter_version = 'rewritten'
     where id = (
       select (result ->> 'authorization_id')::uuid
       from t_solo_fake_v2_result
     ) $$,
  '23001',
  null,
  'authorization facts cannot be updated'
);

select throws_ok(
  $$ delete from app.solo_authorizations
     where id = (
       select (result ->> 'authorization_id')::uuid
       from t_solo_fake_v2_result
     ) $$,
  '23001',
  null,
  'authorization facts cannot be deleted'
);

select throws_ok(
  $$ update app.solo_authorization_events
     set source_operation = 'rewritten'
     where authorization_id = (
       select (result ->> 'authorization_id')::uuid
       from t_solo_fake_v2_result
     ) $$,
  '23001',
  null,
  'authorization events cannot be updated'
);

select throws_ok(
  $$ delete from app.solo_authorization_events
     where authorization_id = (
       select (result ->> 'authorization_id')::uuid
       from t_solo_fake_v2_result
     ) $$,
  '23001',
  null,
  'authorization events cannot be deleted'
);

select throws_ok(
  $$ truncate table app.solo_authorization_events $$,
  '23001',
  null,
  'authorization events cannot be truncated'
);

select * from finish();
rollback;
