# Decisions

Every non-obvious choice, why it was made, and what would make us revisit it.
Append; do not rewrite history. Newest milestone at the bottom.

Format: **What** / **Why** / **Rejected** / **Revisit if**.

---

## M0 — Scaffold, local Supabase, test harness, CI

### D1. Stack: Supabase (Postgres + RLS + Edge Functions), as specified

**What.** No counter-proposal. Building on Supabase as briefed.

**Why.** Postgres is the correct shape for an append-only evidence ledger and a
scoring engine: partial unique indexes give idempotent ingest for free, triggers
give append-only enforcement at a layer no client can route around, and RLS lets
contest-membership access rules be written once as executable policy rather than
re-implemented in every endpoint. Edge Functions put attested ingest and
scheduled settlement in the same repo and the same deploy as the schema. The
whole thing runs locally, which is non-negotiable for work whose correctness
argument is "here are six fraudulent fixtures and here is what the engine does
with them."

**Rejected.** A bespoke Node/Postgres service (more control, but we would
hand-roll auth, RLS-equivalent authorization, and storage, and the
authorization logic would drift from the schema). Firebase (document store is
a poor fit for a ledger with cross-row invariants and no real transactional
scoring). CloudKit (tempting for an Apple-only app, but no server-side scoring
engine, no cron, and no way to enforce provenance rules server-side, which is
the entire product).

**Revisit if.** Edge Function cold starts make hourly settlement unreliable at
scale, or the scoring engine outgrows the Deno execution limits. Both would
argue for moving the cron worker to a container, not for changing the database.

### D2. iOS deployment target: 18.0

**What.** `platforms: [.iOS(.v18)]`, Swift 6 language mode.

**Why.** The brief said to check the installed Xcode/SDK and pick current minus
two majors. **I could not check**: this backend was built in a Linux container
with no macOS, no Xcode, and no `xcodebuild`. So this is a reasoned pick, not a
measured one, and it needs confirming against the actual toolchain.

Reasoning: the current shipping SDK is iOS 26.x. Apple's version sequence jumped
17 → 18 → 26, so "current minus two majors" reads literally as iOS 17, which is
a 2023 OS. iOS 18.0 is one real generation back, covers the overwhelming
majority of active devices, and buys mature `@Observable`, clean Swift 6 strict
concurrency, and modern SwiftUI navigation with no availability guards. Every
framework this app depends on — HealthKit background delivery, App Attest,
CoreLocation region monitoring, CoreMotion — long predates it, so nothing in the
product is gated on going newer.

**Rejected.** iOS 17 (the literal reading; costs concurrency ergonomics and adds
availability guards for no product gain). iOS 26 (no guards at all, but cuts the
device base hard for an app that spreads through existing friend groups).

**Revisit if.** `xcodebuild -version` on the real machine shows something
unexpected, or a required API turns out to be 26-only.

> **Action for the owner:** run `xcodebuild -version && xcodebuild -showsdks` and
> confirm. One line in `Package.swift` changes if this is wrong.

### D3. One scoring engine, in TypeScript

**What.** The deterministic scoring function lives in
`supabase/functions/_shared/` and is the only implementation. The client renders
server-computed standings; it does not score.

**Why.** Two implementations of a scoring engine are two answers to "who won",
and the difference will surface as a dispute between friends. A single engine
removes the drift risk entirely. TypeScript over plpgsql because the engine has
to be exercised against fixture time series including deliberately fraudulent
ones, and fixtures, table-driven tests, and structured integrity summaries are
far easier to express in TS than in SQL.

Swift Testing still has real work: hourly bucketing, provenance extraction from
`HKSample` metadata, on-device dwell computation, and idempotent replay of the
offline queue. That is client domain logic, and it is tested as such.

**Rejected.** Mirroring the engine in Swift for optimistic offline standings
(buys instant UI and a cross-check, costs a permanent lockstep obligation on the
most correctness-sensitive code in the product). plpgsql (closest to the data,
but awkward for integrity heuristics and materially harder to fixture-test).

**Revisit if.** Offline standings become a product requirement. The escape hatch
is a shared JSON fixture corpus that both implementations must pass — design the
fixtures in that format now so the option stays open.

### D4. Group contests are winner-takes-all

**What.** One winner per group contest. Every other participant gets their own
settlement row for the full donation amount, all directed to the winner's chosen
charity. A group of five produces four settlements.

**Why.** Keeps per-person exposure capped at the stake they agreed to, which
matters when the product is a pledge to actually donate money. Also keeps the
duel and group cases structurally identical: a settlement is always
(winner, loser, amount, charity), and a duel is the N=2 case. One settlement
shape, one lifecycle, one set of tests.

**Rejected.** Pairwise round-robin (richer, but a group of five exposes each
person to 4× their stake — a real financial-harm surface for a charity app, and
it multiplies dispute surface). Pass/fail against individual targets (a
different product: group-as-support-network rather than competition).

**Revisit if.** Group contests get used as leagues, where round-robin is the
natural fit. Note this is adjacent to the out-of-scope public-leagues seam.

### D5. Daily cadence uses each participant's own timezone, frozen at join

**What.** `contest_participants` stores an IANA timezone captured when the
participant joins. Day boundaries for daily-cadence goals are computed in that
zone. Changing it mid-contest requires opponent consent and raises an integrity
flag.

**Why.** "Did you hit 10k on Tuesday" should mean the participant's Tuesday;
anything else penalizes whoever lives furthest from the contest creator. Freezing
at join is what makes that safe: a live timezone would let a participant fly
their day boundary backwards to reopen a day they had already lost, which is a
clean exploit against the monotonic-counter rule.

**Rejected.** Contest-level fixed zone (trivially auditable, unfair across
cities). UTC (simplest, but a US day would roll over mid-afternoon and generate
disputes that are our fault, not the users').

**Revisit if.** Real users travel across zones often enough that frozen zones
feel wrong. The consent-plus-flag path already exists for that case.

### D6. Hard invariants in SQL, heuristics in TypeScript

**What.** A split, applied consistently:

- **Database** (cannot be bypassed): append-only enforcement, idempotency via
  unique constraints, monotonic counters, RLS membership rules, finalized-contest
  immutability, referential integrity.
- **TypeScript** (needs judgment and tuning): cadence plausibility ceilings,
  cross-metric corroboration, impossible travel, integrity scoring.

**Why.** Anti-cheat rules divide cleanly into two kinds. Rules 1, 2, 3, 8, and 10
are absolutes with no tuning parameter — they belong where a bug in application
code cannot defeat them. Rules 4, 5, and 7 are thresholds that will be tuned
against real data and must produce a flag with a severity and a JSON detail
blob, not a rejection. Putting a tunable heuristic in a CHECK constraint would
mean a migration every time we adjust a ceiling.

**Revisit if.** A heuristic stabilizes enough to become an invariant.

### D7. pgTAP is installed by the test script, not by a migration

**What.** `scripts/db-test.sh` runs `create extension pgtap` after
`supabase db reset` and before `supabase test db`. No migration references it.

**Why.** pgTAP is test scaffolding. Shipping roughly a thousand assertion
functions to production to satisfy a local test runner is the wrong trade, and a
migration is the wrong place to express "this exists only where tests run."
Ordering matters: `db reset` drops it, so the install has to sit between.

**Rejected.** A migration (the common Supabase pattern; simpler, but leaks test
tooling into every environment).

### D8. Realtime and analytics are disabled in the local stack

**What.** Both off in `config.toml`.

**Why.** Nothing in v1 needs a websocket — standings are recomputed hourly by
cron and read on demand. Realtime also runs an Ecto migration at boot with a
15-second DB timeout, which was the first thing to fail on a cold or
resource-constrained machine (it failed repeatedly here before being disabled).
Analytics is the heaviest container in the stack and we do not consume it.
Turning both off makes local start and CI faster and more reliable.

**Revisit if.** Live standings during the final hours of a contest become a
product goal. Realtime is a config flag away.

### D9. Edge Functions are exported handlers, tested under plain Deno

**What.** Every function exports a pure `handler(req: Request): Promise<Response>`
and calls `Deno.serve(handler)` only at its entry point. Tests import the handler
and invoke it directly; they do not go through the edge-runtime container.

**Why.** Faster and far less environment-dependent — a handler test is a function
call, not a container boot and an HTTP round trip. It also forced itself on us:
the sandbox this was built in caps `RLIMIT_NOFILE` at 4096 without
`CAP_SYS_RESOURCE`, and the edge-runtime container will not start under that
limit. The design is better regardless, so it stays.

**Revisit if.** Never, for unit tests. Integration tests that need the real
runtime should run on a host that can start it.

### D10. The client splits into a portable core and an app target

**What.** `ios/GameTimeCore` is a SwiftPM package with no Apple framework
imports; it builds and tests on Linux CI. The Xcode app target (M8) depends on it
and holds everything that needs a device: HealthKit, CoreLocation, DeviceCheck,
SwiftUI.

**Why.** It makes client domain logic genuinely CI-tested rather than tested only
when someone opens Xcode. It also forces device dependencies behind protocols,
which is what makes bucketing and dwell logic testable without a device at all.

**Revisit if.** Nothing foreseeable. This one is close to free.

### D11. App Attest has a development bypass, guarded against deployment

**What.** `ATTEST_DEV_BYPASS=true` lets ingest accept a stub assertion.
`assertAttestConfigIsSafe()` throws at module load if the bypass is on while
`SUPABASE_ENV` is `staging` or `production`, taking the function down at boot.

**Why.** The backend has to be testable without a physical Apple device, and App
Attest fundamentally cannot be satisfied off-device. The bypass is therefore
necessary and is also a total defeat of anti-cheat rule 9 — so it is guarded at
the only moment that matters, and the failure mode is a function that refuses to
start rather than one that quietly accepts unattested data. Boolean parsing is
strict (`"1"` and `"yes"` are rejected, not coerced) so a typo in a security flag
fails loudly instead of landing on a default.

**Revisit if.** We get a device-backed integration environment; the bypass can
then be restricted to `local` alone.

### D12. Sign in with Apple only; email signup disabled

**What.** `[auth.email].enable_signup = false`, Apple provider enabled.

**Why.** As briefed. Making it explicit in config means a stray client cannot
mint an identity outside the Apple trust chain, which matters because device
attestation and reliability scores are both anchored to a durable identity.

### D13. Migrations are hand-written SQL; pg-delta is not relied on

**What.** Every schema change is an SQL file under `supabase/migrations/`. The
CLI's diff engine is not part of the workflow.

**Why.** As briefed, no dashboard changes. Beyond that: this schema carries
constraints, triggers, and RLS policies whose intent is not recoverable from a
diff. A generated migration would produce correct DDL with none of the reasoning,
and the reasoning is the part worth version-controlling.

Also practical — the CLI's pg-delta catalog cache could not initialize in this
sandbox (it fetches from npm inside a container that does not trust the local
proxy CA). It emits a warning and nothing depends on it.

---

## Decisions deferred, with a current default

Recorded so they are not silently made later. Each has a working default;
each gets its own entry above when it is actually implemented.

- **Tie-break menu (M2).** Declared at contest creation, never ad hoc. Proposed
  options: highest integrity score → earliest to reach target → both donate →
  void. Default: highest integrity score, which makes clean data the
  tie-breaker.
- **Quarantine approval in group contests (M5).** A retroactively-written sample
  counts only if approved. In a duel that means the opponent. In a group,
  proposed rule: a majority of other active participants, failing closed —
  no response inside the review window means the sample stays excluded.
- **Reliability score formula (M7).** Proposed: a decayed ratio of confirmed
  settlements to total obligations, so one old default does not brand someone
  permanently.
- **Charity reference data (M2).** Seed a small curated list with EIN and
  donation slug. No IRS Pub 78 import in v1.
- **Integrity score scale (M5).** Proposed: start at 100, subtract per-flag
  severity weights, floor at 0. Never auto-disqualifies; it is displayed and it
  strengthens a dispute.
