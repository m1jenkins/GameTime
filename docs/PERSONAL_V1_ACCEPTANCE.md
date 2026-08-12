# Prove Personal Accountability V1 Stage A

> **Historical acceptance record.** This runbook applies only to challenges
> frozen with `step_data_policy = attested_hourly_v1`. D120 supersedes its
> manual sync, App Attest, hourly coverage, diagnostic, eligibility-hold, and
> positive-sample creation requirements for new or migrated Personal
> challenges. Do not use this document as a beta gate for
> `healthkit_nonmanual_daily_v1`; use
> [PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md](PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md).

This runbook is designed to prove one seven-day personal steps challenge with a
test commitment on one physical iPhone, plus authorization isolation between
two database actors. The fresh repository-local evidence below does not prove
that physical-device layer, real fees, production readiness, TestFlight
readiness, or App Store compliance.

Do not combine proof layers. Local tests, hosted Staging, a simulator, a signed
build, one physical device, and two authenticated actors establish different
facts. Record each one separately and leave unavailable gates unchecked.

## Prerequisites

- Reviewed commit and a clean worktree recorded before the run.
- Local Supabase, Deno, Swift, and Xcode versions recorded.
- One unlocked, trusted, provisioned physical iPhone.
- A Staging build with Sign in with Apple, HealthKit, and development App Attest.
- `ATTEST_DEV_BYPASS` absent from hosted Staging.
- Hosted project identity and public bundle IDs confirmed read-only.
- One Apple-authenticated Staging account with completed handle onboarding.
- A second authenticated actor available for privacy tests or a controlled
  sequential account-isolation observation.
- Explicit approval before any hosted migration or Edge Function deployment.

If the physical phone, provisioning, hosted approval, or second actor is
unavailable, stop at the last completed layer. Do not substitute simulator
fixtures or optional features for the missing evidence.

## Record only bounded evidence

Record:

- Commit ID, build configuration, bundle ID, and hosted project reference.
- Challenge ID, request UUID, diagnostic ID, result ID, and hold ID when needed.
- Challenge model, cadence, target, commitment preset, frozen timezone, start,
  end, cutoff, status, and result code.
- Counts of expected and covered buckets, accepted/replayed uploads, rows, and
  test assertions.
- Timestamps needed to prove ordering, grace, and post-hold clearance.
- HTTP status classes and bounded error codes, not bodies containing private
  data.

Do not record:

- Raw HealthKit values or hourly activity rows.
- Request bodies, assertions, attestation objects, receipts, payload digests,
  access or refresh tokens, publishable or service credentials, Apple private
  material, or database connection strings.
- Device logs that contain HealthKit diagnostics.
- Another user's handle, profile details, activity, device state, or terms in
  the acceptance record.

## Prove the local repository first

1. Confirm the implementation is based on the reviewed `main` history and did
   not merge the dormant social branch wholesale.
2. Reset the local database from migrations and run every pgTAP suite.
3. Run database lint and security/performance advisors for the new schema,
   functions, grants, and policies.
4. Run Deno format, lint, type checks, and tests.
5. Run GameTimeCore build and tests.
6. Run product unit and UI tests.
7. Build Debug, Staging, and Release simulator configurations.
8. Run the conformance target tests.
9. Run `git diff --check`.

Local exit criteria:

- Legacy backfill and compatibility tests pass without altered historical
  results, standings, or obligations.
- Duplicate and concurrent personal creation tests produce one open challenge.
- Two-user RLS tests isolate terms, activity, coverage, diagnostics, results,
  and holds.
- Daily, cumulative, spring-forward, fall-back, grace, quarantine, outage, and
  hold-recovery tests pass.
- UI tests find only Today, Challenges, and You and find no reachable social or
  charity language.
- Release configuration tests prove personal mutation remains disabled and no
  client request can name `live_fee`.

### Fresh Personal candidate evidence (2026-08-03)

The tree recorded by the commit containing this runbook was reconstructed from
exact baseline `422e638b1e255b8d3f8a3aae9036bbc32432fff6` and excludes every
Solo migration, test, and documentation section. The applicable local gates
were rerun against that Personal-only tree:

- A disposable loopback Supabase reset applied 24 migrations, ending with the
  two Personal migrations in order. All 1,293 pgTAP assertions across 32 files
  passed. Schema lint reported no errors; local security and performance
  advisors reported no warning- or error-level findings.
- Deno 2.9.4 checked formatting for 56 files, linted and type-checked 55 files,
  and passed all 350 tests across 21 modules. Both Personal Edge Function entry
  points resolved complete 212-module bundles.
- Swift 6.2.3 built GameTimeCore and passed all 103 tests in nine suites.
  `./scripts/test-all.sh` independently passed the database, Deno, and Swift
  gates together.
- Xcode 26.2 build 17C52 passed the complete unfiltered product matrix on an
  iPhone 17 Pro iOS 26.2 simulator: 103 unit and 10 UI tests, with zero failures
  or skips. GameTimeConformance passed 10 of 10 with zero failures or skips.
- Unsigned Debug, Staging, and Release simulator builds passed. The only raw
  build warning was Xcode's expected App Intents metadata self-skip accepted by
  D83; categorized diagnostics reported no warning or error.
- Whitespace, Solo-exclusion, migration-order, credential, provider,
  money-movement, generated-artifact, Release-lock, RLS/grant, App Attest, and
  exact-byte-retry checks passed.

This is repository-local and simulator evidence only. Hosted Personal remains
absent until a separately approved deployment, and signed physical HealthKit,
App Attest, background-delivery, and two-device acceptance remain open.

### Recorded dirty-tree evidence — not candidate proof (2026-08-02)

This run began on dirty `main` at baseline
`422e638b1e255b8d3f8a3aae9036bbc32432fff6` and included later dormant database
work that is absent from the Personal candidate. It is useful recorded evidence,
but it is not a clean-commit, Personal-only, or publication record.

- Xcode 26.2 build 17C52 ran `GameTime.xcodeproj`, scheme `GameTime`, on a
  booted iPhone 17 Pro simulator with iOS 26.2. The complete unfiltered product
  matrix discovered and passed 113 tests: 103 unit and 10 UI, with zero failures
  and zero skips.
- The UI matrix exercised the Today, Challenges, and You roots; steps-only daily
  and cumulative creation; $10, $20, $30, $40, and $50 presets with $10 as the
  default; diagnostic, frozen review, scheduled challenge, pending-request
  relaunch, eligibility-hold recovery, loading, empty, and offline states.
- The exact **Test commitment — no money will be charged.** disclosure was
  asserted before confirmation and on open-challenge surfaces. Reachable fixture
  screens were checked for the forbidden friend, invitation, roster,
  competitor, rank, standing, winner, charity, reaction, and tie-break language.
- An XXXL Dynamic Type launch, accessibility labels and values, and a Reduce
  Motion launch remained usable through the Personal creation and privacy
  surfaces.
- The complete unfiltered `GameTimeConformance` simulator suite passed 10 of 10
  tests with zero failures and zero skips. This is deterministic simulator proof,
  not physical App Attest proof.
- Unsigned simulator builds passed for Debug (`GameTime`), Staging
  (`GameTime-Staging`), and Release (`GameTime`). Release mutation-lock tests
  also passed.
- Fresh builds reproduce Xcode's exact diagnostic:
  `Metadata extraction skipped. No AppIntents.framework dependency found.` The
  product and conformance projects have no App Intents source, extension target,
  linked framework, package, or linker flag. Xcode's installed metadata extractor
  contains this exact self-skip path. D83 therefore accepts it as an expected
  Xcode 26.2 toolchain boundary. No dummy intent, unused framework, or broad
  warning suppression was added. No other build warning was observed.
- The combined dirty-tree database suite passed, but its file and assertion
  counts are intentionally not carried forward as Personal-only proof.
  `public` and `app` schema lint found no errors, and local security and
  performance advisors found no warning-level issues.
- Deno format checked 56 files, lint checked 55 files, type checking passed, and
  all 350 tests across 21 modules passed. GameTimeCore built and all 103 tests
  across nine suites passed. `./scripts/test-all.sh` independently passed all
  three portable suites.
- Bounded repository checks resolved all 5 relative inline Markdown links and
  all 13 active inline-code Markdown references. No reference-style definitions
  were present, and `git diff --check` passed.

This evidence closes only the repository-local simulator layer. It does not
prove HealthKit reads, App Attest, provisioning, signed or physical-device
behavior, real background delivery, hosted scheduling, hosted multi-user
isolation, a real processor, money movement, legal approval, or App Review
approval.

## Scope note for the external sandbox beta

This document remains the acceptance record for the internal `test_only` Stage
A path. Its Release-lock statements describe that historical/internal contract,
not the current invite-only external Release source configuration.

The external beta is a separate Stripe test-mode rehearsal controlled by
[`BETA_LAUNCH_AUDIT.md`](BETA_LAUNCH_AUDIT.md). It requires its own sandbox,
hosted, production-App-Attest, signed-device, deletion, and TestFlight proof.
Nothing in the green Stage A checklist proves those gates.

## Prove hosted Stage A only after approval

1. Record explicit approval and the exact reviewed commit.
2. Confirm the target is Staging, never production.
3. Apply only the reviewed forward migrations and deploy only reviewed personal
   Edge Functions.
4. Confirm every existing hosted challenge reports
   `legacy_charity_contest` and no legacy result or obligation changed.
5. Confirm personal tables have RLS enabled and only their explicit grants.
6. Probe unauthenticated personal RPCs and require authorization failure.
7. Create a personal challenge through the authenticated public RPC.
8. Confirm the stored settlement mode is `test_only` even though the client did
   not send a mode.
9. Confirm no standings, winner, charity, donation obligation, payment, or
   payout row was created.
10. Let the hosted activation worker activate the one-owner challenge without a
    test-only row update.

Hosted exit criteria:

- Migration and Edge Function versions match the reviewed commit.
- One-owner activation is observed through the hosted worker.
- Test-only enforcement is proven at the server row and function boundary.
- Legacy and personal paths dispatch independently.
- No production object or configuration was changed.

## Run the personal creation flow on one physical iPhone

1. Install the reviewed Staging build and sign in with Apple.
2. Complete or restore public-handle onboarding.
3. Confirm only Today, Challenges, and You are reachable.
4. Start creation and confirm steps is the only metric.
5. Select daily cadence and confirm the default is 10,000 steps per day.
6. Select cumulative cadence and confirm the default is 70,000 total steps.
7. Edit the target and confirm non-whole, zero, negative, and over-limit values
   cannot be submitted.
8. Exercise $10, $20, $30, $40, and $50; confirm $10 is the initial default.
9. Check Apple Health access. Confirm a local read finds recent iPhone or Apple
   Watch steps and then permits Continue without running a trusted diagnostic
   or waiting for an App Attest-backed upload. If Health access is already
   confirmed, Continue must be available without another check.
10. On review, confirm **Test commitment — no money will be charged.** is
    conspicuous before the final action.
11. Submit once, deliberately lose or ignore the response, relaunch, and retry
    the saved personal request.
12. Confirm one challenge exists with the same request UUID and exact frozen
    terms.
13. Confirm its start is the first local midnight strictly after creation and
    its end is midnight seven local dates later.
14. Attempt to create a second challenge and confirm the server rejects it.

Creation exit criteria:

- Apple Health access, review, submission, lost-response recovery, and relaunch
  work on the physical phone.
- No trusted diagnostic action or diagnostic status appears during normal
  creation.
- One personal challenge and owner participant exist.
- No invitation, charity, tie-break, roster, or social pending record exists.
- The challenge is `test_only` and the app consistently uses the exact no-charge
  disclosure.

## Prove cancellation and activation

Use separate personal challenges when necessary; do not rewrite timestamps on a
real accepted request.

1. Create a scheduled challenge and cancel it before `starts_at` with a stable
   cancellation request UUID.
2. Retry that exact cancellation after its former start time and confirm the
   same cancelled challenge returns.
3. Confirm the open slot is released and another personal challenge can be
   created.
4. For the new challenge, wait for scheduled activation.
5. Attempt a new cancellation after activation and confirm rejection.
6. Confirm the slot remains occupied through the seven-day window, 24-hour
   grace, and assessment wait.

## Run trusted activity sync

1. Confirm Health access is visible in You without raw values. Do not run a
   trusted diagnostic as a prerequisite for normal activity sync.
2. During the active window, tap manual sync.
3. Confirm the signed upload records admissible steps and the queried completed
   hourly coverage as separate facts.
4. Confirm every positive metric batch is accepted before the matching coverage
   batch sends. Simulate a pending metric upload and confirm coverage remains
   pending rather than certifying a partial query.
5. Force-quit after an ambiguous upload response, relaunch, and retry the exact
   saved bytes and identifiers.
6. Confirm the accepted batch is returned as a replay and no evidence or
   coverage is duplicated.
7. Confirm a real zero-step covered period contributes coverage without
   inventing a positive step row.
8. Repeat until every completed bucket is covered.
9. With the Staging build backgrounded, create new device-recorded steps and
   capture a real HealthKit observer wake. Confirm the observer invokes the
   same durable personal sync pipeline, always completes the HealthKit delivery
   callback, and retries any exact pending metric or coverage request after a
   later foreground or background wake. Simulator invocation or a direct call
   to the coordinator is not physical background-delivery proof.
10. After the seventh local midnight, perform the final sync within 24 hours.
    Prove both a manual final sync and, separately, an observer-triggered final
    sync on the signed physical build.
11. Confirm the expected coverage set is generated from the frozen timezone and
   includes every completed local-hour interval wholly inside the challenge
   window. Exercise both a one-hour DST transition and a non-hour transition;
   do not assert a universal fixed count. If the platform generates overlapping
   intervals, confirm the result fails closed as
   `inconclusive / gametime_outage`, waives the commitment, and creates no hold;
   never score overlapping values twice.
12. Attempt an upload after the personal cutoff and confirm rejection.

An empty HealthKit read does not prove permission denial. Record it as no
trusted readable coverage and expect an inconclusive path unless a later trusted
sync completes the window.

## Prove personal scoring and history

Exercise deterministic fixtures locally and one bounded hosted/device outcome:

1. Daily 7/7 reaches `met_goal / target_reached`.
2. One completely covered day below target reaches
   `missed_goal / target_missed`.
3. Cumulative total at or above target reaches `met_goal / target_reached`.
4. Completely covered cumulative total below target reaches
   `missed_goal / target_missed`.
5. Missing coverage, unresolved quarantine, conflicting evidence, or unresolved
   assessment reaches the matching `inconclusive` reason before goal comparison.
6. Confirmed GameTime outage reaches `inconclusive / gametime_outage`, waives,
   closes the slot, and creates no hold.
7. User/device sync failure reaches
   `inconclusive / user_device_sync_failure`, waives, closes the slot, and
   creates an eligibility hold.
8. Confirm the first result closes the slot and the completed challenge appears
   in history.
9. Confirm an exact result-publication retry is idempotent, a conflicting retry
   is rejected, and the published result is never rewritten.

## Prove diagnostic-hold recovery

1. With an active hold, attempt personal creation and confirm rejection.
2. Replay or reference a diagnostic from before the hold and confirm it cannot
   clear the hold.
3. Run a fresh HealthKit and App Attest diagnostic after the hold timestamp.
4. Confirm the diagnostic succeeds and sets the hold's one-time clearance
   timestamp and diagnostic reference without deleting or rewriting its cause,
   challenge, or result.
5. Confirm personal creation is available again.

## Verify two-actor privacy

Using two independent authenticated database sessions:

1. Have actor A create and sync a personal challenge.
2. As actor B, attempt direct table reads and every personal list/detail RPC for
   actor A's challenge.
3. Confirm actor B cannot read A's base challenge through participant access,
   terms, metric rows, coverage, diagnostic state, result, or hold.
4. Confirm actor A can read only the owner-safe personal surfaces and cannot
   directly write service-owned rows.
5. Confirm `anon` has no table or function access.
6. Confirm service-only assessment, result, diagnostic recorder, and hold
   clearance functions are not executable by `authenticated` or `anon`.

If a controlled sequential account switch is run on the physical phone, confirm
sign-out clears personal challenge, pending request, upload queue, diagnostic,
and hold state before actor B signs in. Do not count one phone as two concurrent
device identities.

## Check privacy and language

Inspect every reachable V1 screen and bounded log output:

- No Friends tab, invitation action, roster, competitor, rank, standing,
  winning, winner, charity, donation obligation, reaction, or tie-break copy.
- No raw step values in server logs, acceptance artifacts, diagnostic records,
  push payloads, or error details.
- No tokens, assertions, attestation objects, receipts, signed bodies, payload
  digests, private keys, or service credentials.
- No legacy social challenge is rendered as a personal challenge.
- Every current Stage A open personal surface says
  **Test commitment — no money will be charged.**

## Prove the external Stripe sandbox separately

This section records the Stage B acceptance contract. Its local foundation is
present, but this checklist has not passed end to end and does not change the
Stage A evidence above. Stripe test objects move no real money. Do not report
this section as hosted, live, legal, processor, or App Store proof.

- [ ] A new forward terms version leaves all Stage A and Solo rows, enums,
      results, and migrations unchanged.
- [ ] Challenge creation uses one Stripe test-mode `SetupIntent` after Health
      access succeeds and before final confirmation.
- [ ] The exact creation request binds the frozen amount, terms version,
      payment-method reference, and explicit off-session consent without storing
      card data.
- [ ] Starting or scheduling a challenge creates no authorization hold,
      `PaymentIntent`, or charge.
- [ ] Pre-start cancellation closes with $0 and creates no `PaymentIntent`.
- [ ] The seven-day challenge retains its 24-hour final-sync period, and no
      payment decision occurs before the evidence cutoff.
- [ ] `met_goal` closes with $0 and creates no `PaymentIntent`.
- [ ] Every `inconclusive` reason closes with $0 and creates no
      `PaymentIntent`.
- [ ] A complete `missed_goal` publishes as provisional with
      `review_deadline = published_at + interval '7 days'`.
- [ ] No charge occurs before `review_deadline` or while a timely review remains
      unresolved.
- [ ] No review by the deadline, or a completed review that confirms the miss,
      permits exactly one idempotent off-session test-mode `PaymentIntent` for
      the frozen amount.
- [ ] A review that overturns the miss, or remains unresolved at the deadline,
      waives the amount and creates no charge.
- [ ] Duplicate, delayed, and reordered Stripe webhook events cannot create a
      second payment or rewrite a terminal payment fact.
- [ ] A failed payment or customer-action state triggers no automatic retry.
      Only an explicit user-authorized recovery action may continue payment.
- [ ] An unresolved review or payment keeps another paid challenge blocked until
      it is resolved or waived.
- [ ] Every sandbox screen says
      **Payment test mode — no real money moves.**
- [ ] Sandbox result screens distinguish $0, provisional review, test charge,
      customer action, and failure without implying that real money moved.
- [ ] The invite-only Release build exposes only Stripe sandbox; live Stripe
      remains disabled.
- [ ] Hosted sandbox deployment, webhook configuration, and reconciliation occur
      only after separate approval.
- [ ] Written Stripe, US legal, App Store, HealthKit, age, and jurisdiction gates
      remain open and are never inferred from sandbox success.

## Completion checklist

- [x] Local migrations and all 1,293 pgTAP assertions across 32 files pass;
      local `public` and `app` schema lint and security/performance advisors
      report no warning- or error-level findings.
- [ ] Hosted advisors pass after separate deployment approval.
- [x] Deno format, lint, check, and all 350 tests pass.
- [x] GameTimeCore passes all 103 tests across nine suites.
- [x] Full product matrix passes on a booted simulator: 103 unit and 10 UI tests,
      with zero failures and zero skips.
- [x] All 10 App Attest conformance simulator tests pass with zero failures and
      zero skips.
- [x] Unsigned Debug, Staging, and Release simulator builds pass. D83 accepts
      Xcode 26.2's expected no-AppIntents metadata self-skip; no dummy dependency
      or warning suppression was added.
- [x] `./scripts/test-all.sh`, bounded Markdown link/reference checks, and
      `git diff --check` pass.
- [x] Legacy backfill and privacy compatibility pass locally.
- [x] One-open concurrency and exact retries pass locally.
- [x] Seven-local-day and DST scoring pass locally.
- [x] Two-actor database privacy isolation passes locally.
- [x] Server-enforced `test_only` passes locally.
- [ ] Hosted Staging migration and worker proof passes after approval.
- [ ] Physical HealthKit and App Attest diagnostic passes.
- [ ] Physical manual sync, exact replay, and final grace sync pass.
- [ ] Physical background observer wake, durable upload, callback completion,
      and retry pass on the signed Staging build.
- [x] Personal result, outage waiver, hold, and diagnostic recovery pass in the
      local database suite.
- [ ] Logs and evidence artifacts contain no sensitive data.

Even when every Stage A item passes, it does not prove the Stripe sandbox. The
Release source may carry the forward test-mode slice, but hosted sandbox
deployment requires separate approval. Live payment, production migration,
TestFlight publication, App Store submission, and payment marketing claims
remain blocked by every live gate in `PLAN.md`.
