# How GameTime talks

GameTime is a personal accountability app. The person reading a screen is
someone who committed twenty dollars to walking 10,000 steps a day and wants to
know how they are doing. They are not reading a spec, an audit report, or a
schema.

The product's domain vocabulary — *snapshot*, *frozen terms*, *observation*,
*query-through*, *inconclusive*, and *cadence* — is precise, and it should stay
precise in the code, schema, and `DECISIONS.md`. Historical and generic systems
also retain *evidence*, *coverage*, and *attestation*. None of it belongs on a
Personal screen. Verification is what GameTime does *for* someone; making them
learn its vocabulary hands them the work instead.

## The rules

**Write what the person sees or needs to do, not what the system computed.**
"Updated from Apple Health 3 min ago" beats "snapshot observed at 14:03 and
queried through 14:02." Same fact, no glossary.

**Every error says what happened and what to do next.** "The snapshot uploader
rejected this observation" tells someone nothing they can act on. "We couldn't
update Apple Health right now. Your last update is still here." does.

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

**Keep build and infrastructure detail out of shipping screens.** "This RPC is
authenticated" or "App Attest is legacy-only" is a note to a developer that a
user found by accident.

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
- Saved method: **Test method saved. No test charge exists.**
- Consent: **By starting, you agree that GameTime may create one \(amount) test
  charge only if this challenge is confirmed missed after the review window.
  Missing or unclear step data never counts as a miss.**
- Met goal: **Goal met — $0 test charge.**
- Inconclusive or waived: **This one didn't count — $0 test charge.**
- Cancelled or otherwise closed without a result: **Challenge closed — $0 test
  charge.**
- Provisional miss: **Goal missed — review open. Settlement is paused. Ask us to
  review this result by \(reviewDeadline).**
- Expired provisional miss: **Review window ended — settlement update pending.**
- Review pending: **Under review — settlement paused.**
- Confirmed miss: **Processing one \(amount) test charge.**
- Test payment complete: **Test charge complete — sandbox transaction recorded.**
- Failed or customer action required: **Test payment needs your attention. We
  won't try again automatically.**
- Unavailable: **Payment test status could not be confirmed.**
- Stale last confirmation: **Last confirmed \(checkedAt). We couldn't refresh
  it.**
- Sandbox cancellation confirmation: **This ends the challenge immediately.
  It will stay in your history, and your saved test payment method will not be
  charged.**

Challenge detail presents these states in one **Payment test status** card.
The result card states only how the challenge ended; it never infers review or
settlement state from result timing. An under-review state never promises a
resolution deadline. For nonterminal, attention, failed, stale, and unavailable
states, the only recovery actions are **Refresh** and **Contact Support**.
There is no client-side payment retry, automatic retry claim, or locally authored
settlement transition. Review submission is enabled only for a fresh,
server-confirmed `review_open` state whose exact server deadline is still in
the future. When a previously confirmed review form is retained during Refresh
or after a failed refresh, every review control stays disabled until a fresh
confirmation returns.

Show the saved payment method by brand and last four digits when Stripe provides
them. Never show a full payment number, Stripe identifier, `SetupIntent`,
`PaymentIntent`, mandate, webhook, or idempotency language.

### Placement: disclose the environment once, protect each decision

The compact environment banner is the canonical ambient disclosure. Show it
once above the app root in every test-only and Stripe-sandbox configuration:

- **Test commitment — no money will be charged.**
- **Payment test mode — no real money moves.**

Use the same compact component once inside a presented creation sheet because
the sheet covers the root banner. Interactive Demo replaces it with **Demo mode
— no money will be charged. Nothing here leaves your phone.** Do not repeat the
environment promise in ordinary Today, Challenges, You, Privacy, detail, or
signed-out cards. The shared accessibility identifier is
`personal.environment-disclosure`.

Detailed protection copy belongs where a choice has consequences: beside the
selected amount, during test-payment consent, on the confirmation receipt, and
beside a final result or review action. Repetition at those decision points is
intentional. Keep the exact Stripe consent sentence and payment trigger
unchanged; changing placement never changes the agreement or its version.

Beside the selected amount, the $0 path and the one-time miss charge share the
same paragraph. Follow it with **This is not a subscription.** Amount tiles stay
equal; the selected amount is a check, not a larger or louder tile.

The confirmation receipt groups the frozen facts under **Your challenge**,
**When it starts**, and **Payment protection**, with no more than four facts in
each group. The confirmation action is **Start this challenge**. In Stripe
sandbox it stays disabled until the consent checkbox is on. Longer start and
cadence explanations, sandbox cancellation, and the safe saved-draft
explanation stay behind **More details**. Never show the draft request
identifier.

### Future live copy

Live mode uses the same outcome rules without “test” language. Its primary
explanation is:

**Meet your goal and pay $0. If GameTime confirms you missed after the final
Apple Health check and review, we'll charge \(amount) once. This is not a
subscription.**

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
| snapshot steps, historical trusted steps | steps |
| snapshot observation/update time | "Updated from Apple Health 3 min ago" |
| stale retained snapshot | "Last updated … · Apple Health is temporarily unavailable" |
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
| Health permission request | Connect Apple Health |
| App Attest, attestation, provenance | *(legacy/generic only; never shown on Personal)* |
| historical evidence, coverage, diagnostic, eligibility hold | *(legacy v1 only; never shown on Personal v2)* |
| inconclusive, waived | didn't count; "it doesn't count against you" |
| evidence cutoff, snapshot cutoff | "We'll keep checking Apple Health through …" |
| no successful snapshot | "No step data available yet" plus Apple Health settings help |
| local day | day |
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
`PersonalPaceComponents.swift`, `AppModel.swift`, and `DomainModels.swift`.
`PersonalSyncCoverage.swift`, `SupabaseMetricUploadClient.swift`, and
`ActivitySyncCoordinator.swift` contain historical/generic error copy only and
must not feed a Personal-v2 screen.

`GameTimeUITests` asserts on visible copy in several places, and
`assertNoForbiddenLanguage` fails the suite if a reachable screen uses the
competitive-social vocabulary Personal V1 dropped (*friend*, *invitation*,
*standings*, *winner*, *charity*, *tie-break*, and friends). Changing a string
usually means changing an assertion; keep them in the same commit.

Payment copy also requires tests for sandbox versus live configuration; all nine
authoritative sandbox states (`method_saved`, `review_open`, `under_review`,
`waived`, `no_charge`, `charge_pending`, `charged`, `requires_action`, and
`collection_failed`); expired review, stale and unavailable reads; all $0
outcomes; and scheduled/active sandbox cancellation. Never make a sandbox
fixture or screenshot look like a real charge, and never expose a payment-retry
action.

Accessibility identifiers are test hooks, not copy. Personal v2 must not retain
the removed `personal.sync`, `personal.sync.pending`,
`personal.diagnostic.run`, or `personal.eligibility-hold` hooks. The one
permission action should use a Health-connect identifier consistently.
