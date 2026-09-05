# GameTime product app

> **Product direction — September 4, 2026.** This README describes the
> current Personal app. Friend duels and personal performance commitments are
> adopted future work in [BUSINESS_MODEL.md](../../docs/BUSINESS_MODEL.md) and
> [PLAN.md](../../PLAN.md). The shell still blocks legacy social routes; new
> products require separate models, consent and routes. No live money is enabled.

`GameTime.xcodeproj` is the production-shaped Personal iOS target. New and
migrated open challenges use automatic Apple Health snapshot v2. It is
independent from `../GameTimeConformance`, which remains the focused legacy and
generic M6.5 App Attest engineering harness rather than a Personal-v2 gate.

## Targets and configurations

- `GameTime`: iOS 18, Swift 6, SwiftUI, `GameTimeCore`, and the exact
  `supabase-swift` version recorded in `Package.resolved`.
- `GameTimeTests`: Personal terms, automatic Health snapshots, cache/upload,
  recovery, state, routing, DTO, validation, configuration, retained-legacy,
  and client-boundary tests.
- `GameTimeUITests`: signed-out/onboarding roots, the three-tab Personal
  Daybreak journey, daily and cumulative creation, every test commitment,
  recovery and fixture states, Dynamic Type, labels, and Reduce Motion.
- `Debug`: live clients by default; pass `--fixture-mode` for deterministic
  local and UI-test data.
- `Staging`: live clients, test-only Personal mutation and automatic Health
  progress enabled, and a persistent **Test commitment — no money will be charged.**
  banner. The signed-out root and You tab can enter an isolated fixture model
  without changing the live account.
- `Release`: live clients; Personal creation is allowed only through the
  explicit Stripe sandbox configuration and backend admission gates. Internal
  test-only Personal and retained legacy social mutations remain locked; this
  is not proof of a hosted or distribution-ready sandbox.

Fixture code is guarded by `#if DEBUG || STAGING`; Release cannot compile or
route to it.

## Personal fixture journey

In a Debug or Staging build, open **You → Open demo mode**. If the live account
is signed out, **Try demo mode** is also available on the sign-in screen. The
isolated model presents only Today, Challenges, and You and resets on exit.
Its account and challenge data stay local, while step progress is read from
Apple Health on the device. “Start right now” and the detail screen's “Sync
now” use the same behavior as main mode, so today's real steps count in either
journey.

UI tests launch the same deterministic boundary with `--fixture-mode`.
Snapshot-v2 fixtures cover automatic live progress, cache/server fallback,
stale retention, no data, grace, offline upload, and frozen history. Historical
diagnostic/hold/activity fixtures may remain only when explicitly labelled v1.
Fixtures do not touch Supabase and automated fixture runs do not prove hosted,
two-user, Apple Health, observer, Watch, or locked-device behavior.

## Personal restart-safe creation

Before the first Personal creation RPC attempt, the app saves one protected,
versioned request for the authenticated actor under Application Support. It
preserves the request UUID, cadence, whole-step target, test commitment,
timezone, owner, and exact retry metadata. An offline, cancelled, or ambiguous
response leaves the record in place; a relaunch restores it only for the same
actor and requires an explicit creation retry.

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

The controlling proof layers and external Apple prerequisites are in
`../../docs/PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md`. The older
`../../docs/PERSONAL_V1_ACCEPTANCE.md` and App Attest conformance suite remain
historical/generic regression records. Simulator proof does not substitute for
signed physical-device Health or hosted acceptance.


## Opt-in simulated friend duels

Debug/Staging: launch with `--fixture-mode --duels`, then open **You → Friend
duels**. Add `--fixture-duel-incoming`, `--fixture-duel-lost-response`,
`--fixture-duel-gate-off` or `--fixture-duel-offline` to exercise those cases.
The default Personal launch remains unchanged. Real duel RPC clients require
`--duels` and a disposable loopback backend with separately admitted local
actors and a curated event. Hosted configurations and Release stay closed.
See [native acceptance](../../docs/DUEL_NATIVE_V1_ACCEPTANCE.md) for the request
contract, completed authenticated local smoke and its reproducible runner.


Phase 2(d) adds progress, saved notices and correction history, independent
review receipts, confirmed results and separate simulated returns. Add
`--fixture-duel-review`, `--fixture-duel-correction`, `--fixture-duel-final`,
`--fixture-duel-settlement` or `--fixture-duel-blocked` for those scenarios.
Review and safe-exit recovery work with the gate-off/lost-response switches.
Real local clients require the additive native lifecycle projection migration.
See [native lifecycle acceptance](../../docs/DUEL_NATIVE_LIFECYCLE_V1_ACCEPTANCE.md)
for verification and the Phase 2(e) rematch/link handoff. The existing HTTP smoke
runner now also covers native review/exit recovery and blocked own returns.


### Phase 2(e): rematches and invitation links

The opt-in local duel includes **Challenge again** after a saved final result,
a fresh event and full new consent review. Creators can create/share/revoke
expiring links. Debug/Staging register `gametime-duel://invitation/<token>`;
Release's registrations and feature exclusion remain unchanged. A named friend
must sign in and explicitly agree. Links use no public preview or hosted page.

See [rematch/link acceptance](../../docs/DUEL_REMATCH_LINK_V1_ACCEPTANCE.md) for
SQL/RPC boundaries, durable recovery, native URL/account tests, simulator
journeys and the authenticated local smoke. `--fixture-duel-final` enables the
rematch journey; `--fixture-duel-link` supplies a fictional incoming link for
URL-handler tests. Neither fixture changes the normal Personal launch.
