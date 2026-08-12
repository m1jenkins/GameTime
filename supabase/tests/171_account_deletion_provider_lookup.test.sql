-- D81 service-only provider lookup used by the deletion Edge Function.

begin;
select plan(8);

insert into auth.users (id)
values ('11111111-1111-1111-1111-111111111111');
insert into public.profiles (id, handle, display_name, timezone)
values (
  '11111111-1111-1111-1111-111111111111',
  'provider_lookup_user',
  'Provider Lookup User',
  'UTC'
);
insert into app.personal_stripe_sandbox_customers (
  user_id,
  stripe_customer_id
)
values (
  '11111111-1111-1111-1111-111111111111',
  'cus_ProviderLookup'
);

select has_function(
  'public',
  'account_deletion_provider_ids',
  'the account deletion provider lookup exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.account_deletion_provider_ids(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.account_deletion_provider_ids(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.account_deletion_provider_ids(uuid)',
    'execute'
  ),
  'only service_role can execute the provider lookup'
);

set local role service_role;
select is(
  public.account_deletion_provider_ids(
    '11111111-1111-1111-1111-111111111111'
  ),
  '{"stripe_customer_id": "cus_ProviderLookup"}'::jsonb,
  'the service lookup returns the provider id for the active actor'
);
select is(
  public.account_deletion_provider_ids(
    '22222222-2222-2222-2222-222222222222'
  ),
  '{}'::jsonb,
  'the service lookup returns no provider id for another actor'
);
reset role;
set local role authenticated;
select throws_ok(
  $$ select public.account_deletion_provider_ids(
       '11111111-1111-1111-1111-111111111111'
     ) $$,
  '42501',
  null,
  'the lookup rejects a non-service caller'
);
select throws_ok(
  $$ select public.account_deletion_provider_ids(null) $$,
  '42501',
  null,
  'the lookup rejects a non-service caller before actor validation'
);
reset role;
select ok(
  not has_table_privilege(
    'authenticated',
    'app.personal_stripe_sandbox_customers',
    'select'
  ),
  'authenticated cannot read the private provider binding'
);
select ok(
  not has_table_privilege(
    'anon',
    'app.personal_stripe_sandbox_customers',
    'select'
  ),
  'anon cannot read the private provider binding'
);

select * from finish();
rollback;
