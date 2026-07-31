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
  and challenge mutations, fixture states, Dynamic Type, labels, and Reduce
  Motion.
- `Debug`: live clients by default; pass `--fixture-mode` for deterministic
  local and UI-test data.
- `Staging`: live clients, contest mutations enabled, and a persistent
  `Test environment—no real pledge` banner. The signed-out root and You tab
  can enter an isolated on-device demo without changing the live account.
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

## Installed configuration

Every product build includes `Configuration/PublicClient.xcconfig`, containing
the hosted Supabase URL and its low-privilege `sb_publishable_…` mobile-client
key. A clone, archive, TestFlight build, or directly installed build therefore
starts without machine-specific configuration.

The public key is not an application secret: it is recoverable from every
installed mobile binary and access remains controlled by Supabase Auth, grants,
and row-level security. Never place Apple secrets, `sb_secret_…` or
service-role keys, database credentials, or Edge Function secrets in an app
configuration.

Debug developers may create the gitignored
`Configuration/LocalOverrides.xcconfig` to point only their Debug build at a
local or isolated project:

```xcconfig
// $() inserts the second slash without starting an xcconfig comment.
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY = sb_publishable_local_key
```

Staging and Release deliberately ignore local overrides so an installed build
cannot depend on the build machine's private files. The app target also rejects
the build if the URL/key is invalid or its bundle ID no longer matches the
Apple client identity accepted by Supabase Auth.

## Run and test

Open `GameTime.xcodeproj`, select `GameTime-Staging` for the connected product
or `GameTime` for Debug/Release work, and choose an iPhone Simulator or a
provisioned device. All configurations use the currently provisioned
`com.mjenkins.gametime.staging` Sign in with Apple identity.

External testers should receive a signed/TestFlight build. They need no source
checkout, local configuration, Supabase access, or Apple developer-team access.

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
