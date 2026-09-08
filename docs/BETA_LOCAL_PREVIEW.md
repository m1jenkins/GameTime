# Morning local preview — b7

This is the new Beta shell on fictional local accounts. All stakes are simulated
and nonredeemable; no Health data is scored. Legacy default navigation is intact.
Physical-source evidence, human acceptance and distribution are still pending.

## Launch

Use this worktree, not either primary checkout:

```sh
cd /Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta
scripts/beta-preview.py --owned-project gametime-finish-b7 serve
```

Keep that command in its foreground terminal. It makes seven fictional accounts,
prints their usernames, starts a loopback controller on 58339, installs the Debug
build on **only** Simulator `72A3249A-2DE0-4695-AF41-DCD2743B4666`, and opens the
local sign-in screen with account 1 filled in. Tap **Sign in**. Credentials are in
a temporary mode-0600 manifest and process environment, not in these instructions.
Do not run this alongside a native, operator-smoke or concurrency test controller.

The already-created stack is `/tmp/gametime-finish-b7-stack`, project
`gametime-finish-b7`, API 58321 / DB 58322. If its services are stopped, first check
`supabase status --workdir /tmp/gametime-finish-b7-stack`, then start **only** it:

```sh
DO_NOT_TRACK=1 supabase start --workdir /tmp/gametime-finish-b7-stack \
  -x edge-runtime,studio,imgproxy,mailpit,storage-api,vector
```

No reset is needed. Never use an unscoped reset or touch the original 5432x stack.
If the owned Simulator is shut down, boot exactly that UUID with `xcrun simctl boot`.
The reusable Debug build lives at
`/tmp/gametime-finish-b7-derived/Build/Products/Debug-iphonesimulator/GameTime.app`.
Rebuild locally if necessary:

```sh
xcodebuild build -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTimeBetaLocal -configuration Debug \
  -destination 'platform=iOS Simulator,id=72A3249A-2DE0-4695-AF41-DCD2743B4666' \
  -derivedDataPath /tmp/gametime-finish-b7-derived CODE_SIGNING_ALLOWED=NO
```

## Try a two-person steps goal

1. In **Challenges**, confirm age, create the default friend steps lobby, and open
   it. Propose **10000** steps. In another terminal, run `accounts` (below), copy
   account 2's username into **Exact friend username**, then **Invite friend**.
   Use `latest` now to obtain this lobby's UUID for the later clock commands.
2. Run `open --actor 2`, tap Sign in and confirm age. Open the lobby and propose
   **10001**. Switch back to account 1 and select account 2 for the roster.
3. Tap **Lock in roster and goals**. Each account must separately open the full
   agreement, turn on **I have read the complete rules and agree**, then agree.
   Merely opening or signing in never submits consent. The challenge becomes
   scheduled only after both agree. Reopening terms requires both again.
4. Advance the fictional clock and add progress using the commands below. Refresh
   in the app to see exact 12,000-step totals. Then lower account 2 to 100 during
   the correction period. No chart point is fabricated or interpolated.
5. Process a deliberately delayed result notice. Account 2 can ask for a review
   from the detail page. The notice grants a full 48 hours from its actual time.
   Use the assigned independent operator workflow below to inspect and resolve it.
6. Advance to the end of that review window and process. Home/Challenges history
   shows the exact final result. For the default $20 simulated entry and these
   confirmed values, account 1 receives a $40 simulated return and account 2 $0.
   Nothing can be paid out or redeemed.

Run these from a second terminal in the same worktree:

```sh
scripts/beta-preview.py --owned-project gametime-finish-b7 accounts
scripts/beta-preview.py --owned-project gametime-finish-b7 latest --actor 1
scripts/beta-preview.py --owned-project gametime-finish-b7 open --actor 2
scripts/beta-preview.py --owned-project gametime-finish-b7 open --actor 1
```

Set `CHALLENGE_UUID` to the returned lobby ID (do not use an old run's ID):

```sh
CHALLENGE_UUID='PASTE_THIS_PREVIEW_LOBBY_UUID'
scripts/beta-preview.py --owned-project gametime-finish-b7 clock --to 2026-10-05T12:00:00Z
scripts/beta-preview.py --owned-project gametime-finish-b7 process --challenge "$CHALLENGE_UUID"
scripts/beta-preview.py --owned-project gametime-finish-b7 progress --challenge "$CHALLENGE_UUID" --actor 1 --value 12000
scripts/beta-preview.py --owned-project gametime-finish-b7 progress --challenge "$CHALLENGE_UUID" --actor 2 --value 12000
scripts/beta-preview.py --owned-project gametime-finish-b7 clock --to 2026-10-11T12:00:00Z
scripts/beta-preview.py --owned-project gametime-finish-b7 progress --challenge "$CHALLENGE_UUID" --actor 2 --value 100
scripts/beta-preview.py --owned-project gametime-finish-b7 clock --to 2026-10-20T12:00:00Z
scripts/beta-preview.py --owned-project gametime-finish-b7 process --challenge "$CHALLENGE_UUID"
```

After filing the review in the app, set `OPERATOR_UUID` to account 7's UUID from
`accounts`. Grant scope, read its assigned case, and set `REVIEW_UUID` to that case:

```sh
OPERATOR_UUID='PASTE_ACCOUNT_7_UUID'
scripts/beta-operator.py --owned-project gametime-finish-b7 grant \
  --actor "$OPERATOR_UUID" --challenge "$CHALLENGE_UUID" \
  --capability review --expires 2026-10-25T12:00:00Z
scripts/beta-operator.py --owned-project gametime-finish-b7 --local-actor 7 \
  cases --challenge "$CHALLENGE_UUID"
REVIEW_UUID='PASTE_REVIEW_UUID'
REQUEST_UUID="$(uuidgen)"
scripts/beta-operator.py --owned-project gametime-finish-b7 --local-actor 7 \
  resolve --challenge "$CHALLENGE_UUID" --review "$REVIEW_UUID" \
  --decision upheld --request-id "$REQUEST_UUID"
scripts/beta-preview.py --owned-project gametime-finish-b7 clock --to 2026-10-22T12:00:00Z
scripts/beta-preview.py --owned-project gametime-finish-b7 process --challenge "$CHALLENGE_UUID"
```

`upheld` is appropriate for these explicit fictional values. For a disputed result
that cannot be established, follow the runbook's conservative exclusion rule.
Changing an allocation issues a new notice with another full review window.

## More things to try

- Invite accounts 2–6 and repeat roster/targets/consent for a six-person journey.
- Try all four activities and both friend formats; leaderboards have no goal field.
  Personal creation previews one private agreement and requires its own consent.
- Use **Leave** before finality, or cancel a lobby before it starts. Review the
  explanation before confirming; your simulated entry returns. Report/block is
  available from a shared participant's controls. Own history stays available.
- Issue/revoke an invitation in the lobby; opening its opaque link does not grant
  access until authenticated redemption and age confirmation. Account 7 has no
  pre-existing friendship with accounts 1–6.
- Run `lose-next-response`, then take one app action. It commits but returns a
  deliberate connection failure. **Retry saved action** retrieves the same result;
  **Stop waiting** checks completion or prevents a late request from committing.
  Switch accounts and return to verify the saved action stays with its owner.
- Run a `clock` command with `--pause-admission --pause-processing`. New admission
  stops, while safe reads, exits, reviews and exact recovery still work. Omit the
  pause flags in another clock command to resume this fictional controller.
- **You → Privacy and terms** explains local data and simulated stakes. External
  support, deletion policy, real sources and distribution remain unaccepted.

## Cleanup and return to historical navigation

Press **Ctrl-C** in the `serve` terminal. It disables fixture/admission/processing /
community discovery, revokes only this preview's sessions, removes its credential
manifest and keeps all historical/fictional records. It leaves the owned database
running and touches no pre-existing stack or Simulator. The app then rejects the
revoked session; another `serve` creates a fresh cohort.

To open historical default navigation without the local opt-in, terminate and
launch the app on this owned Simulator with no Beta argument. Do not sign in to a
hosted account during local verification. No real-source permission or device
acceptance can be inferred from any of these fictional Simulator journeys.
