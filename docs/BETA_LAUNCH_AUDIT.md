# GameTime External Beta Launch Audit

**Audit date:** August 5, 2026  
**Decision:** **NO-GO for actively onboarding external beta users today**

GameTime has a strong local foundation, but the current app and hosted backend
cannot yet complete the full user journey unattended. The two biggest risks are
not cosmetic:

1. A TestFlight install will reject its own valid production App Attest
   registration, which blocks trusted step syncing.
2. The hosted backend has no Personal result worker, so a completed challenge
   can remain stuck forever after its final-sync period.

The current builds are appropriate for continued engineering and internal
testing only.

## What “live-like beta” should mean

For this audit, “runs as if it were live on the App Store” means:

- Testers install the exact signed TestFlight build, not a developer build.
- The app uses its final Apple app identity and production-grade security.
- Every promised journey works end to end against a hosted beta backend.
- Testers use real Sign in with Apple and real Apple Health data.
- The system runs automatically without an engineer manually fixing records.
- Failures, lost connections, relaunches, and duplicate taps recover safely.
- Privacy, deletion, support, monitoring, backup, and incident procedures work.
- Payment behavior, if included, uses **Stripe test mode only** and clearly says
  that no real money moves.

This does **not** require live charges. Real-money fees remain blocked by legal,
Stripe, Apple/HealthKit, age, and jurisdiction approvals in
[PLAN.md](../PLAN.md).

### Recommended beta contract

Build one dedicated **Beta** configuration with:

- Release-level optimization and distribution signing.
- The final App Store bundle ID.
- The hosted beta Supabase project.
- Personal challenge creation, HealthKit, and App Attest enabled.
- Production App Attest behavior.
- Developer bypasses unavailable; any sample mode isolated and clearly labeled.
- Stripe test mode if the beta is intended to rehearse the paid journey.
- Production-safe logging and monitoring.

The current Release build cannot serve this purpose because it disables
Personal mutations, Health sync, and attested uploads. The current Staging build
also cannot serve it because it uses the staging app identity and forces the
unhosted Stripe sandbox:
[AppConfiguration.swift](../ios/GameTime/GameTime/AppConfiguration.swift),
[Release.xcconfig](../ios/GameTime/Configuration/Release.xcconfig), and
[Staging.xcconfig](../ios/GameTime/Configuration/Staging.xcconfig).

### Freeze one truthful release candidate

The current checkout contains substantial uncommitted custom-start and Stripe
work. Hosted and written inventories have also drifted: hosted Supabase already
contains migrations through the custom-start slice, including dormant Solo
migrations that the active plan still describes as withheld.

Before any beta deployment:

- Choose **Stage A without Stripe** or **Stripe sandbox beta** explicitly.
- Reconcile `PLAN.md`, `DECISIONS.md`, the acceptance checklist, app behavior,
  and the actual hosted migration/function inventory.
- Review the exact pending migration list. A broad database push can include
  every pending local migration, including payment work.
- Build from one clean, reviewed, immutable commit.
- Record the exact app version/build, database migrations, Edge Function
  versions, environment settings, and approval owner.
- Never archive or deploy from the current mixed working copy.

## Founder launch board

| Gate | Current state | Required before onboarding |
| --- | --- | --- |
| Live-like TestFlight build | **Blocked** | Create the dedicated Beta configuration, final bundle ID, correct entitlements, beta backend selection, and a repeatable build-number process. |
| Sign in and session recovery | **Partial** | Prove first sign-in, returning sign-in, relaunch, expired session, sign-out, account switch, and Apple credential revocation using the signed TestFlight build. |
| HealthKit and trusted sync | **Blocked** | Fix production App Attest handling, then prove real iPhone/Apple Watch reads, manual sync, background sync, final sync, and recovery. |
| Challenge creation | **Partial** | Resolve the custom-start contract, make cold/offline startup fail closed, and prove exact retry against hosted beta. |
| Payment setup | **Local only** | If included in beta, deploy and prove the full Stripe test-mode setup and commitment path. No live keys or live objects. |
| Seven-day lifecycle | **Partial** | Run one genuine seven-day challenge plus its 24-hour final-sync period on the exact TestFlight build. |
| Automatic result | **Missing** | Implement, schedule, monitor, and host the Personal assessment/finalization worker. |
| Review and test charge | **Local only** | If included, prove provisional miss, seven-day review, waiver, one idempotent test charge, failure, customer-action, webhook, and reconciliation paths. |
| Cancellation and recovery | **Partial** | Prove pending/active cancellation rules, offline retry, ambiguous response, duplicate tap, and safe terminal states. |
| Account deletion | **Missing end to end** | Add in-app deletion, fresh authentication, Apple-token revocation, server execution, local cleanup, retry, and support recovery. |
| Privacy and support | **Blocked** | Publish policy/support URLs, link them in-app, add a monitored contact path, accurate terms, and App Store privacy answers. |
| Operations | **Blocked** | Add crash/backend monitoring, job alerts, backup/restore proof, release manifest, rollback rules, incident owner, and tester-support process. |
| External TestFlight review | **Not proved** | Complete App Store Connect setup, upload and validate the exact build, pass Beta App Review, then run an internal smoke test before inviting external users. |

## Functions that must be complete

### 1. Account and identity lifecycle

The beta must support:

- First Sign in with Apple.
- Returning sign-in and session restoration.
- Expired-session recovery.
- Sign-out and safe account switching.
- In-app account deletion.
- Sign in with Apple token revocation during deletion.
- Removal of local pending uploads, private files, and App Attest state.
- Safe account recreation after deletion.

**Current blocker:** the app offers Sign Out but no Delete Account flow. The
backend deletion transaction exists, but the repository explicitly says it is
not yet an end-to-end user feature:
[YouView.swift](../ios/GameTime/GameTime/YouView.swift) and
[README.md](../README.md).

Apple requires account-creating apps to let users initiate deletion in the app:
[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

### 2. Apple Health permission and readiness

The beta must correctly handle:

- Health access allowed.
- Health access denied.
- No step data.
- iPhone-only steps and Apple Watch steps.
- Reconnection after permission or data problems.
- Clear user language that never claims data was verified when it was not.

Automated tests cannot replace a signed physical-device run. The exact
TestFlight build must be used.

### 3. Production App Attest registration and trusted uploads

This is a deterministic blocker, not merely an untested scenario.

After registration, the app currently accepts only:

```swift
document.environment == "development"
```

See
[SupabaseMetricUploadClient.swift](../ios/GameTime/GameTime/SupabaseMetricUploadClient.swift).
Apple states that TestFlight and App Store builds use the production App Attest
environment regardless of the entitlement selection. A fresh TestFlight install
will therefore receive a valid `production` response and the current app will
reject it.

Before beta:

- Accept only the environment appropriate to the signed build and server
  contract.
- Add production-response tests and negative mismatch tests.
- Test fresh TestFlight installation.
- Test an upgrade from a developer-installed build with retained App Attest
  state.
- Confirm the hosted backend accepts the exact final App ID.
- Prove registration, signed upload, duplicate request, lost response, and key
  recovery on a physical device.

Apple reference:
[App Attest environment behavior](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment).

### 4. Challenge creation and authoritative startup state

The app must not allow a user to start a second challenge merely because the
network failed before the existing challenge/hold state loaded.

The current cold-start path can leave the challenge list empty after a refresh
failure while still enabling creation:
[PersonalAccountabilityStore.swift](../ios/GameTime/GameTime/PersonalAccountabilityStore.swift),
[TodayView.swift](../ios/GameTime/GameTime/TodayView.swift), and
[ChallengesView.swift](../ios/GameTime/GameTime/ChallengesView.swift).

Before beta:

- Disable creation until authoritative open-challenge and hold state loads.
- Show an honest retry state when it cannot load.
- Preserve one-open-challenge enforcement on the server.
- Prove duplicate taps, lost responses, relaunches, and two simultaneous
  sessions cannot create duplicates.

### 5. Freeze the start-time contract

The hosted database and current UI allow a custom future start hour, while
parts of the active plan, decisions, and acceptance runbook still specify the
next local midnight.

Before beta, choose one rule:

- Remove custom starts from the beta; or
- Formally approve custom starts, supersede the old decision, update all copy
  and acceptance criteria, and rerun start-time, timezone, and daylight-saving
  tests.

Do not onboard users while the app, legal terms, test plan, and backend describe
different challenge rules.

### 6. Reliable metric and coverage retry

Saved, already-signed requests must be replayed before asking Apple Health for
fresh data or checking whether the fresh-sync window has closed.

The current coverage coordinator checks challenge eligibility before loading
and replaying the saved request. After the cutoff, a valid lost-response retry
can become permanently stranded:
[PersonalSyncCoverage.swift](../ios/GameTime/GameTime/PersonalSyncCoverage.swift).

Before beta:

- Replay saved exact bytes first.
- Keep the signed body and idempotency identity unchanged.
- Safely terminate or quarantine a permanently rejected item.
- Never show “waiting to send” when no retry path remains.
- Test cutoff, offline, relaunch, unreadable HealthKit, account switch, and a
  later challenge.

### 7. Automatic Personal assessment and final result

The database already has protected operations to record an assessment and
publish a result, but the hosted system has no worker or schedule that calls
them. The legacy finalizer intentionally excludes Personal challenges.

Complete a service-owned worker that:

- Finds due challenges after the evidence cutoff.
- Classifies complete, missing, conflicting, quarantined, device-failure, and
  GameTime-outage evidence deterministically.
- Freezes an evidence digest.
- Records the assessment and publishes the result.
- Is safe under duplicate runs, concurrent final sync, deletion, and retries.
- Alerts when a challenge remains active past the written completion deadline.
- Supports bounded operator replay without rewriting a published result.

Then prove the worker in hosted beta with successful, failed, retried,
concurrent, deliberately stalled, and outage scenarios.

Relevant protected database operations are in
[20260802165312_personal_v1_backend.sql](../supabase/migrations/20260802165312_personal_v1_backend.sql).

### 8. Complete hosted Stripe test mode if the beta rehearses payment

The local working tree contains the Stripe sandbox database migration, iOS
PaymentSheet integration, and five test-mode Edge Functions. All backend code
tests pass, but none of this payment slice is hosted.

Before a payment-rehearsal beta:

- Review and deploy the exact forward migration and functions to a dedicated
  non-production target.
- Configure Stripe test credentials without exposing them.
- Configure and prove signed webhooks.
- Save a reusable test payment method.
- Create the challenge only after Stripe confirms setup.
- Publish a missed goal as provisional.
- Hold the full seven-day review window.
- Waive met, inconclusive, outage, cancelled, and overturned outcomes.
- Create exactly one idempotent test PaymentIntent after an eligible miss.
- Never automatically retry a decline or customer-action state.
- Add an explicit user-authorized recovery path.
- Reconcile delayed, reordered, and duplicate webhooks.
- Block another paid challenge while review/payment state is unresolved.
- Make every relevant screen say **Payment test mode — no real money moves.**
- Add provider-aware deletion, retention, monitoring, and support procedures.

The hosted beta must have a secure worker schedule for eligible test charges;
having function source code alone is not enough.

If the first beta intentionally excludes Stripe, remove the sandbox path from
the Beta build and call it a **Stage A core-product beta**, not a full rehearsal
of the paid product.

### 9. Cancellation, waiver, and failure recovery

For every consequential action, prove:

- Success.
- Clear refusal.
- Lost response after the server committed.
- Exact retry.
- Double tap.
- Relaunch.
- Offline-to-online recovery.
- Account switch.

At minimum this applies to challenge creation, cancellation, metric/coverage
sync, finalization, review, test charge, and account deletion.

No missing or conflicting Health data may become a failed challenge or charge.

### 10. Privacy, terms, and support

Before external users:

- Publish a public privacy-policy URL.
- Link the policy inside the app without requiring sign-in.
- Publish a support URL and monitored feedback email.
- Add an in-app Help/Contact Support action.
- Publish terms that match the exact challenge, cancellation, review, retention,
  and test-payment behavior.
- Explain what deletion removes and what limited audit facts remain.
- Complete App Store privacy answers for account/profile identifiers, step data,
  challenge data, device/App Attest identifiers, and applicable Stripe data.
- Verify logs contain no raw Health or secret data.

The current Privacy screen is explanatory product copy, not a linked legal
policy, and “Contact support” has no contact action:
[YouView.swift](../ios/GameTime/GameTime/YouView.swift) and
[GameTimeApp.swift](../ios/GameTime/GameTime/GameTimeApp.swift).

Apple references:
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
and
[Protecting user privacy with HealthKit](https://developer.apple.com/documentation/healthkit/protecting-user-privacy).

### 11. User-safe monitoring and operator controls

Before onboarding, the team must be able to see and contain failures:

- iOS crash reporting with retained dSYMs for readable crash traces.
- Edge Function 5xx and authentication-anomaly alerts.
- Finalizer failure and overdue-challenge alerts.
- Activation and retention backlog alerts.
- Stripe test webhook/worker alerts if included.
- A tester-support owner and response expectation.
- A kill switch for new onboarding and high-risk backend functions.
- A release manifest tying one commit to its migrations, functions, app build,
  and environment.
- Backup/point-in-time recovery ownership and a tested restore.
- Written incident, rollback/abort, forward-repair, and account-deletion support
  procedures.

Cron “success” alone is insufficient. The current hosted push job reports
success while required Vault bridge entries are absent, making the job inert.
Either fully configure and monitor notifications or keep them outside the beta
promise.

## Platform and App Store gates

### Final app identity and signed archive

Before the first upload:

- Choose the final bundle ID. Every current app configuration uses
  `com.mjenkins.gametime.staging`, and a build script rejects other IDs.
- Configure the same final client identity in Apple and Supabase Auth.
- Create the App Store Connect app record.
- Configure distribution signing and the Sign in with Apple, HealthKit, and App
  Attest capabilities.
- Produce a signed archive from a clean, immutable commit.
- Validate the archive in Xcode and confirm TestFlight processing.
- Inspect the archive’s embedded entitlements and aggregate privacy report.
- Use a unique, repeatable version/build number. The current project is
  `0.8.1 (1)`.
- Preserve the archive and dSYMs.

### App icon and privacy manifest

The repository currently has no App Icon asset and no `PrivacyInfo.xcprivacy`.

Before upload:

- Add the complete App Store icon, including the 1024×1024 marketing icon.
- Add the app privacy manifest.
- Declare valid reasons for required-reason APIs used by the app.
- Generate Xcode’s aggregate privacy report and reconcile the Stripe/Supabase
  manifests with App Store privacy answers.

Apple references:
[Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon/),
[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files),
and
[Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

### iPhone versus iPad

The project currently declares iPhone and iPad support, while the recorded UI
proof is iPhone-only.

Before upload, either:

- Make the first beta iPhone-only; or
- Complete iPad layout, rotation, HealthKit, multitasking, physical-device, and
  screenshot acceptance.

### App Store Connect and Beta App Review

Complete and verify:

- Developer Program agreements and roles.
- App name, SKU, category, age rating, availability, and copyright.
- Privacy and support URLs.
- App Privacy labels.
- Export-compliance answers.
- EU trader status if distributing in the EU.
- Accurate HealthKit and payment review notes.
- Beta description, “What to Test,” feedback email, review contact, and tester
  groups.
- A real review path that does not rely on hidden developer fixtures.

Apple requires Beta App Review before an external TestFlight build is broadly
tested:
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).

## Security and backend gates

The hosted foundation has useful protections: public tables have row-level
security, public views use caller-level permissions, privileged Personal result
and deletion operations are service-only, request sizes are bounded, and error
logging is deliberately sanitized.

Before beta, still complete:

- Classify and close or formally accept all 29 hosted authenticated
  `SECURITY DEFINER` warnings.
- Revoke dormant authenticated social/Solo operations that are not part of the
  beta, or explicitly support and abuse-test them.
- Confirm Apple-only authentication. If password login remains reachable,
  enable leaked-password protection.
- Add per-account/device abuse limits for attestation, ingest, coverage, and
  diagnostics.
- Prove unauthenticated, malformed-token, cross-account, and service-only
  rejection against the hosted target.
- Run two real authenticated identities to prove isolation.
- Run a clean disposable database reset and the complete pgTAP suite before
  freezing the candidate.

Supabase advisor reference:
[Authenticated `SECURITY DEFINER` function executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Exact acceptance run before inviting users

Use the exact processed TestFlight build and hosted beta release candidate.

1. Fresh install, first Sign in with Apple, onboarding, and relaunch.
2. Health allowed, denied, no-data, iPhone, and Apple Watch cases.
3. Production App Attest registration and signed manual sync.
4. Offline sync, lost response, exact replay, and account switch.
5. Challenge creation, duplicate tap, cancellation, and relaunch.
6. Background observer wake and durable upload.
7. One genuine seven-day challenge plus the 24-hour final-sync period.
8. Automatic assessment and published result without engineer intervention.
9. Met, missed, inconclusive, outage, quarantine, and conflicting-data outcomes.
10. Stripe test setup, review, test charge, failure, and webhook recovery if
    payment is in scope.
11. Account deletion during pending, active, and completed states, followed by
    account recreation.
12. Two-account isolation and abuse/refusal checks.
13. Backup/restore, worker alert, kill switch, and incident-response drill.
14. Internal TestFlight smoke test, then external Beta App Review approval.

Do not substitute an accelerated fixture for the real calendar run. Use both.

## What can wait until after beta starts

These are not launch blockers unless they are promised in beta onboarding:

- Editable username and profile photo.
- Social challenges, friends, standings, and reactions.
- Reminder notifications.
- Dark mode and a branded launch screen.
- Automated release CI, if the initial manual archive process is documented and
  repeatable.
- Real-money Stripe charging.

## Go/no-go checklist

Invite external users only when every item below is checked:

- [ ] One clean, reviewed commit defines the entire candidate.
- [ ] The dedicated Beta configuration works like the planned App Store app.
- [ ] The final bundle ID and Apple/Supabase identities match.
- [ ] The App Attest production-response defect is fixed.
- [ ] Cold/offline creation fails closed.
- [ ] Saved signed retries work after the fresh-sync cutoff.
- [ ] Start-time rules match across code, database, terms, and tests.
- [ ] The hosted Personal finalizer automatically publishes results.
- [ ] The hosted Stripe test lifecycle passes, if payment is in scope.
- [ ] In-app account deletion and Apple-token revocation pass.
- [ ] Privacy policy, support, terms, icon, and privacy manifest are complete.
- [ ] Hosted security findings are dispositioned and two-user isolation passes.
- [ ] Crash/backend/job monitoring, backup, rollback, and support are operational.
- [ ] The exact TestFlight build passes the full physical acceptance matrix.
- [ ] The real seven-day plus 24-hour calendar run passes.
- [ ] Internal smoke testing and external Beta App Review pass.
- [ ] No unresolved crash, data-loss, privacy, authentication, deletion,
      challenge-integrity, or duplicate-charge defect remains.
- [ ] Real charges remain disabled.

## Evidence checked in this audit

### Verified on August 5, 2026

- Staging simulator build compiles successfully with no reported warnings.
- Release simulator build compiles successfully with no reported warnings.
- Backend formatting, linting, and type-checking pass.
- All **386 backend code tests** pass.
- All **103 Swift package tests** pass.
- The GameTime simulator test result bundle reports **133 passed, 0 failed**.
- The conformance simulator suite reports **10 passed, 0 failed**.
- A disposable clean database applied every migration and passed all **1,678
  pgTAP assertions across 41 files**.
- Hosted Supabase is healthy.
- Hosted Supabase has 28 migrations through
  `20260803192500_personal_custom_start_time`.
- Six Edge Functions and four scheduled jobs are active.
- No Personal assessment/result worker or schedule is hosted.
- The five local Stripe functions and Stripe migration are not hosted.
- The implementation through commit `7917b04` is published on `main`.
- `git diff --check` passes.

### Not proved in this audit

- A signed archive or TestFlight processing.
- A physical TestFlight install.
- Real Sign in with Apple, HealthKit, production App Attest, or background wake.
- A hosted full challenge result.
- Hosted Stripe sandbox behavior.
- Account deletion from the app.
- App Store Connect, signing, legal, privacy, support, monitoring, restore, and
  incident-readiness state.

The audit and evidence update were documentation-only. No hosted service, Apple
account, payment account, deployment, migration, or user data was changed by
the audit.
