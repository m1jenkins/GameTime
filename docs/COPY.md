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
| commitment, test commitment | amount ("This is a test — no money will be charged.") |
| settlement mode | *(not shown; the test disclosure covers it)* |
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

Accessibility identifiers (`personal.sync`, `personal.create`, …) are test
hooks, not copy. Rewording a label should never change one.
