# Friends Phase 5: hosted migrations

Applied September 23, 2026 at about 05:56 UTC to `gametime-p11b`
(`lyushhqoednheqwzsmxh`) only, from source `f6a2ce2`. No git push, no Edge
deploy, no Auth or Apple provider change, no setting change, and no change to
the checkout's linked project (`jrkzdttophnmkxjoyioo`).

## Gate override

The [plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md#phase-5--hosted-explicit-approval-after-both-owner-goals-are-final)
held Phase 5 until both owner goals were final, around October 4–6. The owner
chose to override that gate and apply the migrations now, knowing that
`20260920162025` rewrites `challenge_real_health_evaluate_v1`,
`challenge_evaluate_policy_v1`, `challenge_policy_v1` and
`challenge_mutate_unmetered_v1`, which score the owner's goals. The owner then
approved applying all pending migrations and hosted reads.

## Readback before

- **Migrations:** 96. Hosted matched the repo through `20260922150718`, with
  no hosted-only versions.
- **Owner goals:** the two Steps goals that started September 22 are void.
  Three goals are scheduled, all created September 22 and starting
  September 24 05:00 UTC (September 23, 10 PM PDT): two Personal Steps goals
  and one Personal Outdoor runs goal. Each has one member and one consent.
  None had started, so each is scored by the new functions from its start.
  This replaces the plan's assumption of one September 22–28 goal plus one
  September 24–30 goal.
- **Settings:** private trial on, one enrolled account, device verification
  off; real admission, ingestion and processing on.

## Applied

The dry run selected exactly these six, and `db push --include-all` applied them
in order:

1. `20260920162025_challenge_received_leaderboard_v2`
2. `20260922181912_challenge_fixture_admission_age_v1`
3. `20260922210000_friend_commands_v1`
4. `20260922210100_challenge_policy_allowlist_v1`
5. `20260922230000_challenge_freeze_member_privacy_v1`
6. `20260922230100_challenge_community_catalog_closed_v1`

## Readback after

- **Migrations:** 102, the six above added and no other change.
- **Owner goals:** the three scheduled goals are unchanged, still revision 1.
- **Trial and real runtime:** unchanged from before.
- **New settings at their defaults, so behavior is unchanged:**
  `allowlist_enforced`, `account_mode` and `links_enabled` off;
  `commands_only` off with a daily request limit of 20; the allowlist holds
  only Personal Steps and Personal Outdoor runs.
- **Access:** `authenticated` can execute the ten `friend_*_v1` RPCs and
  `challenge_availability_v1`; `anon` can execute none of them. Neither role
  can read `challenge_policy_runtime_v1`, `challenge_policy_allowlist_v1`,
  `friend_runtime_v1` or `friend_commands_v1`.

## How it was run

The checkout's CLI link points at the historical project and `db push` has no
`--project-ref` flag, so a scratch copy of `supabase/config.toml` and
`supabase/migrations` (verified identical to `f6a2ce2`) was linked to
`gametime-p11b` and used through `--workdir`. The CLI used its temporary login
role; no database password was stored.

## Not done

- The build 1 settings in `scripts/fixtures/friends-build1-settings.sql`
  (`commands_only`, `allowlist_enforced`, `account_mode`, the four friend
  goals) are not applied. They open friend goals to every age-confirmed
  account, so they belong with opening sign-up.
- The rest of Phase 5: `delete-account`, the Apple provider and sign-up, the
  owner's support grant, closing legacy grants, confirming saves on the
  phone, and the backup and pause questions.
