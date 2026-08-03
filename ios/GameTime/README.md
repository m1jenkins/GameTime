# GameTime product app

`GameTime.xcodeproj` is the production-shaped Personal V1 iOS target. It is independent
from `../GameTimeConformance`, which remains the focused M6.5 App Attest
engineering harness.

## Targets and configurations

- `GameTime`: iOS 18, Swift 6, SwiftUI, `GameTimeCore`, and the exact
  `supabase-swift` version recorded in `Package.resolved`.
- `GameTimeTests`: Personal terms, recovery, activity, state, routing, DTO,
  validation, configuration, retained-legacy, and client-boundary tests.
- `GameTimeUITests`: signed-out/onboarding roots, the three-tab Personal
  Daybreak journey, daily and cumulative creation, every test commitment,
  recovery and fixture states, Dynamic Type, labels, and Reduce Motion.
- `Debug`: live clients by default; pass `--fixture-mode` for deterministic
  local and UI-test data.
- `Staging`: live clients, test-only Personal mutation and Health activity
  enabled, and a persistent **Test commitment — no money will be charged.**
  banner. The signed-out root and You tab can enter an isolated fixture model
  without changing the live account.
- `Release`: live clients, with Personal and retained social contest mutations
  locked.

Fixture code is guarded by `#if DEBUG || STAGING`; Release cannot compile or
route to it.

## Personal fixture journey

In a Debug or Staging build, open **You → Open demo mode**. If the live account
is signed out, **Try demo mode** is also available on the sign-in screen. The
isolated model presents only Today, Challenges, and You and resets on exit.

UI tests launch the same deterministic boundary with `--fixture-mode`. Bounded
arguments cover `--fixture-loading`, `--fixture-empty`, `--fixture-offline`,
`--fixture-activity`, `--fixture-personal-no-diagnostic`,
`--fixture-personal-hold`, and `--fixture-personal-pending`. These states do not
touch Supabase and do not prove hosted, two-user, HealthKit, or App Attest
behavior.

## Personal restart-safe retry

Before the first Personal creation RPC attempt, the app saves one protected,
versioned request for the authenticated actor under Application Support. It
preserves the request UUID, cadence, whole-step target, test commitment,
timezone, owner, and exact retry metadata. An offline, cancelled, or ambiguous
response leaves the record in place; a relaunch restores it only for the same
actor and requires an explicit manual retry.

If refresh discovers that the server already created that exact pending
challenge, the saved request remains resumable until the idempotent response is
confirmed and the local record is cleared. A genuinely different request stays
blocked while an open challenge exists. Corrupt, changed, cross-account, or
unsupported records fail closed.

The older social v1/v2 pending envelope and multi-friend creation code remain
only for V2/regression compatibility. Personal records never decode or retry as
social requests, and the normal V1 shell exposes no social route.

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
  -project ios/GameTimeConformance/GameTimeConformance.xcodeproj \
  -scheme GameTimeConformance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

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

The full Personal proof layers, observed local counts, and external Apple
prerequisites are in `../../docs/PERSONAL_V1_ACCEPTANCE.md`. The repository-local
simulator layer passes 103 product unit tests, 10 product UI tests, 10 conformance
tests, and all three unsigned simulator configurations. Simulator proof does not
substitute for the signed physical-device or hosted acceptance layers.
