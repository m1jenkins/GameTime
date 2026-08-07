# How GameTime talks

GameTime is a personal accountability app. The person reading a screen is
someone who committed twenty dollars to walking 10,000 steps a day and wants to
know how they are doing. They are not reading a spec, an audit report, or a
schema.

The product's domain vocabulary — *trusted evidence*, *frozen terms*,
*coverage*, *eligibility hold*, *inconclusive*, *cadence*, *attestation* — is
precise, and it should stay precise in the code, the schema, `DECISIONS.md`,
and the ledger. It does not belong on screen. Verification is what GameTime
does *for* someone; making them learn its vocabulary hands them the work
instead.

## The rules

**Write what the person did or needs to do, not what the system computed.**
"We have your steps for 18 of 24 hours" beats "18 of 24 completed local-hour
intervals covered." Same fact, no glossary.

**Every error says what happened and what to do next.** "The staging service
rejected personal step coverage." tells someone nothing they can act on. "We
couldn't sync your steps. Try again in a moment." does.

**Name the actor.** Prefer "we" for GameTime and "you" for the person. Passive
constructions — *was observed*, *could not be verified*, *is required* — hide
who is doing what, and they are the main reason copy drifts into sounding like
a compliance report.

**Never expose an internal identifier as prose.** A reason code with its
underscores swapped for spaces (`identity_mismatch` → "identity mismatch") is
still a reason code. Map known codes to sentences; show unknown ones as an
explicit `Reference: <code>` so nobody mistakes it for English.
`PersonalReasonText` in `PersonalAccountabilityComponents.swift` is where that
mapping lives.

**Keep build and infrastructure detail out of shipping screens.** "App
Attest-signed upload runs in Staging on a provisioned device" is a note to a
developer that a user found by accident.

**Reassure where the design already protects them.** Fail-closed scoring is
generous by design, so say it that way: missing data means the week doesn't
count, and it never counts against them.

**Name the payment mode before stating a consequence.** Internal Stage A is
test-only. The beta Release path uses Stripe sandbox transactions and simulated
payment states. Never let sandbox copy read like a live charge.

**State the exact payment trigger.** Say “confirmed miss after review,” not
“failure,” “forfeit,” or “we may charge you.” Always pair the trigger with the
frozen amount, $0 outcomes, and the fact that the charge is one-time rather than
recurring.

## Payment copy contract

The beta Release path uses the Stripe sandbox contract below. Debug and
historical Stage A fixtures remain separate internal test modes; hosted payment
operation is still a release gate.

### Current Stage A test-only copy

Use **Test commitment — no money will be charged.** for internal Stage A
fixtures.
The beta Release build uses the Stripe sandbox copy below.

### Forward Stripe sandbox copy

Use these exact patterns in the sandbox UI:

- Global banner: **Payment test mode — no real money moves.**
- Payment setup: **Add your test payment method before you start.** Pair it
  with the exact trigger below.
- Consent: **By starting, you agree that GameTime may create one \(amount) test
  charge only if this challenge is confirmed missed after the review window.
  Missing or unclear step data never counts as a miss.**
- Met goal: **Goal met — $0 test charge.**
- Inconclusive or waived: **This one didn't count — $0 test charge.**
- Provisional miss: **Goal missed — review open. Settlement is paused. Ask us to
  review this result by \(reviewDeadline).**
- Review pending: **Under review — settlement paused.**
- Confirmed miss: **Processing one \(amount) test charge.**
- Test payment complete: **Test charge complete — sandbox transaction recorded.**
- Failed or customer action required: **Test payment needs your attention. We
  won't try again automatically.**
- Pre-start cancellation: **Cancel before your challenge starts to close the
  payment terms before settlement.**

Show the saved payment method by brand and last four digits when Stripe provides
them. Never show a full payment number, Stripe identifier, `SetupIntent`,
`PaymentIntent`, mandate, webhook, or idempotency language.

### Future live copy

Live mode uses the same outcome rules without “test” language. Its primary
explanation is:

**Meet your goal and pay $0. If GameTime confirms you missed after final sync
and review, we'll charge \(amount) once. This is not a subscription.**

The live consent is:

**By starting, you authorize GameTime to charge \(amount) once only if this
challenge is confirmed missed after the review window. Missing or unclear step
data never counts as a miss.**

Do not ship this live copy until Release payments, Apple and Stripe approval,
legal terms, age and jurisdiction checks, hosted deployment, and live acceptance
are complete.

## The glossary

Left is what the system calls it. Right is what a screen calls it. If you need
a new term, add a row rather than inventing a second name for something here.

| Domain term | On screen |
| --- | --- |
| trusted steps, trusted activity | steps |
| evidence, coverage | step data, your steps, hours we have |
| trusted sync | synced ("Last synced 2 hours ago") |
| frozen terms | what you signed up for; "this locks in when you start" |
| cadence | how it counts |
| daily / cumulative | Every day / Week total |
| legacy Stage A commitment | amount ("Test commitment — no money will be charged.") |
| Stripe sandbox commitment | amount ("Payment test mode — no real money moves.") |
| settlement mode | *(not shown; the environment disclosure covers it)* |
| saved payment method, `SetupIntent` | payment method; "Test method saved" |
| off-session mandate | the exact one-time authorization sentence |
| provisional `missed_goal` | goal missed; review open |
| `review_deadline` | review by |
| off-session `PaymentIntent` | one-time charge |
| failed payment, customer action required | payment needs your attention |
| metric | *(not shown while steps are the only option)* |
| diagnostic, trusted diagnostic | Health check |
| App Attest, attestation, provenance | *(never shown; say "verify" or nothing)* |
| eligibility hold | paused; "New challenges are paused" |
| inconclusive, waived | didn't count; "it doesn't count against you" |
| evidence cutoff, final sync window | last chance to sync |
| local day, local-hour interval | day, hour |
| pending creation, retry record | draft |
| protected storage | saved on your phone |
| handle | username |
| surface, route, view | *(never shown)* |
| Staging, Debug, HealthKit, Supabase | *(never shown; describe the effect)* |

## Where the copy lives

User-facing strings are Swift literals in the view layer and in the
`errorDescription` of each `LocalizedError` — `PersonalChallengeFlow.swift`,
`PersonalChallengeDetailView.swift`, `TodayView.swift`, `YouView.swift`,
`ChallengesView.swift`, `PersonalAccountabilityComponents.swift`,
`AppModel.swift`, `DomainModels.swift`, `PersonalSyncCoverage.swift`,
`SupabaseMetricUploadClient.swift`, and `ActivitySyncCoordinator.swift`.

`GameTimeUITests` asserts on visible copy in several places, and
`assertNoForbiddenLanguage` fails the suite if a reachable screen uses the
competitive-social vocabulary Personal V1 dropped (*friend*, *invitation*,
*standings*, *winner*, *charity*, *tie-break*, and friends). Changing a string
usually means changing an assertion; keep them in the same commit.

Payment copy also requires tests for sandbox versus live configuration, all $0
outcomes, provisional review, charge success, customer action, failure, and
pre-start cancellation. Never make a sandbox fixture or screenshot look like a
real charge.

Accessibility identifiers (`personal.sync`, `personal.create`, …) are test
hooks, not copy. Rewording a label should never change one.
