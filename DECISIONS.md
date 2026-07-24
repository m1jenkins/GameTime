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

## M1 — Identity, friendships, groups, blocks

### D14. citext is compared as `lower(x::text)`, never with `=`

**What.** Every handle and join-code comparison inside a `search_path = ''`
function is written `lower(col::text) = lower($1)`. Never `col = $1`, even when
both sides are citext.

**Why.** citext's `=` operator lives in the `extensions` schema. Under
`search_path = ''` it is not visible, so the planner falls back to `text = text`
through citext's implicit cast and the comparison silently becomes
case-sensitive. No error, no warning, just wrong answers. Verified rather than
assumed: with `MikeJ` stored, `handle = 'mikej'::extensions.citext` inside such a
function returns false.

What makes it dangerous is the half that keeps working. A unique index on a
citext column has its operator class resolved at DDL time and stored in the
catalog, so handles stay case-insensitively unique regardless of search_path.
The result would have been a system where `@MikeJ` reliably prevents anyone else
registering `@mikej`, and where looking up `mikej` finds nobody — friend-adding
broken for exactly those users with a capital letter in their handle, with
nothing in any log. There is a regression test pinning this in
`010_identity.test.sql`.

The ASCII-only handle format constraint is load-bearing here: it is what makes
`lower(text)` and citext's own case folding provably agree, so the index and
every lookup mean the same thing by "equal".

**Rejected.** Adding `extensions` to each function's search_path (works, but
weakens the convention that gives M0's search_path discipline its value, and a
single omission reintroduces the bug silently). Dropping citext for `text` plus a
functional unique index on `lower(handle)` (also correct and arguably plainer,
but discards an extension M0 installed for this purpose and gives up
case-preserving display).

**Revisit if.** Handles ever admit non-ASCII characters. Then `lower()` and
citext's folding can diverge, the index and the lookups stop agreeing, and the
right fix is a generated normalized column rather than either of the above.

### D15. One friendship row per pair, canonically ordered

**What.** `friendships` stores `user_a < user_b` with the pair as its primary
key. Direction is carried by `requested_by`, not by row identity.

**Why.** Friendship is symmetric, so two mirrored directed rows would make
"A is friends with B but B is not friends with A" a representable state and leave
consistency to application code. Under canonical ordering the primary key makes
the duplicate physically impossible: two people who request each other at the
same moment collide on the key instead of producing two friendships, in either
arrival order. That is the hard-invariant-in-SQL split from D6 applied to the
social graph. Direction still matters for who is allowed to accept, which is a
column.

**Rejected.** Two directed rows (the common ORM shape, simpler reads, but the
invariant becomes a job for code that can have bugs). A separate
`friend_requests` table promoted into `friendships` on accept (clean lifecycle,
but two tables, two RLS surfaces, and a window where a pair exists in both).

**Revisit if.** Friendship acquires genuinely per-direction state — a mute, or a
"close friend" marker one side sets. That belongs in its own directed table
rather than in a reshaping of this one.

### D16. Declining a request deletes the row

**What.** No `declined` status. Cancelling, declining, and unfriending are all
one DELETE, allowed to either party.

**Why.** A retained `declined` row is a durable record of a social rejection, and
the only feature it buys is suppressing re-requests — which is what blocking
does, explicitly and with the user's knowledge. Deleting also keeps the state
machine at two states, so every policy has two cases to reason about instead of
three.

**Rejected.** A `declined` status with a cooldown (throttles pestering without
requiring a block, but stores the rejection indefinitely and adds a state to
every policy that touches friendships).

**Revisit if.** Repeat-request pestering turns up among people unwilling to block
a friend outright. A rate limit on requests per pair is the smaller fix and does
not need a stored status.

### D17. Groups have flat membership

**What.** No owner, no admin, no roles. Any member may rename the group and
rotate its join code. Nobody can remove anyone else. `created_by` is
informational and nulls out on account deletion. The group is deleted when its
last member leaves.

**Why.** Chosen by the owner over a roles-based model. What it commits us to is
worth stating, because the rest of the design follows from it rather than being
separate choices: with no role that could authorize removal, "kick" cannot
exist, so leaving is the only exit. That makes last-one-out the only safe
deletion rule — a member-initiated delete would let one person destroy contest
history the others still want, and there is no owner to reserve that power for.
And `created_by` therefore has to confer nothing at all, or it becomes an owner
by another name; it is immutable and privilege-free for that reason.

**Rejected.** Owner/admin roles (necessary at organization scale; costs a role
column, a transfer-on-leave flow, and a policy surface that must answer "what if
the owner leaves mid-contest"). Member-initiated group deletion (simpler than
reaping, but unilaterally destroys shared history).

**Revisit if.** Groups outgrow friend-group scale, or moderation becomes a real
need. Adding roles later is additive — nothing today depends on their absence
except the deletion rule, which would become "an admin may delete".

### D18. Join codes are generated capabilities, never client-chosen

**What.** `groups.join_code` is eight characters drawn from a 32-symbol alphabet
via `gen_random_bytes`. Clients hold `UPDATE (name)` — a column-level grant — and
rotate the code through `public.rotate_group_join_code()`.

**Why.** The code is the only credential for joining a group, which makes it a
bearer capability and its unguessability a security property rather than a
nicety. A member free to write the column could set `AAAAAAAA`, and a format
CHECK cannot distinguish a weak well-formed code from a strong one — so the
control has to be that clients cannot write the column at all. Hence the
column-level grant, which is also why the constraint on the column is described
as a backstop rather than the mechanism.

Three smaller choices inside it: `gen_random_bytes` rather than `random()`, which
is seeded and predictable; an alphabet of exactly 32 symbols so that 256 divides
evenly by it and the modulo introduces no bias toward early characters; and
0/1/O/I excluded so a code survives being read aloud or copied off a screen.
Rotation exists because a join link outlives the group chat it was pasted into.

**Rejected.** Client-chosen vanity codes (nicer to share, and a guessable-code
hole in the one credential that matters). A format CHECK alone (catches
malformed, cannot catch weak). Signed invite links with no stored code (no
rotation story, and revocation needs server-side state anyway).

**Revisit if.** Groups need to be publicly discoverable. That is a different
mechanism, not a longer code.

### D19. Blocks are directed, one-sided in visibility, and reach everywhere

**What.** `blocks` is a directed pair. Every policy on it is blocker-only,
including SELECT. Inserting one severs any friendship between the pair, hides
both profiles from each other, removes both from handle discovery, and refuses a
group join in either direction.

**Why.** The reach is the whole point. A block that can be routed around by
joining a group the other person is in is not a block, so the check sits in
`join_group_by_code()` as well as in the policies.

One-sided visibility is a separate decision and matters as much. If the blocked
party can read the row, the block becomes a message — and for a product where
these two people are friends who may owe each other a donation, delivering that
message is a worse outcome than not blocking at all.

Severing the friendship on insert, rather than leaving it and filtering it out of
reads, is what keeps `app.is_friend()` a single honest predicate that M2 through
M7 can rely on without each remembering to also check for a block.

**Rejected.** Symmetric blocks (fewer rows, but conflates "I want no contact"
with "they want none"). Retaining the friendship and filtering it (recoverable on
unblock, but every future consumer of friendship has to remember the filter, and
the first one that forgets silently reopens contact).

**Revisit if.** Users want unblock to restore the old friendship. It cannot — the
edge is gone and they must re-request. Retaining a severed edge is the change,
and it costs the single-predicate property above.

### D20. Nothing auto-creates a profile

**What.** No trigger on `auth.users`. The client inserts its own profile row with
a chosen handle. An auth user with no profile row is mid-onboarding, which is a
legitimate state.

**Why.** A handle is user-chosen and unique, so a trigger would have to invent a
placeholder — and placeholder handles leak into contests, standings, and
settlement records, where they are indistinguishable from real ones. Letting
"a profile exists" mean "onboarding finished" also gives the client one
unambiguous check instead of an `is_onboarded` flag that can disagree with the
data. `join_group_by_code()` enforces the precondition explicitly rather than
failing later on a foreign key.

**Rejected.** A trigger minting `user_8f3a`-style handles (one less client round
trip; permanent junk identities for everyone who abandons signup, with no way to
tell them from real accounts).

**Revisit if.** Nothing foreseeable.

### D21. Withheld verbs are revoked, not merely unpoliced

**What.** Each table revokes ALL from `anon` and `authenticated`, then grants
back only the verbs that have a matching policy. Five verbs are withheld
outright, listed in the migration.

**Why.** Supabase ships default privileges that grant `anon` and `authenticated`
ALL on new tables in `public`. Without an explicit revoke, `anon` holds DELETE on
every table in this migration and is stopped only by the absence of a policy —
so one permissive policy added later for an unrelated reason turns into a live
delete path. Revoking makes the intent enforced twice and puts it somewhere
visible: `\dp` shows a grant, whereas a missing policy looks identical to an
oversight.

The pattern earned itself immediately. `groups.created_by` is refused by the
column-level grant before its immutability trigger is consulted at all, which
means two independent mechanisms have to fail before authorship can be
rewritten — and the test suite asserts both, with the different SQLSTATEs each
produces.

**Rejected.** Relying on policy absence alone, which is what the default
Supabase workflow encourages (one less line per table; makes every future policy
a potential privilege escalation).

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
- **Handle change throttling (M8).** Handles are freely editable today. Swapping
  to a friend's handle shortly before settlement is a plausible impersonation
  play. Proposed: one change per 30 days, enforced by a `handle_changed_at`
  column, plus showing the change to anyone in an active contest with them.
- **Contest co-participants can see each other's profiles (M2).** The
  `profiles` read policy currently covers friends and group co-members only.
  M2 adds contest co-participation as a third route, which is the point at
  which it is needed — a duel between two people who are not friends has to
  render an opponent.
- **Group size cap (M2).** Uncapped today. A winner-takes-all group of *n*
  produces *n-1* settlements (D4), so group size directly bounds how many
  donation obligations one contest can create. Proposed: cap at contest
  creation rather than on the group, since the group is not the thing being
  staked.
- **A block does not eject either party from a shared group (M2).** Blocking
  hides the profiles and prevents new joins, but two people already in a group
  stay in it. Ejecting on block would let anyone remove anyone from a group by
  blocking them, which is exactly the power flat membership withholds (D17).
  Revisit alongside contest invitations, where the same tension reappears.
- **Avatar storage bucket and its policies (M8).** `profiles.avatar_path` holds
  an object path, but no bucket exists yet and nothing writes it. The bucket
  and its RLS arrive with the client that uploads to it.
