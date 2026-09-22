-- D142 build 1: a roster freeze that fails because of another member reveals
-- nothing about that member's other challenges.
--
-- Freeze checks every selected member: admission, suspension, blocks, the
-- three-unsettled limit and same-activity overlap. Until now the creator got
-- the other member's own reason. The app words those reasons as the creator's
-- own problem ("You already have a friend challenge for this activity during
-- these dates"), which is wrong for the creator and hints at the other
-- person's challenges. Friends Phase 4 found this over HTTP.
--
-- The creator is now checked first and keeps their specific reasons, so a
-- creator who is at a limit themselves hears about it even when a friend is
-- too. For any other member, these reasons become challenge_member_unavailable.
-- Everything else about the freeze is unchanged: the whole freeze still fails,
-- the lobby stays open, no slot is saved and the agreement lists participants
-- in the same order. Other errors, such as lock or serialization failures,
-- still reach the caller unchanged.

do $migration$
declare d text; marker text;
begin
 d := pg_get_functiondef('app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
 marker := $m$   foreach x in array roster loop
    perform app.challenge_admit_v1(x);
    if app.challenge_actor_unavailable_v1(x) or exists(select 1 from unnest(roster) y where app.is_blocked_either_way(x,y)) then raise exception 'challenge_participant_unavailable' using errcode='42501'; end if;
    perform app.challenge_slot_v1(x,c);
$m$;
 if position(marker in d) = 0 then raise exception 'Unexpected roster freeze'; end if;
 execute replace(d, marker, $m$   foreach x in array array[a] || array_remove(roster, a) loop
    begin
     perform app.challenge_admit_v1(x);
     if app.challenge_actor_unavailable_v1(x) or exists(select 1 from unnest(roster) y where app.is_blocked_either_way(x,y)) then raise exception 'challenge_participant_unavailable' using errcode='42501'; end if;
     perform app.challenge_slot_v1(x,c);
    exception when sqlstate '42501' or sqlstate '23505' then
     if x = a or sqlerrm not in ('challenge_participant_unavailable', 'challenge_metric_overlap', 'challenge_unsettled_limit',
       'challenge_age_required', 'challenge_admission_paused', 'challenge_private_trial_account_required') then raise; end if;
     raise exception 'challenge_member_unavailable' using errcode = '42501';
    end;
$m$);
end;
$migration$;
