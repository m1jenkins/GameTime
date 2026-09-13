# Local Cobalt preview

Run from `/Users/user/Documents/GitHub/GameTime` on `main`. This opens the newer
friend/personal ChallengeV1 shell with fictional local accounts. It does not use
Demo Mode or connect real Health data. Normal signed-in challenge transport stays
closed. Amounts are nonredeemable simulation.

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
5. Use `latest --actor 1` to obtain a new challenge ID. The launcher's `clock`,
   `progress` and `process` commands advance only fictional scenarios; inspect
   their `--help` and the selected agreement dates before using them.

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
