# Friends build 1 settings on gametime-p11b

Applied September 26, 2026, shortly before the 15:07:43 UTC readback, to
`gametime-p11b` (`lyushhqoednheqwzsmxh`) only, with the owner's approval for
this one change, from source `b86a006`. The only hosted write was
`scripts/fixtures/friends-build1-settings.sql`, exactly as written (SHA-256
`fab7dfaf4e46c5a00ca82061a84caac8b6e6a30133c6df8aeaac25859340aee5`), sent as one
batch through the Supabase MCP with the project ref named explicitly. No
migration, function deploy, Auth or Apple provider change, grant, enrollment or
trial change. The checkout's linked project (`jrkzdttophnmkxjoyioo`) was not
used. Nothing was pushed.

## What changed

| Setting | Before | After |
| --- | --- | --- |
| `friend_runtime_v1.commands_only` | off | **on** |
| `challenge_policy_runtime_v1.allowlist_enforced` | off | **on** |
| `challenge_policy_runtime_v1.account_mode` | off | **on** |
| `challenge_policy_runtime_v1.links_enabled` | off | off |
| `challenge_policy_allowlist_v1` | `personal_steps_goal_v1`, `personal_distance_goal_v1` | the same two, plus `friend_steps_goal_v1`, `friend_exercise_goal_v1`, `friend_distance_goal_v1`, `friend_timed_goal_v1` |

A read-only pre-check found all four friend pairs valid under the allowlist's
constraints and none already listed, and no triggers on the three settings
tables.

## What stayed the same

Read back at 14:54 UTC before and 15:07 UTC after:

- **Private trial:** on, device verification off, one enrolled account.
- **Real activity:** admission, ingestion and processing on.
- **Friend requests:** daily limit 20.
- **Commitments (D144):** runtime switch on, last changed 03:27 UTC today,
  before this task.
- **Accounts:** one account, one 21+ confirmation, no friendships.
- **Migrations:** 103 recorded.
- **Owner goals:** the six personal records below matched field for field:
  status, revision, agreement version, agreement and consent digests, the
  member's target (compared by hash), dates and configuration. A final read
  at 15:20 UTC matched the before snapshot exactly (fingerprint
  `680e1022d1b083d5f7782037a108461d`, computed on hosted and from the saved
  snapshot). Targets are left out of this public record.

| Goal (UTC window) | Status | Revision | Agreement digest |
| --- | --- | --- | --- |
| Steps, Sep 24 05:00 – Oct 1 05:00 | active | 2 | `59000be90865…` |
| Outdoor runs, Sep 24 05:00 – Oct 1 05:00 | active | 2 | `dd2b764c7bdd…` |
| Steps, Sep 27 05:00 – Oct 4 05:00 | scheduled | 1 | `9d57556ebc8c…` |
| Steps, Sep 24 05:00 – Oct 1 05:00 | void | 4 | `08379189495d…` |
| Steps, Sep 22 07:00 – Sep 29 07:00 | void | 4 | `9b8233928ca5…` |
| Steps, Sep 22 07:00 – Oct 6 07:00 | void | 4 | `62258cb91547…` |

Since the [Phase 5 migration receipt](2026-09-23-friends-phase-5-migrations.md),
one of the three September 24 goals was left at 03:43 UTC today and is void,
and the scheduled September 27 Steps goal was saved a minute later. Neither
happened in this task. Later, during the phone check, the owner left the
active September 24 Steps goal; see [Phone](#phone).

## What the owner's account is offered

`challenge_availability_v1`, called as the enrolled owner through their live
session (a read, in a transaction that wrote nothing):

- **Before, 14:58 UTC:** restricted, admission on, account allowed, account
  mode, links and community closed; Personal Steps and Personal Outdoor runs.
- **After, 15:08 UTC:** the same, plus the four friend goals: Steps, Activity
  minutes (`apple_watch_exercise_credit_v2`), Running distance and Timed run.

## Can a friend who isn't enrolled take part?

**No, not while the private trial is on.** Hosted has only one account, since
sign-up hasn't been opened, so there is no second account there to try. The check ran on a
disposable local stack configured like hosted after this change: build 1
settings, real activity on, the trial on with device verification off, one
enrolled fictional owner and one fictional friend who is 21+ but not enrolled.

| Step | Trial on | Trial off (local only) |
| --- | --- | --- |
| Friend's availability | lists all six goals, `account_allowed` false | — |
| Friend request and accept | works | — |
| Friend's activity check (Steps readiness) | refused, HTTP 403 | works |
| Friend creates a friend goal | refused, `challenge_private_trial_account_required` | works |
| Owner creates a friend goal and invites the friend | works | — |
| Friend sets their own target | refused, `challenge_private_trial_account_required` | works |
| Owner locks the roster | refused, `challenge_incomplete_roster` | works |
| Both agree | not reached | both agree |

The trial rules on hosted are the ones tested: the 210 `challenge_*` and
`friend_*` function definitions in `app` and `public` hash to the same value
on hosted and on the local stack (`ec4458ad3de9f603bf130a0b6e8bcfe7`),
including the trial checks, admission and the row guard, and the row guard's
seven trigger definitions match too. A read-only hosted check at 15:08 UTC
returned `true` for the enrolled owner and `false` for a made-up account ID.

Friends can take part only after Apple sign-up opens and either the trial is
turned off or each friend's account is enrolled. The trial was not changed;
that is the owner's decision.

## Local checks

- **Build:** the app, `GameTimeTests` and `GameTimeUITests` compiled for the
  iPhone simulator at `b86a006` with Xcode 27.0 (27A5237l), with no errors.
  PR #27 needed no compile fixes.
- **Unit tests:** `ChallengeCreationDraftTests` 13/13 and
  `ChallengeCreationFlowTests` 13/13 passed on an iPhone 17 Pro, iOS 27.0.
- **`LiveDesignUITests`:** 14/15 passed. The failure,
  `testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize`, fails
  the same way on `e5b283d`, main just before PR #27: "Unblock Casey Wu" isn't
  found on Blocked people at default size, Remove isn't found on a friend's
  actions at the largest size, and the audit reports low contrast on
  "Accepted your request" in the Home action rows at the largest size. It is
  not a PR #27 regression.
- **Settings rehearsal:** `scripts/friends-local-verify.sh` passed all 139
  checks at `b86a006`, which now includes D143 and D144, with these settings
  and the trial off.

## Phone

Installed at 16:33:31 UTC, once the owner was home with the iPhone unlocked.
An earlier attempt at about 15:15 UTC, while the owner was away, could not
reach the phone and changed nothing.

- **Build:** GameTime Staging 0.8.1 (926.26.1), built from `b86a006` with the
  `GameTime-Staging` scheme and Staging configuration, not Debug. Bundle
  `com.mjenkins.gametime.staging`, team `87Z29RTC26`, backend
  `lyushhqoednheqwzsmxh`, challenges and account mode on, HealthKit and
  development App Attest entitlements. The iPhone-product guard passed. The
  executable's SHA-256 is
  `ec92749aa582a7a460f4ca52301cd7c48eb884eb50dd82009224ee261fb9fc96`, and
  Info.plist's is
  `6861e4b24017ad350ee0d3202e109975dbfa3be8bc8ea25d5fc4c760751a2012`. A copy
  stays out of Git at `build/friends-build1-staging-20260926-926.26.1/`.
- **Install:** in place over GameTime Staging 0.8.1 (1), keeping the app's
  data. The phone then reported 0.8.1 (926.26.1) for the same bundle.
- **Launch:** opened with no arguments, signed in, on Home, with Home,
  Challenges and You along the bottom.

The owner tapped through while this Mac captured the screen with `devicectl`
and read each capture with macOS text recognition. The captures show personal
data and stay outside Git.

- Starting a challenge opened on **"Who's it for?"** with **Personal goal**
  ("Just for you") and **Goals with friends** ("Each person chooses a goal",
  preselected), and the steps Who, Goal, Challenge, Friends. No leaderboard was
  offered.
- The next step, "What's your goal?", offered Steps, Activity minutes, Running
  distance and Timed run.
- None of the nine captures (Home, a goal and its full rules, You, Challenges
  and three creation steps) showed "saved action" or "stop waiting". Neither
  phrase appears in the app source at `b86a006` outside the tests.

At 16:35:13 UTC, during this session, the owner left the active September 24
Steps goal from the phone, and it is now void. That was the owner's choice. A
read at 16:36 UTC found the other five goal records identical to the before
snapshot, including the active Outdoor runs goal and the Steps goal that
starts September 27.

An automated phone check would need an Apple account in Xcode to sign its
test runner; none is signed in on this Mac.

## Observed, not changed

- **Migration history.** Hosted records the D144 migration as
  `20260926024624_challenge_personal_commitment_v1`, not the repo's
  `20260925000000`, and has no `20260923070000_retire_charity_v1`. Its 103
  entries against the repo's 104 would make a later `db push` try both; the
  commitment one would fail on objects that already exist. The history needs
  repair before the next push.
- **Commitment switch.** D144 records the switch off when its migration was
  applied; it has been on since 03:27 UTC today.

## Not done

Turning the trial off, Apple sign-up, `delete-account`, support grants,
closing legacy grants and the backup and pause questions remain in Phase 5 of
the [friends plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md).

The full readbacks, which name account and goal IDs, and the local check script
and its results stay on the owner's Mac, outside Git, in
`tmp/friends-build1-2026-09-26/`.
