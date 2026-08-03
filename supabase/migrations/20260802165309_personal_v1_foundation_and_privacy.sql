-- Personal Accountability V1 -- model boundary and privacy-safe legacy reads.
--
-- Existing rows and legacy RPCs remain the social charity-contest model.  The
-- personal model is deliberately explicit so no old contest can be reinterpreted
-- by a new client or service worker.

create type public.challenge_model as enum (
  'legacy_charity_contest',
  'personal_accountability',
  'social_accountability'
);

alter table public.contests
  add column challenge_model public.challenge_model not null
    default 'legacy_charity_contest';

comment on column public.contests.challenge_model is
  'Immutable dispatcher. Existing and legacy-created rows are legacy_charity_contest; personal_accountability has isolated terms and results; social_accountability is reserved for V2.';

-- The original bound encoded the social minimum directly. Personal challenges
-- have exactly one owner; both social models retain the old 2--20 range.
alter table public.contests
  drop constraint contests_participant_range,
  add constraint contests_participant_range_by_model check (
    (
      challenge_model = 'personal_accountability'
      and max_participants = 1
    )
    or (
      challenge_model <> 'personal_accountability'
      and max_participants between 2 and 20
    )
  );

drop trigger contests_freeze_terms on public.contests;

create trigger contests_freeze_terms
  before update on public.contests
  for each row execute function app.forbid_column_change(
    'id', 'title', 'challenge_model', 'metric', 'cadence',
    'target_value', 'stake_amount_cents', 'tie_break',
    'starts_at', 'ends_at', 'max_participants', 'created_at'
  );

-- Accepted personal and future social-accountability participants do not carry
-- charity nominations. Legacy accepted participants still must. The cross-table
-- part belongs in a trigger; the local CHECK continues to guarantee a timezone.
alter table public.contest_participants
  drop constraint contest_participants_accepted_is_complete,
  add constraint contest_participants_accepted_has_timezone check (
    status <> 'accepted' or timezone is not null
  );

create function app.assert_participant_matches_challenge_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_model      public.challenge_model;
  v_created_by uuid;
begin
  select contest.challenge_model, contest.created_by
    into v_model, v_created_by
  from public.contests contest
  where contest.id = new.contest_id;

  if v_model is null then
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_model = 'personal_accountability' then
    if v_created_by is null or new.user_id <> v_created_by then
      raise exception 'a personal challenge may contain only its owner'
        using errcode = 'restrict_violation';
    end if;
    if new.status <> 'accepted' then
      raise exception 'a personal challenge owner is enrolled as accepted'
        using errcode = 'restrict_violation';
    end if;
    if new.charity_id is not null then
      raise exception 'a personal challenge cannot nominate a charity'
        using errcode = 'restrict_violation';
    end if;
  elsif v_model = 'legacy_charity_contest' then
    if new.status = 'accepted' and new.charity_id is null then
      raise exception 'a legacy accepted participant must nominate a charity'
        using errcode = 'check_violation';
    end if;
  elsif new.charity_id is not null then
    raise exception 'social accountability does not carry charity nominations'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger contest_participants_assert_model_terms
  before insert or update on public.contest_participants
  for each row execute function app.assert_participant_matches_challenge_model();

comment on function app.assert_participant_matches_challenge_model() is
  'Keeps participant cardinality and charity fields compatible with the immutable challenge model.';

-- Invitation reach remains unchanged for both social models. A personal row is
-- categorically single-owner even though the legacy table still has INSERT
-- granted for invitations.
create or replace function app.may_invite_to_contest(
  cid uuid,
  inviter uuid,
  invitee uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select inviter is not null
     and invitee is not null
     and inviter <> invitee
     and not app.is_blocked_either_way(inviter, invitee)
     and exists (
       select 1
       from public.contests contest
       where contest.id = cid
         and contest.status = 'pending'
         and contest.challenge_model <> 'personal_accountability'
         and contest.created_by = inviter
         and (
           app.is_friend(inviter, invitee)
           or (
             contest.group_id is not null
             and app.is_group_member(contest.group_id, invitee)
             and app.is_group_member(contest.group_id, inviter)
           )
         )
     );
$$;

-- ---------------------------------------------------------------------------
-- Selective reimplementation of 6cfae0b: direct rows are self-only. A bounded
-- definer RPC retains the aggregate/accepted-roster surface needed to render old
-- social history without disclosing pending invitee identities.
-- ---------------------------------------------------------------------------

drop policy if exists contest_participants_select_roster
  on public.contest_participants;

create policy contest_participants_select_self
  on public.contest_participants
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

comment on policy contest_participants_select_self
  on public.contest_participants is
  'A client reads only its own lifecycle row. Bounded social summaries come from list_my_challenge_summaries_v1().';

create function public.list_my_challenge_summaries_v1()
returns table (
  contest_id             uuid,
  title                  text,
  created_by             uuid,
  metric                 public.contest_metric,
  cadence                public.contest_cadence,
  target_value           numeric,
  stake_amount_cents     integer,
  tie_break              public.contest_tie_break,
  starts_at              timestamptz,
  ends_at                timestamptz,
  contest_status         public.contest_status,
  max_participants       smallint,
  caller_status          public.contest_participant_status,
  caller_timezone        text,
  accepted_count         bigint,
  invited_count          bigint,
  declined_count         bigint,
  withdrawn_count        bigint,
  lapsed_count           bigint,
  author_profile         jsonb,
  accepted_profiles      jsonb
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid;
begin
  v_caller_id := app.require_active_caller();

  return query
  select
    contest.id,
    contest.title,
    contest.created_by,
    contest.metric,
    contest.cadence,
    contest.target_value,
    contest.stake_amount_cents,
    contest.tie_break,
    contest.starts_at,
    contest.ends_at,
    contest.status,
    contest.max_participants,
    caller_participant.status,
    caller_participant.timezone,
    participant_counts.accepted_count,
    participant_counts.invited_count,
    participant_counts.declined_count,
    participant_counts.withdrawn_count,
    participant_counts.lapsed_count,
    case
      when author.id is null then null
      when caller_participant.status = 'accepted'
        or author.id = v_caller_id
      then pg_catalog.jsonb_build_object(
        'id', author.id,
        'handle', case
          when author.deleted_at is null then author.handle::text
          else null
        end,
        'display_name', case
          when author.deleted_at is null then author.display_name
          else 'Deleted member'
        end,
        'is_deleted', author.deleted_at is not null
      )
      when app.is_active_actor(author.id)
        and not app.is_blocked_either_way(v_caller_id, author.id)
        and (
          app.is_friend(v_caller_id, author.id)
          or app.shares_group(v_caller_id, author.id)
        )
      then pg_catalog.jsonb_build_object(
        'id', author.id,
        'handle', author.handle::text,
        'display_name', author.display_name,
        'is_deleted', false
      )
      else null
    end,
    case
      when caller_participant.status <> 'accepted' then '[]'::jsonb
      else coalesce(
        (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'id', accepted_profile.id,
              'handle', case
                when accepted_profile.deleted_at is null
                  then accepted_profile.handle::text
                else null
              end,
              'display_name', case
                when accepted_profile.deleted_at is null
                  then accepted_profile.display_name
                else 'Deleted member'
              end,
              'is_deleted', accepted_profile.deleted_at is not null
            )
            order by
              case
                when accepted_participant.user_id = contest.created_by then 0
                else 1
              end,
              accepted_participant.accepted_at,
              accepted_participant.user_id
          )
          from public.contest_participants accepted_participant
          join public.profiles accepted_profile
            on accepted_profile.id = accepted_participant.user_id
          where accepted_participant.contest_id = contest.id
            and accepted_participant.status = 'accepted'
        ),
        '[]'::jsonb
      )
    end
  from public.contest_participants caller_participant
  join public.contests contest
    on contest.id = caller_participant.contest_id
  left join public.profiles author
    on author.id = contest.created_by
  cross join lateral (
    select
      pg_catalog.count(*) filter (
        where participant.status = 'accepted'
      ) as accepted_count,
      pg_catalog.count(*) filter (
        where participant.status = 'invited'
      ) as invited_count,
      pg_catalog.count(*) filter (
        where participant.status = 'declined'
      ) as declined_count,
      pg_catalog.count(*) filter (
        where participant.status = 'withdrawn'
      ) as withdrawn_count,
      pg_catalog.count(*) filter (
        where participant.status = 'lapsed'
      ) as lapsed_count
    from public.contest_participants participant
    where participant.contest_id = contest.id
  ) participant_counts
  where caller_participant.user_id = v_caller_id
    and contest.challenge_model in (
      'legacy_charity_contest',
      'social_accountability'
    )
  order by contest.starts_at, contest.id;
end;
$$;

comment on function public.list_my_challenge_summaries_v1() is
  'Caller-bounded social challenge history. Pending identities stay hidden; accepted callers receive only minimum accepted profile cards.';

-- Personal rows must never enter the legacy competition/charity artifact path.
create function app.reject_personal_social_artifact()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.contests contest
    where contest.id = new.contest_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'personal challenges cannot create social contest artifacts'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger contest_results_reject_personal
  before insert on public.contest_results
  for each row execute function app.reject_personal_social_artifact();

create trigger contest_standing_snapshots_reject_personal
  before insert on public.contest_standing_snapshots
  for each row execute function app.reject_personal_social_artifact();

create trigger contest_standing_entries_reject_personal
  before insert on public.contest_standing_entries
  for each row execute function app.reject_personal_social_artifact();

create trigger donation_obligations_reject_personal
  before insert on public.donation_obligations
  for each row execute function app.reject_personal_social_artifact();

create trigger contest_geofences_reject_personal
  before insert on public.contest_geofences
  for each row execute function app.reject_personal_social_artifact();

create trigger geofence_checkins_reject_personal
  before insert on public.geofence_checkins
  for each row execute function app.reject_personal_social_artifact();

create trigger timezone_change_requests_reject_personal
  before insert on public.timezone_change_requests
  for each row execute function app.reject_personal_social_artifact();

create trigger timezone_change_applied_events_reject_personal
  before insert on public.timezone_change_applied_events
  for each row execute function app.reject_personal_social_artifact();

revoke all on function app.assert_participant_matches_challenge_model(),
                       app.reject_personal_social_artifact()
  from public, anon, authenticated, service_role;

revoke all on function public.list_my_challenge_summaries_v1()
  from public, anon, authenticated, service_role;

grant execute on function public.list_my_challenge_summaries_v1()
  to authenticated;
