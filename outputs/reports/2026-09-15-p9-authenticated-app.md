# P9 ordinary app authentication connection — September 15, 2026

Base: `c6f88cde525b2cf085d7420c1780a115ed0871e2`. Implemented on the isolated
`fm/gametime-p9-authenticated-app-20260915` branch. Firstmate owns subsequent
main landing and publication. This report describes one bounded P9 slice,
not completed real-source P8/P9 or Beta acceptance.

## Implemented behavior

- `LiveServicesFactory` passes the configured challenge client through
  `AppServices` into ordinary `AppModel`/Signal. It uses the existing Supabase
  SDK and session shared with Apple sign-in and profile loading.
- `GAMETIME_CHALLENGE_V1_ENABLED` is an explicit transport opt-in, default `NO`
  in every checked-in configuration. Valid HTTPS origins are supported; explicit
  loopback development remains non-Release only. No Beta host was selected,
  and the historical configured hosted project was not enabled for challenges.
- The client reuses `validSession()` for renewal, checks the login identity
  across renewal and keeps the existing actor/token fence across each request.
  It preserves exact bytes, request journals and redirect refusal. Revocation
  clears shared challenge content and the shell provides a sign-out action.
- Opaque invitation intent now belongs to AppModel above authentication and is
  received by the ordinary root. Cancellation, failed sign-in, account changes
  and relaunch preserve it until explicit confirmed redemption. Accepted account
  deletion clears the newly owned in-memory state; existing disk cleanup remains.
- Real local testing reproduced queued old Auth events clearing a new actor's
  challenge store. AppModel now applies only snapshots matching the current
  shared session, with its existing mutation/generation protections.

Signal presentation, historical Personal access/agreements/consent, all thirteen
policies, four required sources, simulation and server gates are preserved.
There are no automatic invitations, increased amount defaults, notifications,
Health/loss targeting or new financial exposure. Existing explicit consent,
request recovery and safe exits remain authoritative.

## Verification

Commands, individual result bundles and resource disposition are recorded in
the private task report at
`/Users/user/firstmate-workspace/data/gametime-p9-authenticated-app-20260915/report.md`.
The focused local checks include:

- 30 native checks passed with zero failures/skips: configuration/HTTPS routing,
  actor and token fences, stored-session expiry/real local Auth renewal, revoked
  session denial, durable invitation/issued-link recovery and deletion regression.
  The ordinary AppModel HTTP journey covers interrupted sign-in, age, paused
  creation/exact retry, link redemption with lost response and account switch,
  targets, roster freeze, both consents, detail, safe exit and history.
- One visible ordinary Signal journey passed with zero failures/skips: URL
  delivery while signed out, shared-session sign-in, retained Personal access,
  age, creation, cancellation/history, sign-out and cold relaunch. The actual
  history screenshot was inspected; simulation and private own-history remain.
- 60 affected native checks passed with zero failures/skips: 33 AppModel/routing,
  20 domain/configuration and seven Signal rendering tests, including the new
  delayed-auth-snapshot regression and all thirteen agreement presentations.
- Unsigned `GameTime` Release simulator build passed. The built plist retains
  `GAMETIME_CHALLENGE_V1_ENABLED = NO`; the three Debug substitute flag/button
  markers are absent from the executable. The iPhone source/product guard
  passed (154 sources, three targets/schemes, no Watch payload or linkage).
- Python syntax, documentation links and `git diff --check` passed. No backend
  migration, source policy or readiness entry changed.

These are 91 selected passing tests with zero skips, using Xcode 27.0
(`27A5237l`) and an owned iPhone 17 Pro simulator on iOS 26.5. This does not
replace qualification on the project's pinned Xcode 26.2 toolchain.

The existing `scripts/beta-native-smoke.py` supplies `--native-only
--native-phase app` and `--touch-only app`. It contacts real local GoTrue and
PostgREST through its owned proxy. Debug's `--authenticated-app-local` replaces
only sign-in with a fictional password account, disables Health/provider
services and mounts ordinary RootView/AppModel/Signal. It does not mount the
separate local preview shell. See [the local connection guide](../../docs/BETA_LOCAL_PREVIEW.md#ordinary-app-connection-and-its-local-substitute).

## Retained failures and limits

Failed attempts remain separate: initial misplaced service argument; test helper
visibility/type-name compilation errors; local email login initially disabled;
a Simulator busy launch; an incorrect test expectation that a paused action
would be discarded; and the reproduced stale Auth-event account-switch failure.
The actual server keeps a paused action for explicit retry; that behavior was
preserved, and the test was corrected.

The session-expiry case expires stored client metadata and performs renewal
against real local Auth. It is not a clock-expired hosted JWT or Apple-provider
check. The visible sign-in button is a Debug-only substitute; no real Apple
exchange/revocation, Health read, hosted mutation, physical device action,
release archive, distribution or payment occurred. The full release matrix was
not run. All 18 readiness entries remain false.

Approved HTTPS invitation host/AASA/entitlements, Apple/bundle identity, actual
hosting, P7 source policies and physical acceptance, real consent/ingestion,
all-mode source-backed journeys and human/release qualification remain separate.
The existing settings/source worksheets retain those unanswered choices.

All task-owned controllers finished with fixture gates off, seven fictional
sessions revoked per run and no cleanup failures. The task's Supabase services
and simulator were stopped; its database volume, network, simulator and private
evidence are retained for Firstmate. Shared resources were untouched.
