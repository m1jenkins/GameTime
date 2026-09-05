# GameTime lean external beta launch plan — Stripe sandbox

> **Product scope — September 4, 2026.** This document is retained for the
> existing Personal steps/sandbox implementation and its dated acceptance work.
> Friend duels and personal performance commitments now control future product
> scope: see [BUSINESS_MODEL.md](BUSINESS_MODEL.md), [PLAN.md](../PLAN.md), and
> D123. Solo-only/no-participant-payout guidance below is not a constraint on
> those new products. Existing agreements and no-live-money restrictions remain.
> Old rollout commands/prompts are historical instructions, not authorization
> to deploy or distribute. Consult the current roadmap for the next build task.

**Revised:** August 13, 2026

**Target:** a small, invite-only external TestFlight beta

**Decision:** **Not ready to invite external testers today**

## August 13 Release/TestFlight demo-parity update

The unchanged **Start right now — count today** server contract is hosted on
the checked-in Staging project. The client continues to send the current-minute
marker, the server freezes the scored start at local midnight and activates
immediately, and an exact retry keeps the original marker. This is hosted
capability, not yet proof from the fresh processed Release build.

The candidate now also supports owner cancellation of a scheduled or
still-active sandbox challenge. The active exception is limited to internal
`test_only` with no provider agreement or a retained Stripe agreement whose
provider is `stripe`, environment is `sandbox`, and `livemode = false`.
Cancellation ends the challenge immediately, closes its terms, frees the open
slot, and retains cancelled history, frozen terms, activation time, the Stripe
test agreement, the Health snapshot, and the exact cancellation audit. It
cannot publish a result, open payment review, or create a charge command.

Awaiting-final-Health, completed, already-cancelled, other-account, and future
live-mode challenges remain non-cancellable. Apply the single new forward
migration and complete the authenticated create/start-now/cancel/history/
recreate smoke before distributing the client. Never use `--include-all`,
seeding, or migration repair for this rollout.

## August 12 automatic-progress replacement

This section controls wherever the older audit below refers to manual step
sync, signed metric/coverage queues, Personal App Attest, trusted diagnostics,
eligibility holds, positive-sample readiness, or a “final sync.” Those were the
`attested_hourly_v1` beta assumptions. New and migrated open Personal
challenges use `healthkit_nonmanual_daily_v1` and the acceptance gate is
[PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md](PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md).

The replacement beta contract is:

- one **Connect Apple Health** permission action, with no positive-sample gate;
- automatic local-first merged Health progress with explicit manual-entry
  exclusion, plus **Sync now** on the open challenge detail as an on-demand
  entry into that same refresh path;
- one owner-authenticated seven-day daily snapshot, with no Personal App Attest
  or coverage upload;
- a protected whole-snapshot cache and coherent live/cache/server/frozen display
  precedence;
- a 24-hour finalization period during which GameTime keeps checking Health;
- one immutable cutoff result, with missing/incomplete data waived;
- backend support and smoke first, mandatory v2 build second, eligible open-v1
  migration third, and result-Cron activation last.

Generic/social App Attest infrastructure and historical v1 records remain in
the repository. They are regression scope, not external Personal-beta gates.

## Short answer

GameTime is not hundreds of tests away from beta. In the August 5 snapshot, the
386 backend tests and 1,678 database assertions already existed; they are
automated regression checks, not future implementation tasks.

The first beta needs six contained workstreams: align the product and sandbox
contract, make one distribution build, finish the current client trust fixes,
add automatic results, finish deletion/privacy/support, and pass one bounded
TestFlight run including the sandbox review/settlement loop.

This plan gets GameTime to an **external beta**, not a public App Store launch.

## Locked first-beta scope

- No more than 10 named iPhone testers; no public TestFlight link.
- Personal Accountability with Steps and one seven-day challenge per person.
- Stripe sandbox payment setup, review, and simulated settlement only; live
  Stripe mode, social challenge, and Solo remain out of scope.
- A challenge defaults to the next local midnight, or the owner can start now
  and count eligible steps since today's local midnight. Custom hours stay dormant.
- The owner can cancel while scheduled or still active in the sandbox beta;
  the cancelled challenge remains in history and the saved test method is not
  charged. The action disappears during final Health collection and after a
  terminal state.
- Foreground Health refresh is automatic. Background observation is
  opportunistic and never replaces the foreground freshness guarantee.
- iPhone only; iPad and Apple Watch-specific acceptance wait.
- One monitored feedback email and a daily founder check during the first
  cohort.

The [automatic Personal acceptance document](PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md)
is the engineering reference. The older
[Personal V1 record](PERSONAL_V1_ACCEPTANCE.md) remains historical only.

The August 6 [product and design audit](BETA_PRODUCT_DESIGN_AUDIT.md) confirms
that these three tabs and the existing Personal loop are enough. Its
[implementation prompts](BETA_IMPLEMENTATION_PROMPTS.md) divide the remaining
work into bounded, paste-ready chats.

## The six remaining workstreams

### 1. Make the product contract agree

Update [PLAN.md](../PLAN.md), [DECISIONS.md](../DECISIONS.md),
[README.md](../README.md), acceptance copy, and the app only where they
contradict the scope above.

Keep custom-start, live-fee, Solo, and social history in the repository, but
expose only the Stripe sandbox path in the distribution build. Do not delete or
refactor historical paths for beta.

For the visible beta journey:

- Remove the redundant screen where Steps is the only metric choice.
- Remove the custom-start screen; keep next midnight as the default and expose
  one creation toggle for start now and count today before payment setup
  freezes the request.
- Use **Payment test mode — no real money moves.** wherever the beta
  explains payment setup or settlement.
- Put one state-aware next action and exact local deadline on Today.
- Surface honest Health, saved cancellation, detail-load, and overdue-result
  recovery.
- Keep the complete root journey in the existing fixed light appearance. Full
  dark-mode design remains deferred.

### 2. Make one shippable distribution build

Correct one Release configuration; do not create several new build flavors.
Keep Staging for internal engineering.

The distribution build needs:

- The final Apple App ID and matching Supabase Auth identity.
- Distribution signing for Sign in with Apple and HealthKit. App Attest remains
  relevant only to retained generic/legacy targets.
- The reviewed hosted beta backend and a public client key only.
- Personal creation, automatic Health reads, protected caching, and
  authenticated snapshot uploads enabled.
- `stripe_sandbox` settlement, a reachable payment screen, and test-mode
  provider configuration only.
- iPhone-only support, an app icon, a privacy manifest, and a unique build
  number.

Release is the distribution sandbox beta; Staging remains the internal
engineering build.

### 3. Finish proof for the automatic snapshot client

1. **Coherent local progress:** publish a successful whole Health snapshot to
   the UI and protected cache before network upload, including zero and lower
   corrections.
2. **Fail-closed availability:** keep Create disabled until authoritative open
   challenge state loads. Permission-request completion, not a positive Health
   sample, satisfies the creation Health gate.
3. **Automatic freshness:** prove every trigger, one-active/one-trailing
   coalescing, account/challenge cancellation, stale retention, and exact
   live/cache/server/frozen precedence.

Add focused tests for those behaviors only. Do not create a universal failure
matrix for every screen and action.

They are not candidate proof until the exact frozen revision passes the full
client/backend run, the v2 RPC/read/finalizer support is hosted, and the
automatic Health flow is exercised from the signed TestFlight build.

### 4. Add automatic Personal results

Use the existing protected assessment and publication operations. Add one small
scheduled worker that:

- Finds Personal challenges due after the 24-hour grace period.
- Publishes one immutable result using existing fail-closed rules.
- Is safe to rerun and safe beside a final snapshot upload.
- Leaves uncertain evidence `inconclusive`; it never guesses.
- Exposes an overdue/failure check that the founder reviews daily during the
  first cohort.

Keep the hosted sandbox payment setup, review, webhook, and idempotent test
settlement paths behind the beta allowlist and kill switch. Prove one result,
one incomplete result, one review outcome, one test settlement, and a safe
rerun in an accelerated hosted smoke test. Do not add a general job platform
or an operations dashboard.

The source checkpoint includes the bounded result-worker migration, focused
tests, and an inactive five-minute Cron registration. A later local migration,
`20260807151320_personal_stripe_sandbox_beta_controls`, adds the default-off
database switch, empty exact-owner allowlist, and replay-safe enforcement
boundary. Its focused tests and the full local suite pass, but it has not been
applied to the hosted project.

Treat both workers and controls as unhosted source. The existing hash-locked
five-migration packet predates the Stripe controls and must be regenerated for
the six-migration set before owner review, authenticated dry run, isolated
hosted smoke, and separate Cron or Stripe-control activation approval.

### 5. Finish deletion, privacy, and support

The substantial database deletion transaction already exists. Add only the
missing thin layer:

- Delete Account under You, with confirmation and fresh authentication.
- Sign in with Apple token revocation.
- The existing server deletion operation.
- Stripe test-Customer/payment-method deletion or exact disclosed retention.
- Local pending-request, App Attest, and session cleanup.
- Honest success, retry, and support states.

Apple requires account-creating apps to let people initiate deletion in the app
and says Sign in with Apple tokens should be revoked. See
[Apple's account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

Also add one public privacy-policy URL, one working support contact, short
test-only beta terms, and a check that logs contain no raw Health data, signed
bodies, credentials, or private profiles.

Use one **Account & Support** destination under You rather than several new
settings screens. It should contain Health help, Privacy Policy, Beta Terms,
Contact Beta Support, app version/build, sign out, and Delete Account. Reuse its
support route from launch, Health, cancellation, detail, result, and deletion
failures. Do not invent missing URLs or contact details.

### 6. Freeze, verify, and distribute one candidate

1. Freeze one reviewed commit and record its build number and backend versions.
2. Run the existing automated repository and Xcode suites once for that exact
   commit. Do not manually repeat green suites.
3. Smoke-test only the hosted beta surface: unauthenticated refusal, exact
   retry, two-account isolation, automatic result, Stripe test setup, signed
   webhook, review, and one idempotent simulated settlement.
4. Run the six TestFlight journeys below on the exact processed build.
5. Run the common journeys with VoiceOver and Larger Text, verify sufficient
   contrast and 44-point controls, and confirm that state is never color-only.
6. Add the minimum TestFlight information: beta description, What to Test,
   feedback email, review contact, privacy URL, reviewer-access instructions,
   Stripe-published test-card instructions with a never-use-a-real-card warning,
   and export-compliance answer.
7. Submit that same build for TestFlight App Review. Apple reviews the first
   external build before testers can join. See
   [Apple's TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).
8. After approval, invite no more than 10 named testers.

During the first cohort, check TestFlight crashes/feedback, backend errors, and
overdue challenges once per day. Stop new invitations if a core journey fails.
No third-party monitoring platform is required yet.

## Product and design completion checklist

The August 6 audit found no missing major feature family. Close these contained
gaps before the candidate freeze:

- [ ] Today states the next action and exact local deadline for scheduled,
      active, finalization-window, result-pending, overdue, and final states.
- [x] The visible creation journey has no one-option metric page or custom
      start; only the Stripe sandbox payment route is reachable, and its copy
      always identifies test mode.
- [ ] Health no-data recovery says access may be limited or data may be absent;
      it never claims Apple revealed read denial.
- [ ] Saved cancellation, detail-load, and overdue-result failures have Retry,
      Refresh where appropriate, and a shared support route.
- [ ] Account & Support uses real Privacy Policy, Beta Terms, and monitored
      support destinations and displays the app version/build.
- [ ] Signed Out and configuration failure expose working privacy/terms/support
      actions before account creation.
- [ ] Payment consent links those documents and accurately says Stripe handles
      test payment details; the app never claims those details stay only with
      GameTime.
- [ ] Testers are told never to enter a real card and receive only Stripe's
      published test-card instructions.
- [ ] Delete Account completes fresh authentication, Apple token revocation,
      Stripe test-data handling, server deletion, confirmed local cleanup, and
      retry/support states.
- [ ] Challenge detail shows review-open, under-review, waived/no-charge,
      simulated-charge pending/succeeded, requires-action, and failed states
      from the authoritative sandbox status.
- [ ] Requires-action or failed test settlement has one explicit
      user-authorized recovery or founder-waiver path and cannot block the
      tester forever.
- [x] Local Stripe setup/commit/dispatch source is protected by a
      database-enforced beta allowlist and global kill switch; status, signed
      webhook reconciliation, and audited no-charge/waiver resolution remain
      safe when disabled. Hosted application and activation remain unproven and
      separately approval-gated.
- [ ] The complete root journey remains legible when the phone uses dark
      appearance, while GameTime intentionally ships fixed-light for beta.
- [ ] The exact candidate passes common journeys with VoiceOver, Larger Text,
      contrast, 44-point touch targets, and non-color state communication.
- [ ] App Review access and accurate review notes are documented without
      inventing credentials or a hidden demo path.

Keep permanent-username simplification, full dark mode, reminders, charts,
streaks, and broader statistics as post-cohort decisions.

## Test policy

- In the August 5 snapshot, 386 backend tests were existing Deno unit and
  endpoint checks across 28 files and finished in about two seconds.
- In that same snapshot, 1,678 pgTAP assertions were fine-grained database
  checks from 41 SQL files. They were one automated job, not 1,678 manual
  scenarios.
- Legacy social, dormant Solo, and Stripe sandbox tests stay as regression
  protection; they are not a reason to expand the beta surface.
- There is no new test-count goal. Add focused coverage only for the actual
  launch fixes, then run one full green candidate gate.
- A simulator cannot prove Apple Health values, observer wakes, locked-device
  retry, or Watch catch-up. One real TestFlight phone still matters. Personal
  App Attest is not part of this proof.

## One bounded TestFlight acceptance pass

Use the exact processed distribution build for six journeys:

1. **Identity:** fresh install, Sign in with Apple, onboarding, relaunch, and
   sign-out/sign-in restoration.
2. **Creation:** confirm next-midnight terms, sandbox payment setup and consent,
   Health readiness, one created challenge, and a clear first next action.
3. **Automatic Health progress:** real iPhone Health data, no-tap refresh across
   every surface, exact finalization deadline, Watch catch-up, offline/local
   display, and one privacy-safe no-access/no-data recovery.
4. **Recovery:** offline/lost response, exact retry, duplicate tap, active
   Stripe-sandbox cancellation with visible saved retry and retained history,
   detail failure, relaunch without duplicate data, and successful creation of
   another challenge.
5. **Backend safety and sandbox settlement:** accelerated automatic result,
   result-pending/overdue guidance, review request/decision, signed webhook,
   idempotent simulated test settlement with visible final status, and one
   two-account privacy check.
6. **Deletion:** in-app deletion, Apple token revocation, local cleanup, and
   account recreation.

Automated fixtures cover met, missed, inconclusive, outage, quarantine,
daylight-saving, concurrency, and other state permutations. Do not repeat each
one as a physical seven-day run.

The first cohort should complete one genuine seven-day challenge plus its
24-hour grace period before expanding beyond 10 people. That is a beta learning
goal, not a reason to delay the first controlled cohort after the accelerated
result path passes.

## Explicitly deferred

- Live Stripe mode, real-money charging, counsel, processor approval, and live
  reconciliation.
- Social, friends, standings, reactions, charities, and Solo.
- Custom-hour starts and partial first days.
- Guaranteed background delivery remains deferred; opportunistic observer and
  Apple Watch catch-up acceptance are required for the current automatic flow.
- iPad support, screenshots, and QA.
- Upgrade/minimum-build/90-day-expiration drills.
- Blanket closure of every historical Supabase advisor warning; review only the
  beta surfaces reachable by testers and keep dormant paths disabled.
- Per-device abuse systems, third-party crash tooling, restore drills, incident
  simulations, and a custom operations dashboard.
- Full App Store screenshots, keywords, localization, marketing copy, dark
  mode, reminders, and other general-release polish.

## Go/no-go

Invite the first external cohort only when:

- [ ] The processed build is iPhone-only, `stripe_sandbox`, and uses test-mode
      provider keys and transactions.
- [ ] The Release/TestFlight client points to an explicitly non-production
      Stripe beta backend; hosted labels and runtime environment values agree.
- [ ] Concurrent Watch work is preserved but not embedded or reachable in this
      candidate.
- [ ] Its final Stripe redirect scheme returns correctly on the processed
      TestFlight build.
- [ ] Its Apple/Supabase identity, signing, icon, and privacy manifest are
      correct.
- [ ] Automatic Apple Health refresh, manual-entry exclusion, offline display,
      Watch catch-up, and exact cutoff freezing pass on TestFlight.
- [ ] Unknown server state cannot enable creation, and saved retries recover.
- [ ] Next-midnight terms agree across app, backend request, and tester copy.
- [ ] Today gives the correct next action and exact local deadline in every
      reachable challenge/result state.
- [ ] Health, cancellation, detail, and overdue-result recovery is honest and
      actionable.
- [ ] Active Stripe-sandbox cancellation ends immediately, remains in history,
      creates no payment workflow, and releases the slot for another challenge.
- [ ] The hosted Personal worker publishes one result and safely reruns.
- [ ] Hosted sandbox payment setup, review, webhook, and test settlement safely
      rerun, remain allowlisted, and appear honestly in challenge detail.
- [ ] In-app deletion/recreation and two-account isolation pass.
- [ ] Account deletion handles the Stripe test Customer/payment method exactly
      as the in-app policy promises.
- [ ] Account & Support uses working privacy/terms/support links, shows the
      version/build, and the feedback inbox is monitored.
- [ ] Common journeys pass VoiceOver, Larger Text, contrast, touch-target, and
      fixed-light appearance checks.
- [ ] Reviewer access and accurate App Review notes are ready.
- [ ] One full candidate run and the six TestFlight journeys pass.
- [ ] TestFlight App Review approves the exact build.
- [ ] No known crash, privacy leak, authentication failure, duplicate challenge,
      lost evidence, stuck result, or accidental live-money path remains.

## Evidence boundary

The August 5 audit recorded green local database, backend, Swift, simulator,
and conformance suites. That is a strong regression foundation, but it does not
prove a signed TestFlight journey.

The August 6 design/function audit was read-only. Its Personal App Attest and
manual-sync findings are retained historical context. Neither they nor the
result-worker draft are snapshot-v2 candidate or hosted proof.

The beta list also changed during the audit from no-payment Stage A to a Stripe
sandbox rehearsal. `PLAN.md`, `DECISIONS.md`, copy, hosted scope, and reviewer
notes must agree on that choice before the candidate freezes.

Still unproved: the final processed build, automatic physical-device Health
flow, hosted snapshot/frozen-result operation, hosted sandbox payment operation,
in-app deletion, the two-account pass, full common-journey accessibility,
reviewer access, and TestFlight App Review approval.

This plan does not authorize Apple-account changes, hosted deployment,
migrations, Edge Function publication, TestFlight upload, or invitations. Each
consequential external step still requires explicit approval.
