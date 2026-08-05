-- Stripe sandbox schema boundary: private storage, fixed test provenance,
-- narrow versioned RPC grants, and no persisted secrets or raw provider bodies.

begin;
select no_plan();

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app'
      and relation.relname in (
        'personal_stripe_sandbox_customers',
        'personal_stripe_sandbox_setups',
        'personal_stripe_sandbox_agreements',
        'personal_stripe_sandbox_payment_reviews',
        'personal_stripe_sandbox_charge_commands',
        'personal_stripe_sandbox_webhook_receipts'
      )
      and relation.relkind = 'r'
  ),
  6::bigint,
  'all Stripe sandbox state lives in six private app tables'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app'
      and relation.relname in (
        'personal_stripe_sandbox_customers',
        'personal_stripe_sandbox_setups',
        'personal_stripe_sandbox_agreements',
        'personal_stripe_sandbox_payment_reviews',
        'personal_stripe_sandbox_charge_commands',
        'personal_stripe_sandbox_webhook_receipts'
      )
      and relation.relrowsecurity
  ),
  6::bigint,
  'RLS is enabled on every private Stripe sandbox table'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'app'
      and policy.tablename in (
        'personal_stripe_sandbox_customers',
        'personal_stripe_sandbox_setups',
        'personal_stripe_sandbox_agreements',
        'personal_stripe_sandbox_payment_reviews',
        'personal_stripe_sandbox_charge_commands',
        'personal_stripe_sandbox_webhook_receipts'
      )
  ),
  0::bigint,
  'private Stripe sandbox tables intentionally have no RLS policies'
);

select ok(
  not exists (
    select 1
    from (
      values ('public'), ('anon'), ('authenticated'), ('service_role')
    ) actor(role_name)
    cross join (
      values
        ('app.personal_stripe_sandbox_customers'),
        ('app.personal_stripe_sandbox_setups'),
        ('app.personal_stripe_sandbox_agreements'),
        ('app.personal_stripe_sandbox_payment_reviews'),
        ('app.personal_stripe_sandbox_charge_commands'),
        ('app.personal_stripe_sandbox_webhook_receipts')
    ) relation(relation_name)
    cross join (
      values ('select'), ('insert'), ('update'), ('delete'), ('truncate')
    ) operation(privilege_name)
    where has_table_privilege(
      actor.role_name,
      relation.relation_name,
      operation.privilege_name
    )
  ),
  'public, clients, and service_role have no direct table privileges'
);

select ok(
  not exists (
    select 1
    from information_schema.columns column_def
    where column_def.table_schema = 'app'
      and column_def.table_name like 'personal_stripe_sandbox_%'
      and (
        column_def.column_name like '%client_secret%'
        or column_def.column_name like '%webhook_secret%'
        or column_def.column_name like '%raw%'
        or column_def.column_name like '%body%'
        or column_def.column_name like '%card%'
      )
  ),
  'the database has no client secret, webhook secret, raw body, or card column'
);

select has_function(
  'public',
  'begin_personal_stripe_sandbox_setup_v1',
  array[
    'uuid',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'text',
    'timestamptz',
    'text',
    'text'
  ],
  'authenticated setup consent has a versioned boundary'
);

select has_function(
  'public',
  'begin_personal_stripe_sandbox_setup_service_v1',
  array[
    'uuid',
    'uuid',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'text',
    'timestamptz',
    'text',
    'text'
  ],
  'Edge setup consent has an explicit verified-owner boundary'
);

select has_function(
  'public',
  'record_personal_stripe_sandbox_customer_v1',
  array['uuid', 'text', 'boolean'],
  'Customer binding has a service boundary'
);

select has_function(
  'public',
  'record_personal_stripe_sandbox_setup_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'boolean'],
  'canonical SetupIntent refresh has a service boundary'
);

select has_function(
  'public',
  'load_personal_stripe_sandbox_setup_service_v1',
  array[
    'uuid',
    'uuid',
    'uuid',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'text',
    'timestamptz',
    'text',
    'text'
  ],
  'Edge commit load has an explicit verified-owner boundary'
);

select has_function(
  'public',
  'commit_personal_stripe_sandbox_challenge_service_v1',
  array[
    'uuid',
    'uuid',
    'uuid',
    'public.contest_cadence',
    'integer',
    'integer',
    'text',
    'text',
    'timestamptz',
    'text',
    'text'
  ],
  'Edge challenge commit has an explicit verified-owner boundary'
);

select has_function(
  'public',
  'request_personal_stripe_sandbox_review_service_v1',
  array['uuid', 'uuid', 'text', 'text'],
  'verified-owner review filing has a service-only boundary'
);

select has_function(
  'public',
  'settle_personal_stripe_sandbox_review_v1',
  array['uuid', 'text', 'text', 'text'],
  'review settlement is isolated from the V1 result publisher'
);

select has_function(
  'public',
  'claim_personal_stripe_sandbox_charges_v1',
  array['uuid', 'integer'],
  'the leased charge worker has a versioned claim boundary'
);

select has_function(
  'public',
  'record_personal_stripe_sandbox_charge_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'boolean'],
  'the leased charge worker has a normalized record boundary'
);

select has_function(
  'public',
  'apply_personal_stripe_sandbox_webhook_v1',
  array[
    'text',
    'bytea',
    'text',
    'text',
    'text',
    'timestamptz',
    'text',
    'text',
    'text',
    'boolean',
    'text',
    'text',
    'integer',
    'text',
    'text',
    'uuid'
  ],
  'normalized webhook reconciliation has a versioned service boundary'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.begin_personal_stripe_sandbox_setup_v1(uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.create_personal_challenge_with_stripe_sandbox_v2(uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_my_personal_stripe_sandbox_status_v1(uuid)',
    'execute'
  ),
  'authenticated clients receive only begin, direct commit, and owner-safe status'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.load_personal_stripe_sandbox_setup_service_v1(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.record_personal_stripe_sandbox_setup_v1(uuid,uuid,text,text,text,text,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_personal_stripe_sandbox_charges_v1(uuid,integer)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.begin_personal_stripe_sandbox_setup_v1(uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.request_personal_stripe_sandbox_review_service_v1(uuid,uuid,text,text)',
    'execute'
  ),
  'clients cannot load provider IDs, refresh provider state, or run workers'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.begin_personal_stripe_sandbox_setup_service_v1(uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.record_personal_stripe_sandbox_customer_v1(uuid,text,boolean)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.request_personal_stripe_sandbox_review_service_v1(uuid,uuid,text,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.record_personal_stripe_sandbox_setup_v1(uuid,uuid,text,text,text,text,boolean)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.load_personal_stripe_sandbox_setup_service_v1(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.commit_personal_stripe_sandbox_challenge_service_v1(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.apply_personal_stripe_sandbox_webhook_v1(text,bytea,text,text,text,timestamptz,text,text,text,boolean,text,text,integer,text,text,uuid)',
    'execute'
  ),
  'service_role receives the explicit Edge and worker boundaries'
);

select ok(
  (
    select position(
      'insert into app.personal_stripe_sandbox_payment_reviews'
      in pg_catalog.pg_get_functiondef(
        'app.open_personal_stripe_sandbox_review()'::regprocedure
      )
    ) > 0
  )
  and (
    select position(
      'personal_stripe_sandbox_charge_commands'
      in pg_catalog.pg_get_functiondef(
        'app.open_personal_stripe_sandbox_review()'::regprocedure
      )
    ) = 0
  ),
  'the result trigger opens review and cannot create a charge command'
);

select ok(
  (
    select count(*)
    from pg_catalog.pg_trigger trigger_def
    where trigger_def.tgrelid =
      'public.personal_challenge_results'::regclass
      and trigger_def.tgname =
        'personal_results_open_stripe_sandbox_review'
      and not trigger_def.tgisinternal
  ) = 1,
  'one result trigger owns the provisional review opening'
);

select ok(
  (
    select position(
      '''worker_failed'''
      in pg_catalog.pg_get_functiondef(
        'public.record_personal_stripe_sandbox_charge_v1(uuid,uuid,text,text,text,boolean)'::regprocedure
      )
    ) > 0
    and position(
      'when p_status = ''worker_failed'' then ''failed'''
      in pg_catalog.pg_get_functiondef(
        'public.record_personal_stripe_sandbox_charge_v1(uuid,uuid,text,text,text,boolean)'::regprocedure
      )
    ) > 0
  ),
  'a definite worker failure terminalizes without requiring a PaymentIntent'
);

select ok(
  (
    select position(
      'review.review_deadline <= v_now'
      in pg_catalog.pg_get_functiondef(
        'public.claim_personal_stripe_sandbox_charges_v1(uuid,integer)'::regprocedure
      )
    ) > 0
    and position(
      'review.state = ''review_open'''
      in pg_catalog.pg_get_functiondef(
        'public.claim_personal_stripe_sandbox_charges_v1(uuid,integer)'::regprocedure
      )
    ) > 0
    and position(
      'state = ''confirmed_miss'''
      in pg_catalog.pg_get_functiondef(
        'public.claim_personal_stripe_sandbox_charges_v1(uuid,integer)'::regprocedure
      )
    ) > 0
  ),
  'claim independently enforces the deadline and discovers expired unreviewed misses'
);

select ok(
  (
    select position(
      'an earlier paid challenge review or collection is unresolved'
      in pg_catalog.pg_get_functiondef(
        'app.commit_personal_stripe_sandbox_challenge_unchecked(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)'::regprocedure
      )
    ) > 0
  ),
  'paid challenge commit blocks while an earlier review or collection is unresolved'
);

select ok(
  exists (
    select 1
    from information_schema.columns column_def
    where column_def.table_schema = 'app'
      and column_def.table_name =
        'personal_stripe_sandbox_charge_commands'
      and column_def.column_name = 'first_attempted_at'
  )
  and (
    select position(
      'interval ''23 hours'''
      in pg_catalog.pg_get_functiondef(
        'public.claim_personal_stripe_sandbox_charges_v1(uuid,integer)'::regprocedure
      )
    ) > 0
  ),
  'ambiguous same-key recovery is bounded to 23 hours from first attempt'
);

select * from finish();
rollback;
