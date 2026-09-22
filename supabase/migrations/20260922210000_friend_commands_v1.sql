-- D142 friends. Versioned commands for friend requests, acceptance, silent
-- decline, cancel, remove, block, unblock, report, list and lookup.
--
-- Each mutation carries an actor-bound request ID. An exact retry returns the
-- saved receipt; a different payload under the same ID is refused. Each one
-- also states the pair state it expects (incoming, outgoing, friends, blocked)
-- and is refused with friend_state_changed when the pair has moved on, so a
-- stale screen or a crossed request can't act on the wrong state.
--
-- Protection for the first private TestFlight cohort, per the friends plan:
-- request IDs, expected state, suspension checks, one daily request cap and a
-- lookup rate limit that shares the invite command's 30-per-minute "lookup"
-- bucket. Decline cooldowns, pending caps and friend-list caps are deferred.
--
-- Block and report work for any account, not only co-participants. Inside a
-- shared challenge a block keeps the consequences of challenge_block_v1: both
-- people leave any unfinished challenge they share, through the same safe tick.
-- Remove leaves shared challenges alone; friendship is checked only at invite.
--
-- Direct table writes stay possible until an operator sets
-- friend_runtime_v1.commands_only. Historical tests and fixtures keep their
-- behavior with the default. With it on, public.friendships and public.blocks
-- accept writes only inside a command, the legacy challenge block, or account
-- deletion.

create table app.friend_runtime_v1 (
  singleton boolean primary key default true check (singleton),
  commands_only boolean not null default false,
  daily_request_limit integer not null default 20 check (daily_request_limit between 1 and 200)
);
insert into app.friend_runtime_v1 default values;

create table app.friend_commands_v1 (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  payload jsonb not null,
  response jsonb not null,
  recorded_at timestamptz not null,
  primary key (actor_id, request_id)
);

alter table app.friend_runtime_v1 enable row level security;
alter table app.friend_commands_v1 enable row level security;
revoke all on app.friend_runtime_v1, app.friend_commands_v1
  from public, anon, authenticated, service_role;

-- The guard runs as whoever writes, including a signed-in client, so the one
-- setting it needs is read through a definer helper that returns only it.
create function app.friend_commands_only_v1()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select commands_only from app.friend_runtime_v1 where singleton), false);
$$;

-- Writes to friendships, blocks and the command journal must come from the
-- table owner inside a marked transaction. For friendships and blocks the
-- check applies only once commands_only is on.
create function app.friend_write_guard_v1()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_table_name in ('friendships', 'blocks') and not app.friend_commands_only_v1() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if current_user <> pg_catalog.pg_get_userbyid(
       (select relowner from pg_catalog.pg_class where oid = tg_relid))
     or not (
       coalesce(current_setting('app.friend_write_v1', true), '') = 'on'
       or coalesce(current_setting('app.challenge_write_v1', true), '') = 'on'
       or coalesce(current_setting('app.system_actor_lock_bypass', true), '') = 'on')
  then
    raise exception 'friend_command_required' using errcode = '42501';
  end if;
  if tg_table_name = 'friend_commands_v1' and tg_op = 'UPDATE' then
    raise exception 'friend_immutable' using errcode = '23001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger friendships_000_command_guard
  before insert or update or delete on public.friendships
  for each row execute function app.friend_write_guard_v1();
create trigger friendships_000_command_no_truncate
  before truncate on public.friendships
  for each statement execute function app.friend_write_guard_v1();
create trigger blocks_000_command_guard
  before insert or update or delete on public.blocks
  for each row execute function app.friend_write_guard_v1();
create trigger blocks_000_command_no_truncate
  before truncate on public.blocks
  for each statement execute function app.friend_write_guard_v1();
create trigger friend_commands_guard
  before insert or update or delete on app.friend_commands_v1
  for each row execute function app.friend_write_guard_v1();
create trigger friend_commands_no_truncate
  before truncate on app.friend_commands_v1
  for each statement execute function app.friend_write_guard_v1();

-- Account deletion already removes friendships and blocks. The deleted
-- actor's own command journal goes with them.
create function app.friend_forget_deleted_v1()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    perform set_config('app.friend_write_v1', 'on', true);
    delete from app.friend_commands_v1 where actor_id = new.id;
  end if;
  return new;
end;
$$;
create trigger profiles_forget_friend_commands
  after update of deleted_at on public.profiles
  for each row execute function app.friend_forget_deleted_v1();

-- The pair state from the caller's side. Blocks are separate: a block severs
-- the friendship row, so a blocked pair reads as none here.
create function app.friend_state_v1(a uuid, b uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case
      when f.status = 'accepted' then 'friends'
      when f.requested_by = a then 'outgoing'
      else 'incoming' end
    from public.friendships f
    where f.user_a = least(a, b) and f.user_b = greatest(a, b)), 'none');
$$;

-- Someone you can find, ask, or accept: an active, age-confirmed account that
-- isn't suspended, isn't you, and has no block with you in either direction.
create function app.friend_reachable_v1(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select b is not null and a is distinct from b
    and app.is_active_actor(b)
    and not app.challenge_actor_unavailable_v1(b)
    and exists (select 1 from app.challenge_age_v1 where actor_id = b)
    and not app.is_blocked_either_way(a, b);
$$;

-- Sending, accepting and looking up need a confirmed 21+ account that isn't
-- suspended. Decline, cancel, remove, block, unblock and report stay open.
create function app.friend_require_participant_v1(a uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from app.challenge_age_v1 where actor_id = a) then
    raise exception 'friend_age_required' using errcode = '42501';
  end if;
  if exists (select 1 from app.challenge_suspensions_v1 where actor_id = a and suspended) then
    raise exception 'friend_account_restricted' using errcode = '42501';
  end if;
end;
$$;

create function app.friend_replay_v1(p_actor uuid, p_request_id uuid, p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare saved app.friend_commands_v1;
begin
  if p_request_id is null then raise exception 'friend_invalid_request' using errcode = '22023'; end if;
  select * into saved from app.friend_commands_v1 where actor_id = p_actor and request_id = p_request_id;
  if not found then return null; end if;
  if saved.payload is distinct from p_payload then
    raise exception 'friend_request_conflict' using errcode = '22023';
  end if;
  return saved.response;
end;
$$;

create function app.friend_save_v1(p_actor uuid, p_request_id uuid, p_payload jsonb, p_response jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('app.friend_write_v1', 'on', true);
  insert into app.friend_commands_v1 values (p_actor, p_request_id, p_payload, p_response, clock_timestamp());
  return p_response;
end;
$$;

-- Lock both profiles in UUID order, the same order the deletion triggers and
-- challenge_block_v1 use, so crossed requests serialize on the pair.
create function app.friend_lock_pair_v1(a uuid, b uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform id from public.profiles where id in (a, b) order by id for update;
end;
$$;

create function app.friend_expect_v1(a uuid, b uuid, expected text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if app.friend_state_v1(a, b) is distinct from expected then
    raise exception 'friend_state_changed' using errcode = '55000';
  end if;
end;
$$;

-- Lookup by exact username. Every attempt by an eligible caller counts
-- against the shared lookup budget, and a limited attempt returns an error
-- body instead of raising so the counter commits. Hidden accounts (blocked
-- either way, suspended, deleted, not age-confirmed) look the same as a
-- username that doesn't exist.
create function public.friend_lookup_v1(p_username text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_session_v1(); wanted text; p public.profiles;
begin
  perform app.friend_require_participant_v1(a);
  if not app.challenge_quota_v1(a, 'lookup', 30, interval '1 minute') then
    return app.challenge_quota_error_v1('friend_lookup_rate_limited');
  end if;
  wanted := ltrim(btrim(coalesce(p_username, '')), '@');
  if wanted !~ '^[A-Za-z][A-Za-z0-9_]{2,29}$' then return '{"found":false}'; end if;
  select * into p from public.profiles
  where lower(handle::text) = lower(wanted) and deleted_at is null;
  if p.id is null then return '{"found":false}'; end if;
  if p.id = a then
    return jsonb_build_object('found', true, 'id', p.id, 'username', p.handle::text,
      'display_name', p.display_name, 'relation', 'self');
  end if;
  if not app.friend_reachable_v1(a, p.id) then return '{"found":false}'; end if;
  return jsonb_build_object('found', true, 'id', p.id, 'username', p.handle::text,
    'display_name', p.display_name, 'relation', app.friend_state_v1(a, p.id));
end;
$$;

create function public.friend_request_v1(p_request_id uuid, p_subject uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', 'request', 'subject', p_subject);
 saved jsonb; state text; lim integer;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  perform app.friend_require_participant_v1(a);
  if p_subject is null or p_subject = a then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  perform app.friend_lock_pair_v1(a, p_subject);
  if not app.friend_reachable_v1(a, p_subject) then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  state := app.friend_state_v1(a, p_subject);
  if state = 'incoming' then
    raise exception 'friend_incoming_request_exists' using errcode = '23505';
  elsif state = 'outgoing' then
    raise exception 'friend_request_already_sent' using errcode = '23505';
  elsif state = 'friends' then
    raise exception 'friend_already_friends' using errcode = '23505';
  end if;
  select daily_request_limit into lim from app.friend_runtime_v1 where singleton;
  if not app.challenge_quota_v1(a, 'friend_requests', lim, interval '1 day') then
    raise exception 'friend_request_limit' using errcode = 'P0001';
  end if;
  perform set_config('app.friend_write_v1', 'on', true);
  insert into public.friendships (user_a, user_b, requested_by, status)
  values (least(a, p_subject), greatest(a, p_subject), a, 'pending');
  return app.friend_save_v1(a, p_request_id, payload, '{"state":"outgoing"}');
end;
$$;

create function public.friend_accept_v1(p_request_id uuid, p_subject uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', 'accept', 'subject', p_subject);
 saved jsonb;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  perform app.friend_require_participant_v1(a);
  if p_subject is null or p_subject = a then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  perform app.friend_lock_pair_v1(a, p_subject);
  perform app.friend_expect_v1(a, p_subject, 'incoming');
  if not app.friend_reachable_v1(a, p_subject) then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  perform set_config('app.friend_write_v1', 'on', true);
  update public.friendships set status = 'accepted'
  where user_a = least(a, p_subject) and user_b = greatest(a, p_subject);
  return app.friend_save_v1(a, p_request_id, payload, '{"state":"friends"}');
end;
$$;

-- Decline, cancel and remove delete the row. Nobody is notified.
create function app.friend_end_pair_v1(p_request_id uuid, p_subject uuid, p_op text, p_expected text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', p_op, 'subject', p_subject);
 saved jsonb;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  if p_subject is null or p_subject = a then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  perform app.friend_lock_pair_v1(a, p_subject);
  perform app.friend_expect_v1(a, p_subject, p_expected);
  perform set_config('app.friend_write_v1', 'on', true);
  delete from public.friendships
  where user_a = least(a, p_subject) and user_b = greatest(a, p_subject);
  return app.friend_save_v1(a, p_request_id, payload, '{"state":"none"}');
end;
$$;

create function public.friend_decline_v1(p_request_id uuid, p_subject uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select app.friend_end_pair_v1(p_request_id, p_subject, 'decline', 'incoming');
$$;
create function public.friend_cancel_v1(p_request_id uuid, p_subject uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select app.friend_end_pair_v1(p_request_id, p_subject, 'cancel', 'outgoing');
$$;
create function public.friend_remove_v1(p_request_id uuid, p_subject uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select app.friend_end_pair_v1(p_request_id, p_subject, 'remove', 'friends');
$$;

-- Any account may be blocked. Challenge scopes lock first in UUID order, then
-- profiles, as in challenge_block_v1; the insert severs any friendship or
-- request, and the safe tick exits both people from unfinished shared
-- challenges exactly as before.
create function public.friend_block_v1(p_request_id uuid, p_subject uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', 'block', 'subject', p_subject);
 saved jsonb; ids uuid[]; c uuid;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  if p_subject is null or p_subject = a or not app.is_active_actor(p_subject) then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  select coalesce(array_agg(distinct me.challenge_id order by me.challenge_id), '{}') into ids
  from app.challenge_members_v1 me
  join app.challenge_members_v1 other using (challenge_id)
  where me.actor_id = a and other.actor_id = p_subject;
  perform app.challenge_lock_many_v1('challenge', ids);
  perform app.friend_lock_pair_v1(a, p_subject);
  if exists (select 1 from public.blocks where blocker_id = a and blocked_id = p_subject) then
    raise exception 'friend_state_changed' using errcode = '55000';
  end if;
  perform set_config('app.friend_write_v1', 'on', true);
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into public.blocks (blocker_id, blocked_id) values (a, p_subject);
  foreach c in array ids loop
    perform app.challenge_tick_v1(c, true);
  end loop;
  return app.friend_save_v1(a, p_request_id, payload, '{"state":"blocked"}');
end;
$$;

-- Unblocking removes only your own block. It never restores a friendship.
create function public.friend_unblock_v1(p_request_id uuid, p_subject uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', 'unblock', 'subject', p_subject);
 saved jsonb;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  if p_subject is null or p_subject = a then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  perform app.friend_lock_pair_v1(a, p_subject);
  if not exists (select 1 from public.blocks where blocker_id = a and blocked_id = p_subject) then
    raise exception 'friend_state_changed' using errcode = '55000';
  end if;
  perform set_config('app.friend_write_v1', 'on', true);
  delete from public.blocks where blocker_id = a and blocked_id = p_subject;
  return app.friend_save_v1(a, p_request_id, payload, '{"state":"none"}');
end;
$$;

-- Reports about any account land in the same queue support already reads,
-- with the same three reasons and the shared 10-per-hour report budget.
-- No free-text note is stored.
create function public.friend_report_v1(p_request_id uuid, p_subject uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_mutation_session_v1();
 payload jsonb := jsonb_build_object('op', 'report', 'subject', p_subject, 'reason', p_reason);
 saved jsonb;
begin
  saved := app.friend_replay_v1(a, p_request_id, payload);
  if saved is not null then return saved; end if;
  if p_reason is null or p_reason not in ('username', 'unwanted_contact', 'unsafe_behavior') then
    raise exception 'friend_invalid_request' using errcode = '22023';
  end if;
  if p_subject is null or p_subject = a or not app.is_active_actor(p_subject) then
    raise exception 'friend_unavailable' using errcode = '42501';
  end if;
  if not app.challenge_quota_v1(a, 'reports', 10, interval '1 hour') then
    raise exception 'friend_rate_limited' using errcode = 'P0001';
  end if;
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_reports_v1 (id, reporter, subject, reason, created_at)
  values (extensions.gen_random_uuid(), a, p_subject, p_reason, app.challenge_now_v1());
  return app.friend_save_v1(a, p_request_id, payload, '{"saved":true}');
end;
$$;

-- The caller's own lists. Friends and requests show only people you can
-- still reach; the list shows no challenge, activity or other person's data.
-- Blocked people stay listed so you can unblock them.
create function public.friend_list_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a uuid := app.challenge_session_v1();
begin
  return jsonb_build_object(
    'server_time', clock_timestamp(),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.handle::text,
        'display_name', p.display_name, 'since', f.accepted_at, 'you_asked', f.requested_by = a)
        order by lower(p.display_name), p.id)
      from public.friendships f
      join public.profiles p on p.id = case when f.user_a = a then f.user_b else f.user_a end
      where a in (f.user_a, f.user_b) and f.status = 'accepted' and app.friend_reachable_v1(a, p.id)), '[]'),
    'incoming', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.handle::text,
        'display_name', p.display_name, 'sent_at', f.created_at)
        order by f.created_at desc, p.id)
      from public.friendships f
      join public.profiles p on p.id = f.requested_by
      where a in (f.user_a, f.user_b) and f.status = 'pending' and f.requested_by <> a
        and app.friend_reachable_v1(a, p.id)), '[]'),
    'outgoing', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.handle::text,
        'display_name', p.display_name, 'sent_at', f.created_at)
        order by f.created_at desc, p.id)
      from public.friendships f
      join public.profiles p on p.id = case when f.user_a = a then f.user_b else f.user_a end
      where a in (f.user_a, f.user_b) and f.status = 'pending' and f.requested_by = a
        and app.friend_reachable_v1(a, p.id)), '[]'),
    'blocked', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.handle::text,
        'display_name', p.display_name) order by b.created_at desc, p.id)
      from public.blocks b join public.profiles p on p.id = b.blocked_id
      where b.blocker_id = a and app.is_active_actor(p.id)), '[]'));
end;
$$;

revoke all on function app.friend_write_guard_v1(), app.friend_forget_deleted_v1(),
  app.friend_state_v1(uuid, uuid), app.friend_reachable_v1(uuid, uuid),
  app.friend_require_participant_v1(uuid), app.friend_replay_v1(uuid, uuid, jsonb),
  app.friend_save_v1(uuid, uuid, jsonb, jsonb), app.friend_lock_pair_v1(uuid, uuid),
  app.friend_expect_v1(uuid, uuid, text), app.friend_end_pair_v1(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.friend_commands_only_v1() from public, anon, authenticated, service_role;
grant execute on function app.friend_commands_only_v1() to authenticated, service_role;

do $$
declare f regprocedure;
begin
  for f in select oid::regprocedure from pg_proc
    where pronamespace = 'public'::regnamespace and proname in (
      'friend_lookup_v1', 'friend_request_v1', 'friend_accept_v1', 'friend_decline_v1',
      'friend_cancel_v1', 'friend_remove_v1', 'friend_block_v1', 'friend_unblock_v1',
      'friend_report_v1', 'friend_list_v1')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
