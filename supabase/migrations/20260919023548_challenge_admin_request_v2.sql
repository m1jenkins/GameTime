-- New administration only. Historical void v1 calls have no request identity
-- and cannot be backfilled or safely recovered by inventing one after dispatch.
create table app.challenge_admin_requests_v2 (
  request_id uuid primary key,
  payload jsonb not null,
  response jsonb not null,
  recorded_at timestamptz not null
);
alter table app.challenge_admin_requests_v2 enable row level security;
revoke all on app.challenge_admin_requests_v2 from public, anon, authenticated, service_role;
create trigger challenge_admin_requests_guard
  before insert or update or delete on app.challenge_admin_requests_v2
  for each row execute function app.challenge_entry_guard_v1();
create trigger challenge_admin_requests_no_truncate
  before truncate on app.challenge_admin_requests_v2
  for each statement execute function app.challenge_entry_guard_v1();

create function public.challenge_admin_request_v2(p_request_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  saved app.challenge_admin_requests_v2;
  operation text;
  required_keys text[];
  actor uuid;
  challenge uuid;
  expiry timestamptz;
  recorded timestamptz;
  response jsonb;
begin
  -- Service authorization precedes even receipt recovery. There is no human
  -- identity here, and no service-key fallback for human review decisions.
  perform app.duel_require_service_v1();
  if p_request_id is null then
    raise exception 'challenge_invalid_admin_request' using errcode = '22023';
  end if;
  -- One namespace across all four operations/subjects/scopes. A duplicate waits
  -- for the first transaction to commit (or roll back) before looking up its
  -- receipt. This lock is taken before the existing v1 gate/scope/row locks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('challenge_admin_request_v2:' || p_request_id::text, 0));
  select * into saved from app.challenge_admin_requests_v2 where request_id = p_request_id;
  if found then
    if saved.payload is distinct from p_payload then
      raise exception 'challenge_request_conflict' using errcode = '22023';
    end if;
    -- Never revalidate a past grant's expiry or reapply either transition.
    -- This receipt describes history, not the subject's current authority.
    return saved.response;
  end if;

  if jsonb_typeof(p_payload) is distinct from 'object'
     or octet_length(p_payload::text) > 4096
     or p_payload->>'version' is distinct from 'challenge_admin_request_v2' then
    raise exception 'challenge_invalid_admin_request' using errcode = '22023';
  end if;
  operation := p_payload->>'operation';
  required_keys := array['version', 'operation', 'actor_id'];
  case operation
    when 'grant_operator' then required_keys := required_keys || array['challenge_id', 'capability', 'expires_at'];
    when 'revoke_operator' then required_keys := required_keys || array['challenge_id', 'capability'];
    when 'grant_support' then required_keys := required_keys || array['expires_at'];
    when 'revoke_support' then null;
    else raise exception 'challenge_invalid_admin_request' using errcode = '22023';
  end case;
  if not (p_payload ?& required_keys) or p_payload - required_keys <> '{}'::jsonb
     or exists(select 1 from jsonb_each(p_payload) field where jsonb_typeof(field.value) <> 'string') then
    raise exception 'challenge_invalid_admin_request' using errcode = '22023';
  end if;
  actor := (p_payload->>'actor_id')::uuid;
  if operation in ('grant_operator', 'revoke_operator') then
    challenge := (p_payload->>'challenge_id')::uuid;
    if p_payload->>'capability' not in ('review', 'moderate') then
      raise exception 'challenge_invalid_admin_request' using errcode = '22023';
    end if;
  end if;
  if operation in ('grant_operator', 'grant_support') then
    expiry := (p_payload->>'expires_at')::timestamptz;
    if not isfinite(expiry) then
      raise exception 'challenge_invalid_grant' using errcode = '22023';
    end if;
  end if;

  -- Reuse the existing authorization, independence, expiry, scope and audit
  -- semantics. A revoke of an absent grant remains an audited successful no-op.
  case operation
    when 'grant_operator' then
      perform public.challenge_grant_operator_v1(actor, challenge, p_payload->>'capability', expiry);
    when 'revoke_operator' then
      perform public.challenge_revoke_operator_v1(actor, challenge, p_payload->>'capability');
    when 'grant_support' then
      perform public.challenge_grant_support_v1(actor, expiry);
    when 'revoke_support' then
      perform public.challenge_revoke_support_v1(actor);
  end case;
  recorded := app.challenge_now_v1();
  response := jsonb_build_object('version', 'challenge_admin_receipt_v2',
    'request_id', p_request_id, 'request', p_payload, 'recorded_at', recorded);
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_admin_requests_v2 values(p_request_id, p_payload, response, recorded);
  return response;
end
$$;
revoke all on function public.challenge_admin_request_v2(uuid,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.challenge_admin_request_v2(uuid,jsonb) to service_role;
comment on table app.challenge_admin_requests_v2 is
  'Immutable new administrator request/receipt pairs; no historical v1 backfill or named administrator attribution.';
