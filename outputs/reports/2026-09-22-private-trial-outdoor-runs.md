# Private trial personal outdoor runs

Applied September 22, 2026 to `gametime-p11b` (`lyushhqoednheqwzsmxh`) only.
No git push, no Edge redeploy, and no change to the checkout’s linked project
(`jrkzdttophnmkxjoyioo`). The skipped leaderboard migration
`20260920162025` was left unapplied.

## What failed

`challenge_private_trial_personal_steps_only` is raised in two places:

- `app.challenge_admit_v1`, when the trial is on and the command is not a real
  Health command. That still refuses the historical fixture path.
- `app.challenge_private_device_row_guard_v1`, when a real source is written.
  That guard was the save failure. Personal preview and the outdoor distance
  contracts already accepted `personal_distance_goal_v1` with
  `apple_workout_outdoor_distance_v1`. The guard rejected the readiness,
  lobby, consent, and activity rows.

## What changed

Migration `20260922150718_private_trial_personal_outdoor_distance_v1` replaces
the row guard. While the trial is enabled, a real source is allowed only for:

- `apple_watch_steps_v1` with no policy yet, or `personal_steps_goal_v1`
- `apple_workout_outdoor_distance_v1` with no policy yet, or `personal_distance_goal_v1`

Friend, community, Activity minutes, timed runs, and mismatched pairs still
raise `challenge_private_trial_personal_steps_only`. The code name is unchanged.
The on-screen sentence now says the trial supports Steps and Outdoor runs.

The trial flag, the single enrolled account, and device-verification-off mode
were read back unchanged. `ingest-challenge-health` already accepts the outdoor
distance source, so no Edge function was redeployed.

The Staging client already sends `apple_workout_outdoor_distance_v1` for
Outdoor runs and shows Health consent for that source. Steps stays the default
chip. This change does not alter the Outdoor runs | Steps chips or the
“Challenge locked in.” screen.

## Checks

Disposable local pgTAP, then the stack was removed: `526_private_device_trial`
and `527_private_account_health`, 47 assertions, all passed. Covered cases
include enrolled preview and commit of a personal outdoor distance goal, exact
retry, unsigned readiness and activity sync, and refusals for unenrolled
accounts, friend steps, friend distance, community steps, Activity minutes,
timed runs, and mismatched source/policy pairs.

Hosted readback: the allowlist function is installed, clients cannot execute
it, personal steps and personal outdoor distance are allowed, friend distance,
timed runs, and Activity minutes are not.

## On the phone

Use the enrolled Staging account. Start a personal goal, leave Steps as the
default or tap Outdoor runs, enter a distance, continue, connect Apple Health
if asked, and refresh until the activity check is ready. Read the rules, agree,
and save. The goal should stay saved and show “Challenge locked in.” It should
not show the private-trial refusal.
