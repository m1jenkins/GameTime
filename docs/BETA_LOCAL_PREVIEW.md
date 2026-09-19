# Local Signal preview

Run from `/Users/user/Documents/GitHub/GameTime` on `main`. This opens the newer
friend/personal ChallengeV1 shell with fictional local accounts. It does not use
Demo Mode or connect real Health data. Ordinary signed-in transport is now
configurable through the shared app session; checked-in configuration remains
off. Amounts are nonredeemable simulation.

## Choose owned resources

The launcher accepts `GAMETIME_BETA_PREVIEW_PROJECT`, `PORT_BASE`, `STACK`,
`SIMULATOR` and `APP`, each with the `GAMETIME_BETA_PREVIEW_` prefix.
Select an existing disposable stack with the committed migrations applied, an
available Simulator and a Debug Simulator build. These variables select resources;
they do not provision a stack or authorize resetting another database.

The following b7 stack and Cobalt review Simulator were present during the
September 12 cleanup. Recheck their availability before use. The legacy b7 defaults
remain compatible with existing native tests and the operator helper.

```sh
cd /Users/user/Documents/GitHub/GameTime
export GAMETIME_BETA_PREVIEW_PROJECT=gametime-finish-b7
export GAMETIME_BETA_PREVIEW_PORT_BASE=58320
export GAMETIME_BETA_PREVIEW_STACK=/tmp/gametime-finish-b7-stack
export GAMETIME_BETA_PREVIEW_SIMULATOR=F7C22A78-F71A-4071-B122-55E68F8E5EF1
export GAMETIME_BETA_PREVIEW_APP=/tmp/gametime-main-preview-derived/Build/Products/Debug-iphonesimulator/GameTime.app
xcrun simctl list devices booted
supabase status --workdir "$GAMETIME_BETA_PREVIEW_STACK"
```

API, database and controller ports are `PORT_BASE + 1`, `+ 2` and `+ 19`.
The launcher verifies that the stack's actual identity and loopback endpoints
match the selected project. Do not run a second controller against that stack.
If the selected stack is stopped, start only that known stack without resetting
it. If it is absent, prepare a separate owned stack using the local operating
instructions before launching; do not substitute the original development stack.

Build the local scheme into the chosen output directory:

```sh
xcodebuild build -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTimeBetaLocal -configuration Debug \
  -destination "platform=iOS Simulator,id=$GAMETIME_BETA_PREVIEW_SIMULATOR" \
  -derivedDataPath /tmp/gametime-main-preview-derived CODE_SIGNING_ALLOWED=NO
scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" serve
```

Keep the foreground command running. It creates seven fictional accounts, prints
usernames and fills the local sign-in screen for account 1. Tap **Sign in** and
confirm age if asked. It does not submit challenge consent. Credentials stay in a
temporary mode-0600 manifest; do not copy them into source or documentation.

Custom preview projects use a separate manifest named
`tmp/beta-native-smoke-<project>.json`. The b7 default and native test runner retain
`tmp/beta-native-smoke.json`, which existing native/UI tests and the b7 operator
helper expect. The native runner forwards its expected loopback controller URL to
Xcode's test runner. Only one native smoke controller can use a checkout at once.

## Review the journey

Use the same environment settings in a second terminal in the main checkout:

```sh
scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" accounts
scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" open --actor 2
scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" open --actor 1
```

1. As account 1, create a friend goal and propose a target. Invite account 2 by its
   exact printed username.
2. Switch to account 2, sign in, confirm age, open the invitation and propose its
   own target. Switch back to account 1 and select the roster.
3. Lock the agreement. Each account must independently read and consent before
   it becomes scheduled. Account switching never submits consent.
4. Try a friend leaderboard, where no goal field is required, and a personal goal.
   Navigate Home, Challenges and You. All four activity options are fictional.
5. Use `latest --actor 1` to obtain the account's most recently created challenge
   ID, including a scheduled personal goal. The launcher's `clock`, `progress`
   and `process` commands advance only fictional scenarios; inspect their
   `--help` and the selected agreement dates before using them.

## Fast one-day lifecycle walkthrough

Use a fresh preview with no other open challenge for its seven fictional
accounts. In the app, sign in as account 1 and confirm age. Create a **Personal
goal → Steps** with **October 3, 2026**, **1 day**, **UTC**, **10,000 steps**, and
**$1 simulated**. Read the full agreement, turn on its consent toggle, and tap
**Start my personal goal**. This schedules the full October 3 UTC calendar day,
from `2026-10-03T00:00Z` through (but not including) `2026-10-04T00:00Z`.
The preview starts at October 1 noon UTC, so the start date is two local
calendar days after creation. The CLI never submits agreement consent.

In a second terminal with the same preview environment variables:

```sh
challenge_id=$(scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" latest --actor 1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
scripts/beta-preview.py --owned-project "$GAMETIME_BETA_PREVIEW_PROJECT" lifecycle --challenge "$challenge_id" --actor 1
```

The command checks the saved one-day window and consent before changing the
fictional clock. It reuses `clock`, `progress`, and `process` to move from
scheduled to active, save 10,001 steps, enter syncing, and save a downward
correction to 9,999 within the end +48-hour correction window. It deliberately
processes the provisional notice eight hours after its operational due time;
the account then files a review through its authenticated local command 47
hours after that *actual* notice. Processing at the 48-hour notice deadline
must leave the result open while the review is unresolved. The existing
fictional independent operator control upholds it within 72 hours of filing,
then processing records the final nonredeemable simulated result. The CLI
checks each revision, deadline, review and final result and prints a short
timeline. It does not shorten the product day, scheduling lead, correction,
notice, review or resolution rules. A new challenge is required for each run;
saved records are append-only.

The [September 19 local run](../outputs/reports/2026-09-19-preview-one-day-lifecycle.md)
records the actual headless backend verification and its limits.

The prior Cobalt review recorded these journeys interactively. Consult its
screens and the [current baseline](WORKING_BASELINE.md) for the limits of that
record. Consolidating source does not establish new physical, human or hosted
acceptance. The b7-specific operator walkthrough is retained in Git history;
[local operations](BETA_OPERATIONS_LOCAL.md) owns current permission boundaries.

## Stop the preview

Press **Ctrl-C** in its `serve` terminal. The launcher closes fixture gates,
revokes only its preview sessions and removes its credential manifest. Historical
and fictional database records remain. It does not stop other stacks or erase a
Simulator. Starting another preview creates a fresh fictional cohort.

## Ordinary app connection and its local substitute

`GAMETIME_CHALLENGE_V1_ENABLED` defaults to `NO` in `PublicClient.xcconfig` and
is read from each app configuration's Info.plist. For an explicitly approved
Beta target, `YES` selects `SupabaseChallengeV1Client` using the **same** SDK,
`SUPABASE_URL`, publishable key and session as Apple sign-in and profiles.
No second account or challenge-specific credential is needed. Select the actual
target through the existing hosted-settings worksheet; the historical hosted
project in `PublicClient.xcconfig` is not selected for Beta by this change.

Transport accepts an HTTPS origin without credentials, path, query or fragment
(standard HTTPS port only). Debug/Staging may also use explicit loopback with a
port; Release rejects that development transport. Missing/invalid opt-in remains
unavailable. This switch does not change backend admission, source readiness,
community publication, fixture, processing, ingestion or money gates. Server
pauses retain readable history, recovery, review and exits. Expired sessions use
the shared refresh helper; replaced/revoked sessions clear challenge content.

Opaque invitation intent belongs to AppModel above authentication and survives
sign-in cancellation/failure, ordinary sign-out, account changes and relaunch.
Redemption remains deliberate and actor-bound. The existing custom preview link
and pasted invitation input are retained; approved HTTPS domains, AASA,
entitlements and real Apple identity verification are still separate work.

The existing native controller now accepts `--native-only --native-phase app`
for the shared-session AppModel journey and focused regressions, or
`--touch-only app` for the visible ordinary Signal root. Pass unique
`--derived-data` and `--evidence-dir` paths along with the owned resource
variables above. In the **new disposable stack only**, enable email login for
fictional password sign-in (`auth.email.enable_signup = true`); repository and
hosted Auth settings stay Apple-only. Never apply this substitute setting to a
hosted target. The controller confirms fictional emails through its local admin
API; no messages or providers are used.

The visible check launches with Debug-only `--authenticated-app-local`, reusing
`GAMETIME_BETA_LOCAL_URL`, `KEY`, `EMAIL` and `PASSWORD`. It mounts ordinary
RootView/AppModel/Signal and uses the production challenge-service selector;
only sign-in, Health and historical supporting services are substituted. It
requires loopback and a publishable key, disables Health reads/background
registration and contacts real local Auth/PostgREST. It does not use
`ChallengeLocalLaunchView`. Do not combine the two launch flags. The substitute
is absent from Staging/Release and proves no Apple/provider/hosted acceptance.
