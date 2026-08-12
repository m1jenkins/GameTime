-- D81 provider cleanup lookup. The deletion Edge Function must remove the
-- Stripe sandbox Customer before the durable profile/auth transaction runs,
-- but the provider binding lives in the private app schema. Keep this narrow
-- read service-only; the client never receives provider identifiers.
begin;

create function public.account_deletion_provider_ids(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_customer_id text;
begin
  if p_actor_id is null then
    raise exception 'actor id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  select customer.stripe_customer_id
    into v_customer_id
  from app.personal_stripe_sandbox_customers customer
  join public.profiles profile
    on profile.id = customer.user_id
  join auth.users auth_user
    on auth_user.id = customer.user_id
  where customer.user_id = p_actor_id
    and profile.deleted_at is null;

  return case
    when v_customer_id is null then '{}'::jsonb
    else pg_catalog.jsonb_build_object(
      'stripe_customer_id', v_customer_id
    )
  end;
end;
$$;

comment on function public.account_deletion_provider_ids(uuid) is
  'Service-only lookup of provider identifiers needed before D81 account deletion.';

revoke all on function public.account_deletion_provider_ids(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.account_deletion_provider_ids(uuid)
  to service_role;

commit;
