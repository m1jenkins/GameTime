# Fixture admission age check

Local fix, September 22, 2026. Nothing was applied to `gametime-p11b` or any
other hosted project, and nothing was pushed.

## What was wrong

`app.challenge_admit_v1` has two admission paths. The fixture path runs when a
command is not a real-health command. It admits an actor on the fixture roster
(`challenge_runtime_v1.actors`) or with Beta access (`challenge_access_v1`) when
admission and fixtures are on and the actor is not suspended.

- `20260908050901_challenge_access_links_safety_v1.sql:32–37` checked 21+
  confirmation (`app.challenge_age_v1`) after the paused check.
- `20260920010824_challenge_real_health_ingest_v1.sql:708–730` rewrote the
  function. The real-health path kept the age check, but the fixture path lost
  it (lines 720–727).
- `20260920160248_private_device_trial_v1.sql:36–65` added the private-trial
  checks and kept the gap.

It was logged in `docs/FRIENDS_TESTFLIGHT_PLAN.md` under "Logged, not in scope".
It is low severity. Fixtures are off on hosted `gametime-p11b`, and while its
private trial is enabled, that trial refuses the fixture path before this point
with `challenge_private_trial_personal_steps_only`.

## What changed

Migration `20260922181912_challenge_fixture_admission_age_v1` replaces the
function with the `20260920160248` body plus one check. After the existing
fixture paused check, an actor without an age record is refused with
`challenge_age_required` (`42501`). The order matches `20260908050901`: an actor
who was paused before is still paused, not asked for 21+ confirmation.

A diff against the `20260920160248` body shows only those three added lines.
Private-trial checks, the real-health path, the suspension check, error codes
and function privileges are unchanged. No other migration since `20260920160248`
redefines the function, including `20260922150718`.

Callers are unchanged. Create, lobby changes other than leave, cancel and
review, the freeze roster loop, Personal commit, community join and invitation
link issue already call this function. Leave, cancel and review do not.

## Checks

New pgTAP `528_challenge_fixture_admission_age` (14 assertions) uses
fictional actors and rolls back. It covers:

- **Refused:** a fixture roster actor and a Beta-access actor without 21+
  confirmation get `challenge_age_required`, both from the function and from
  the public create command.
- **Admitted:** an age-confirmed roster actor. The same two actors are
  admitted after they confirm 21+, and the roster actor can then create a
  challenge.
- **Still paused:** an actor off the roster, a suspended actor without 21+
  confirmation, and an age-confirmed actor with fixtures off all still get
  `challenge_admission_paused`.
- **Unchanged:** the real-health path still requires 21+ confirmation without
  the roster, and still admits an age-confirmed actor.
- **Unchanged:** with the private trial on, an unenrolled account still gets
  `challenge_private_trial_account_required`, and an enrolled account on the
  fixture path still gets `challenge_private_trial_personal_steps_only` before
  any age check.

Both runs used disposable local stacks. Each copied the tracked `supabase/`
inputs plus the new files into the session scratch directory, with its own
project ID, ports 57520–57529 and Docker network. Both were stopped with `--no-backup`, and no
containers, networks or volumes were left. No other checkout's stack was
reset or reused.

- **With the fix:** 98 migrations applied, the latest `20260922181912`. The
  full suite passed: 111 files, 5,058 assertions.
- **Negative control:** 97 migrations applied, without `20260922181912`.
  Only `528` ran. Assertions 2–4, the three age refusals, failed with "no
  exception", and the other 11 passed.

## Not done

- Not applied to `gametime-p11b`. Applying it needs separate authorization.
  `20260920162025` is also still unapplied there, so a hosted push would need
  to handle that older migration too.
- No native, Edge function or copy change. `challenge_age_required` already
  maps to "Confirm that you are 21 or older before continuing."
  (`ios/GameTime/GameTime/ChallengeV1Models.swift:171`).
