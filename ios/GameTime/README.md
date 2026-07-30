# GameTime product app

`GameTime.xcodeproj` is the production-shaped M8 iOS target. It is independent
from `../GameTimeConformance`, which remains the focused M6.5 App Attest
engineering harness.

## Targets and configurations

- `GameTime`: iOS 18, Swift 6, SwiftUI, `GameTimeCore`, and the exact
  `supabase-swift` version recorded in `Package.resolved`.
- `GameTimeTests`: state, routing, DTO, validation, configuration, and client
  boundary tests, including HealthKit source merging, App Attest registration,
  and exact-byte activity retry behavior.
- `GameTimeUITests`: signed-out/onboarding roots, four-tab navigation, social
  and challenge mutations, fixture states, explicit Staging activity controls,
  Dynamic Type, labels, and Reduce Motion.
- `Debug`: live clients by default; pass `--fixture-mode` for deterministic
  local and UI-test data.
- `Staging`: live clients, contest mutations enabled, and a persistent
  `Test environment—no real pledge` banner. The signed-out root and You tab
  can enter an isolated on-device demo without changing the live account.
  Accepted active steps challenges expose explicit HealthKit authorization and
  sync backed by product App Attest and an account-isolated exact-byte queue.
- `Release`: live clients, with contest creation and acceptance locked until
  the evidence/App Attest slice is complete.

Fixture code is guarded by `#if DEBUG || STAGING`; Release cannot compile or
route to it.

## On-device demo

In a Debug or Staging build, open **You → Open demo mode**. If the live account
is signed out, **Try demo mode** is also available on the sign-in screen.

Demo mode keeps Supabase and the Apple-authenticated staging account untouched.
It uses a separate in-memory model, displays a persistent teal banner, and
resets when you exit. In Friends, search `david1` or `david2` and tap **Add**.
The synthetic friend accepts immediately so that person is available in the
challenge creator. This shortcut is deliberately local and is not evidence for
the two-user staging acceptance gate.

## Atomic multi-friend challenges and restart-safe retry

Before the first contest-creation RPC attempt, the app atomically saves one
versioned pending challenge for the authenticated actor under Application
Support. Challenge creation explicitly selects 1–19 accepted friends, reviews
the complete closed roster, and sends the canonical UUID array through one
`create_contest_with_invites_v1` RPC with
`max_participants = invitees + 1`. The client never loops over invitees, so it
cannot expose a partial-submission state.

The file uses complete data protection, is excluded from backup, and preserves
the request UUID plus canonical millisecond timestamps as exact `Date` bit
patterns so a relaunched retry hashes to the same immutable backend payload.
Envelope version 2 stores the complete invitee array. Loading a version-1
single-invite saved duel migrates it atomically in place while preserving its
actor, request identity, attempt metadata, invitee, and timestamp bit patterns.
Existing records accept only identical terms and monotonic attempt updates;
unsupported or malformed versions fail closed.

An offline, cancelled, or ambiguous response leaves the record in place. The
Challenges tab restores it only for the same actor and requires an explicit
manual retry; the app never retries a mutation on its own. Starting another
challenge is blocked until the server returns a confirmed contest UUID or the
user accepts the warned discard path. Sign-out detaches the record from UI
state without making it visible to another actor.

## Explicit Staging activity sync

For an accepted, active steps challenge, Staging exposes **Enable Activity**
and **Sync Activity**. Reads are user initiated. The app plans only complete
hours inside the immutable challenge window, asks HealthKit statistics to merge
overlapping Apple-device sources, and excludes manual, unknown, and third-party
contributions from this first trusted slice.

Before upload, the app persists the exact metric body and App Attest assertion
under the authenticated actor. Retryable or ambiguous outcomes survive
relaunch and require another explicit tap; another account cannot see or send
the saved batch. Debug and Release keep activity sync disabled. Background
delivery, workouts, Core Location, and physical two-account acceptance remain
open; follow the runbook linked below before using real step data.

## Safe configuration

The app accepts only a Supabase URL and a current `sb_publishable_…` key. It
fails closed when either is missing or malformed and explicitly rejects
`sb_secret_…` and legacy service-role JWTs.

Create the gitignored `Configuration/Secrets.xcconfig`:

```xcconfig
// $() inserts the second slash without starting an xcconfig comment.
SUPABASE_URL = https:/$()/abcdefghijklmnopqrst.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_replace_me
```

Do not place Apple secrets, service-role keys, database credentials, or Edge
Function secrets in an app configuration.

## Run and test

Open `GameTime.xcodeproj`, select the `GameTime-Staging` scheme for connected
staging or `GameTime` for Debug fixtures, and choose an iPhone Simulator.

```sh
xcodebuild \
  -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime-Staging \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The two-account acceptance procedure and external Apple prerequisites are in
`../../docs/M8_1_STAGING_ACCEPTANCE.md`.
