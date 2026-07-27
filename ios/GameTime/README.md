# GameTime product app

`GameTime.xcodeproj` is the production-shaped M8 iOS target. It is independent
from `../GameTimeConformance`, which remains the focused M6.5 App Attest
engineering harness.

## Targets and configurations

- `GameTime`: iOS 18, Swift 6, SwiftUI, `GameTimeCore`, and the exact
  `supabase-swift` version recorded in `Package.resolved`.
- `GameTimeTests`: state, routing, DTO, validation, configuration, and client
  boundary tests.
- `GameTimeUITests`: signed-out/onboarding roots, four-tab navigation, social
  and duel mutations, fixture states, Dynamic Type, labels, and Reduce Motion.
- `Debug`: live clients by default; pass `--fixture-mode` for deterministic
  local and UI-test data.
- `Staging`: live clients, contest mutations enabled, and a persistent
  `Test environment—no real pledge` banner.
- `Release`: live clients, with contest creation and acceptance locked until
  the evidence/App Attest slice is complete.

Debug fixture code is guarded by `#if DEBUG`; Release cannot route to it.

## Restart-safe duel retry

Before the first contest-creation RPC attempt, the app atomically saves one
versioned pending duel for the authenticated actor under Application Support.
The file uses complete data protection, is excluded from backup, and preserves
the request UUID plus canonical millisecond timestamps as exact `Date` bit
patterns so a relaunched retry hashes to the same immutable backend payload.
Existing records accept only identical terms and monotonic attempt updates.

An offline, cancelled, or ambiguous response leaves the record in place. The
Challenges tab restores it only for the same actor and requires an explicit
manual retry; the app never retries a mutation on its own. Starting another duel
is blocked until the server returns a confirmed contest UUID or the user accepts
the warned discard path. Sign-out detaches the record from UI state without
making it visible to another actor.

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
