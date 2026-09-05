# How GameTime talks

GameTime's adopted direction is friend duels and personal performance
commitments. Today's app still offers seven-day Personal steps challenges.
Write for a person checking what they agreed to, how they are doing, and what
happens next. They are not reading a spec, an audit report, or a schema.
See [BUSINESS_MODEL.md](BUSINESS_MODEL.md) for the new journeys and rules.

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

**Reassure where the design already protects them.** On current Personal
screens, missing final step data means the week doesn't count against them.
New products must explain their own proof/review rule; never equate a missing
upload with a loss or promise protection the agreed policy does not provide.

**Name the payment mode before stating a consequence.** Internal Stage A is
test-only. The beta Release path uses Stripe sandbox transactions and simulated
payment states. Never let sandbox copy read like a live charge.

**State the exact payment trigger.** For the existing Personal contract, say
“confirmed miss after review,” not
“failure,” “forfeit,” or “we may charge you.” Always pair the trigger with the
frozen amount, $0 outcomes, and the fact that the charge is one-time rather than
recurring.

## Existing Personal payment copy contract

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

The confirmation receipt groups the frozen facts under **Your challenge**,
**When it starts**, and **Payment protection**, with no more than four facts in
each group. Longer start and cadence explanations, sandbox cancellation, and
the safe saved-draft explanation stay behind **More details**. Never show the
draft request identifier.

### Historical Personal live-copy proposal — inactive

The following proposed language belongs only to a future version of the old
Personal failure-contingent-charge model. It is not approved live copy and
must not be reused for a funded duel or a deposited performance commitment.
D123 supersedes the assumption that it defines GameTime's future business.
Preserve it as historical context; there is no live mode enabled. The proposed
explanation was:

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

## New duel and performance-commitment copy

The opt-in native duel uses the simulated mode and agreement patterns below.
Phase 2(d) adds saved notices, results, participant review and safe exits.
Phase 2(e) adds new-consent rematches and named-recipient links. Performance
commitment screens remain planned; their backend is implemented through
Phase 3(c). Keep existing Personal
consent/version text intact.
Use **Challenge again** for a new duel, **Create invitation link**, **Share
invitation**, and **Turn off this link** for person-initiated sharing. State that
only the invited friend can open the link and still needs to agree. Show the
link expiry. Turning off a link does not cancel the existing invitation; keep
that distinction next to the action. Never call a custom app link a public race
page, imply a message was delivered, or reuse a previous consent/return.

Friend, invitation, opponent, result, winner, and rematch are appropriate when
those concepts actually exist in the new journey. Do not label a charity
obligation a payout or show a new duel as an old Personal week.

- Simulated mode: **Simulated stakes — no real money moves.** At review show
  the two simulated amounts, fee $0, the timing rule, deadline and possible
  outcomes. Never call simulation a funded balance or money locked away.
- Agreement: **You both agree to these rules.** Show event/course, distance,
  chip or elapsed time, proof source, start/end, amount, fee, recipient and
  review/cancellation terms where applicable. An acceptance is never inferred
  from opening an invitation.
- Waiting for proof: **We're waiting for the race results.** Include the exact
  next deadline and action. Inconclusive: **We couldn't confirm this result.
  Neither of you loses your simulated stake.**
- Tie: **Same time — both simulated stakes returned.** Do not present a
  arbitrary winner when precision cannot distinguish the performances.
- Commitment: **Run 5K in under [time] before [date, year, time and zone].**
  Distinguish practice/milestones from an attempt that counts toward the goal.
- Review: **Ask us to review this result by [deadline].** Say what is paused
  and show confirmed server status; an opponent's acknowledgement is not
  an independent decision.
- Saved notice: **Latest result update** or **Earlier result update**. Show its
  original saved time and review deadline. A provisional notice is not final.
- Review receipt: **Your review request is saved.** Keep the request's update
  and reason visible. Map independent decisions to **Review complete — result
  upheld** or **Review complete — duel won’t count**. Never display a raw reason
  code or reviewer identity.
- Confirmed result and simulation are separate: **Result confirmed — simulated
  return update pending.** Only a recorded return can say **Simulated return
  recorded: [amount].** Follow with **Nothing can be paid out or redeemed. No
  real money moved.**
- Safe exit: **Withdraw from duel** or **Report an injury**. Confirm the action
  and explain that neither runner loses a simulated stake. A saved exit does
  not pretend the final result or simulated return is already recorded.
- Rematch: **Challenge again.** Show fresh rules and require both consents.

Any eventual live consent must accurately distinguish: a method saved with no
funds reserved; an expiring authorization; a captured deposit held by a named
provider; a confirmed refund; and a confirmed payout. Name who receives a
forfeiture and all fees before consent. Do not draft those promises by simply
removing “simulated” or “test.” They need the selected, approved funds flow.
Use claims such as “verified” only to describe the actual proof checked, not
as a guarantee against cheating. Avoid loss-chasing, humiliation, pressure to
run injured, or prompts to raise a stake after losing.

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
| metric | distance and time for a running goal; omitted on steps-only Personal screens |
| duel agreement / policy | challenge rules; what you both agreed to |
| qualifying attempt | an attempt that counts toward your goal |
| elapsed time | time from start to finish, including pauses |
| chip time | time from crossing the start to crossing the finish |
| simulation / simulated disposition | simulated stake / simulated result; no real money moves |
| proof revision / durable notice | saved result update; notice saved |
| participant case / resolution | your review request / review complete |
| contact suppression | contact details and shared results are hidden |
| follower projection | progress you chose to share |
| finality / settlement | result confirmed / the actual payment status, shown separately |
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
`assertNoForbiddenLanguage` currently fails the suite if a reachable Personal
screen uses the competitive-social vocabulary that version dropped. When new
routes are implemented, scope this check and the candidate copy audit to
Personal screens and add separate duel/commitment assertions. Do not remove
legacy checks globally. New friend/winner/rematch language is valid in the new
products; old financial consent remains exact. Changing a string usually means
changing an assertion; keep them in the same commit.

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
