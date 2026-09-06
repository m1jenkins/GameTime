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

> **Verified 2026-07-25:** Xcode 26.2 exposes the iOS 26.2 SDK, and Swift 6.2.3
> builds and tests the portable package. The iOS 18 target remains the
> deliberate compatibility choice above. Changing suite counts and later
> verification results live in `docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md`, not this
> decision record.

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

**Amended by D75.** A declared `both_donate` tie has no winner. Its
self-directed obligations are the one explicit exception to the
winner/loser tuple below.

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

**Implementation history (2026-07-26).** M6.5 first added a separate
conformance-only SwiftUI/DeviceCheck target that depends on GameTimeCore. M8.1
then added the product target and macOS CI while restoring the conformance
target to harness-only behavior; D83 records that final boundary.

**Why.** It makes client domain logic genuinely CI-tested rather than tested only
when someone opens Xcode. It also forces device dependencies behind protocols,
which is what makes bucketing and dwell logic testable without a device at all.

**Revisit if.** Nothing foreseeable. This one is close to free.

### D11. App Attest has a development bypass, guarded against deployment

**What.** `ATTEST_DEV_BYPASS=true` lets ingest accept a stub assertion.
`assertAttestConfigIsSafe()` throws at module load if the bypass is on while
`GAMETIME_ENV` is `staging` or `production`, taking the function down at boot.
Hosted functions refuse both a missing value and an explicit `local` or `test`
value, so a deployed function cannot opt itself back into either bypass-capable
environment.

**Why.** The backend has to be testable without a physical Apple device, and App
Attest fundamentally cannot be satisfied off-device. The bypass is therefore
necessary and is also a total defeat of anti-cheat rule 9 — so it is guarded at
the only moment that matters, and the failure mode is a function that refuses to
start rather than one that quietly accepts unattested data. Boolean parsing is
strict (`"1"` and `"yes"` are rejected, not coerced) so a typo in a security flag
fails loudly instead of landing on a default.

**Revisit if.** We get a device-backed integration environment; the bypass can
then be restricted to `local` alone. `GAMETIME_ENV` deliberately does not use
the reserved `SUPABASE_` prefix, which hosted projects do not allow for custom
secrets.

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

**Amended by D81.** Authentication deletion now retains a pseudonymous durable
actor, so `created_by` continues to reference that tombstone instead of nulling
solely because the login was removed. It remains informational and privilege-free.

**What.** No owner, no admin, no roles. Any member may rename the group and
rotate its join code. Nobody can remove anyone else. `created_by` is
informational and, before D81's durable actor, nulled out on account deletion.
The group is deleted when its last member leaves.

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

## M2 — Contests, invitations, participant state machine

### D22. A duel is not a kind of contest; it is `max_participants = 2`

**What.** No `kind` column. `contests.max_participants` (2–20) is the only thing
that distinguishes a duel from a group contest, and `group_id` is an independent,
optional scope.

**Why.** D4 already settled that a duel is the N=2 case of the same structure —
same scoring, same settlement shape, same lifecycle. A `kind` enum would be a
second source of truth for a fact `max_participants` already carries, and the
first bug it produces is a row where the two disagree.

Decoupling `group_id` from roster size falls out of the same thinking. A
three-person contest among friends who share no group is a perfectly good
contest, and a duel between two members of one is too, so tying "is this a group
contest" to "does it name a group" would forbid both for no reason. The group is
a reach mechanism (D28), not a shape.

**Rejected.** A `kind` enum with a CHECK tying it to `max_participants`
(self-documenting in the client, but it is a derived column maintained by hand).
`(kind = 'group') = (group_id is not null)`, which reads natural and forbids the
two useful cases above.

**Revisit if.** A future contest shape is genuinely not a roster-size variant —
pass/fail against individual targets, say, which D4 already identified as a
different product.

### D23. Invitation and participation are one row, and `declined` is retained

**Amended by D79.** The `declined`/`lapsed` distinction remains useful
responsiveness history, but neither state enters pledge reliability.

**What.** `contest_participants` carries the whole lifecycle: `invited`,
`accepted`, `declined`, `withdrawn`, `lapsed`. There is no separate invitations
table, and no row is ever deleted.

**Why.** An invitation and a participation are the same row at different points
in its life, exactly as a friend request and a friendship are (D15). Two tables
would mean two RLS surfaces, a promotion step, a window in which someone exists
in both, and a roster query — the one every later milestone runs — that has to
union them.

Retaining `declined` is the opposite call from friendships, where declining
deletes the row (D16), and the difference is what the row is *for*. A declined
friend request is a social rejection whose only remaining use is suppressing
re-requests, which blocking already does explicitly. A contest roster is the
record of who was asked to pledge money and what they said, and `declined`
against `lapsed`—an answer against silence—remains useful responsiveness
history even though D79 excludes both from pledge reliability. Deleting would
also make re-invitation silently possible where the primary key currently makes
it idempotent.

**Rejected.** A `contest_invitations` table promoted on accept (clean lifecycle
separation, all the costs above). Deleting on decline for consistency with D16
(consistent in mechanism, wrong in meaning).

**Revisit if.** Nothing foreseeable. Note the asymmetry with D16 is deliberate
and both entries should be read together before changing either.

### D24. The terms are frozen at creation, and clients hold no UPDATE on contests

**What.** Every column describing what was agreed — metric, cadence, target,
stake, tie-break, window, roster ceiling, group, author — is immutable from the
instant the row exists, enforced by `app.forbid_column_change()`. `authenticated`
is granted no UPDATE on `public.contests` at all; status moves only through
`cancel_contest()` and `app.activate_due_contests()`.

**Why.** These columns are what each participant individually agreed to. A
mutable stake means the author can raise it after you accept, and there is no
honest version of that — fixing a typo is worth a cancel and a re-create, which
costs one round trip and leaves the agreement unambiguous. Since status is the
only remaining mutable field and it is not the client's to set, there is no
column left for a client to write, so the grant goes away entirely rather than
being narrowed to a column list.

Two mechanisms rather than one, for the same reason as `groups.created_by` in
D21: the missing grant stops a client, and the trigger stops a privileged writer
that gets past it. The suite asserts the trigger specifically, as superuser,
because that is the layer the missing grant cannot test.

**Rejected.** `UPDATE (title)` so typos are fixable (genuinely useful, and it
reopens a policy surface on a table that otherwise needs none — the cancel path
already covers it). Freezing only once a second participant accepts (matches the
consent intuition, but leaves a window whose correctness depends on roster
state, and the author is a participant from the first instant anyway).

**Revisit if.** Contests acquire mutable state that is not a lifecycle stamp — a
running standings cache, say. That belongs in its own table rather than as a
loosened grant here.

### D25. A contest window cannot open in the past

**What.** `app.assert_contest_window_is_future()`, a BEFORE INSERT trigger,
refuses any contest whose `starts_at` is already behind `now()`.

**Why.** This is anti-cheat, not validation, and it is the cheapest high-value
rule in the milestone. Someone who already knows they walked 20,000 steps
yesterday and can name yesterday as the window has a contest they cannot lose —
and every sample in it is genuine, correctly attested, and provenance-clean, so
nothing in M3 through M6 would ever flag it. Backdating is invisible downstream,
which means creation is the only place it can be stopped.

A CHECK constraint cannot express it: `now()` is not immutable. Hence the
trigger, and hence it is INSERT-only — `starts_at` is frozen afterwards by D24,
so there is nothing to re-check on update.

**Rejected.** Allowing a short grace window for clock skew between client and
server (kinder to a phone with a wrong clock, and any grace period is exactly
the size of the exploit). Validating in the client (defeated by anyone willing
to call PostgREST directly, which is precisely the population this rule is for).

**Revisit if.** Legitimate creation flows start failing on clock skew. The fix
is for the client to send a server-derived timestamp, not to widen the rule.

### D26. Charity data is curated and read-only, and is not shipped as a data migration

**What.** `public.charities` is reference data with an EIN and a donation slug.
`authenticated` holds SELECT and nothing else — no INSERT, UPDATE, or DELETE
policy exists. The local list lives in `seed.sql` and is openly fictional:
invented names, `00-000000N` EINs, and `.test` hosts, which RFC 2606 reserves so
they cannot resolve.

**Why.** A charity row is the destination of a real donation obligation, so "who
may add one" is not a question the Data API should be able to answer at all. The
deferred decision from M0 called for a small curated list rather than an IRS
Pub 78 import, and that still holds: 1.3M rows buy nothing until a user asks for
a charity that is not on the list.

What the deferral did not settle is *where* the list lives, and the answer is
neither of the obvious two. `seed.sql` never runs in production, so a
seed-only list ships an empty table and a broken create-contest flow. A data
migration would fix that — but it would have to contain real EINs, and an EIN
that is plausible and wrong is worse than no list at all, because it routes a
real donation to the wrong organisation and looks correct while doing it. Those
cannot be written from memory with the confidence a financial identifier
deserves. So the schema ships, the fixtures are unmistakably fake, and
populating production is an owner action against verified sources.

> **Action for the owner:** before launch, insert the production charity list
> with EINs verified against IRS Tax Exempt Organization Search. Until then
> `charities` is empty in production and `create_contest()` will fail its
> charity check, which is the correct failure mode — no contest should be
> creatable with no valid destination for its stake.

**Rejected.** A data migration with placeholder rows (populates production, and
ships "Example Trail Conservancy" as a nominable destination). A free-text
charity name on the participant row (no curation problem, and no verifiable
destination either, which is the entire point of the table).

**Revisit if.** The curated list becomes large enough to want an import, or
users need charities outside it. The second is the likelier and wants a request
flow, not a bigger seed.

### D27. Accepting a contest requires naming a charity

**Amended by D75.** A declared `both_donate` result has no winner; each accepted
participant's own nomination is the destination of their self-directed
obligation.

**What.** `contest_participants.charity_id` is required for the `accepted`
status, checked one-directionally so that a participant who later withdraws
keeps the nomination they made. The winner's nomination is the destination for
every settlement the contest produces (D4).

**Why.** Informed consent for a money pledge. What a participant agrees to is
"if I lose, I donate the stake to whatever charity the winner nominated", and
they should be able to read every possible destination before agreeing rather
than after losing. Requiring it upfront also removes a stalling move: a winner
who has not yet chosen cannot hold settlement open.

This is what forces creation to be a function rather than an insert. The author
is enrolled as accepted from the first instant (they wrote the terms, so there is
nothing left for them to agree to), which means their row needs a charity, and a
trigger cannot invent one. `create_contest()` writes both tables or neither.

**Rejected.** The winner choosing at settlement (more natural as a moment, and
it means you pledge without knowing the destination). A nullable nomination with
a default charity (removes the friction and quietly picks where someone else's
money goes).

**Resolved by D74 and D75.** The result-created obligation snapshots the frozen
nomination; a later profile or charity-list change cannot repoint it. Revisit
only if the product adds an explicitly consented substitution before donation.

### D28. Invitation reach is the existing social graph, and only the author invites

**What.** An invitation may be sent only by the contest's author, only while it
is pending, and only to a friend or a co-member of the group the contest is
scoped to — never across a block in either direction. Enforced by
`app.may_invite_to_contest()` in the insert policy.

**Why.** Two separate decisions that reinforce each other.

*Reach.* M1 made `profiles` non-enumerable and discovery exact-match precisely
so that knowing a handle is not a route to a stranger. An invitation sendable to
any handle would hand that straight back, and it would do it on the one path in
the product that carries a money pledge — which is a scam and harassment vector
aimed at people who never opted into contact. So invitations reach exactly as
far as the graph already does, and adding someone new means friending them
first, which is a step they consent to.

*Author.* Unlike a group, where flat membership means every member administers
(D17), growing a contest is the author's alone. The divergence is deliberate and
it is why `contests.created_by` confers privilege where `groups.created_by`
pointedly does not: a group is a container with no terms, whereas a contest is an
agreement someone wrote, and adding a participant changes the odds for everyone
who already accepted.

That last point is also what makes it fair for the author to keep inviting after
others have accepted, and it is the real justification for the roster ceiling
that the M0 deferral only half-had. An invitee is shown `max_participants` before
they agree, and exposure is capped at the stake regardless of roster size (D4),
so a later invitation cannot change what they consented to. The ceiling is the
disclosure that makes post-acceptance invitation honest — not merely a bound on
settlement count.

Invitations themselves are uncapped; only acceptances count against the ceiling.
Capping invitations would let one decline shrink a contest permanently, since
nothing reclaims the slot, and "invite five, first two in get the duel" is both
more robust and what a group chat actually produces.

**Rejected.** Invitation by handle (the flow a user might expect, and it reopens
what M1 closed). Any participant may invite (consistent with D17, and it lets
someone else reshape an agreement you authored). Auto-enrolling every member of
the scoped group (one tap for the author, and it commits people to a financial
pledge they never accepted, which flat membership exists to prevent).

**Revisit if.** Contests want to reach beyond the friend graph — a public
league, which the brief already places out of scope and which is a different
mechanism rather than a wider policy.

### D29. The roster freezes when the window opens, so blocking is not an exit

**Amended by D78.** A documented personal exception may release that
participant's later obligation; only a defect affecting the shared result can
make the whole contest inconclusive. Neither is a participant-written exit.

**What.** Once a contest leaves `pending`, nothing on its roster is writable —
not a status, not a charity, nothing — and no participant can be added.
Before the window opens, an accepted participant may still withdraw; the author
never can, and cancels the contest instead.

**Why.** The freeze is what makes a stake binding, and the case that shows why it
has to be total is blocking. Blocks reach everywhere else in this schema (D19),
so the natural instinct is to have them reach here too. They must not: if
blocking your opponent ejected you from a contest, or even just hid them, then
"block the person beating you" would be the cheapest way to walk away from a
losing pledge. So a block during a live contest severs the friendship, hides
nothing about the contest, and leaves the obligation exactly where it was.

That resolves the tension the M1 deferral flagged, and it resolves it harder than
the group case did. In a group, not ejecting on block was about denying anyone
the power to remove another member (D17). Here it is about money: an exit that
one party can take unilaterally is not an agreement.

Pre-window withdrawal is allowed because nothing is at stake yet, and forcing
someone into a contest they regret before it has started would be worse than
letting them go. The author is excluded because they authored the terms and are
enrolled from the first instant — the way out of a contest you wrote is to cancel
it, which is a decision about the whole contest rather than a quiet exit from it.

**Rejected.** Ejecting a blocked participant (consistent with D19's reach,
hands every losing participant an exit). Hiding the counterparty's profile but
keeping the obligation (looks like a compromise; produces a settlement screen
that cannot name who owes whom). Allowing withdrawal from an active contest with
an integrity penalty (turns a hard invariant into a price, and D6 puts prices in
TypeScript and invariants in SQL).

**Historical note, superseded by D78.** A genuine medical or bereavement
exception is adjudicated as an individual release unless it invalidates the
shared result. It is never a status the participant writes themselves.

### D30. Quorum is two, and a contest that misses it cancels before opening

**Amended by D79.** The distinct cancellation reason remains history and an
operational signal, but a contest that never produced an obligation does not
enter pledge reliability.

**What.** `app.activate_due_contests()` opens every pending contest whose
`starts_at` has passed, provided at least two participants accepted. One or
fewer and it becomes `cancelled` with reason `insufficient_participants`.
Outstanding invitations lapse either way.

**Why.** A contest is a comparison and there is nothing to compare one person
against, so a lone author running a contest against themselves is not a degraded
outcome to be tolerated — it is a state with no meaning that would still produce
standings, a winner, and no settlement. System cancellation says so explicitly,
and the distinct reason keeps it from looking like the author called it off.
That distinction remains useful history and an operational signal even though
D79 correctly excludes a contest with no obligation from pledge reliability.

Lapsing outstanding invitations at the same moment is what keeps "my open
invitations" a query on status alone rather than one that has to join contest
status to find out whether an invitation is still real. `cancel_contest()` does
the same for the same reason.

The activation clock is a parameter defaulting to `now()`, so the suite can drive
it while cron calls it with no arguments — a scheduled job that cannot be tested
without waiting for wall-clock time is a job that does not get tested.

**Rejected.** Activating regardless and letting the scoring engine handle N=1
(fewer states here, pushes a meaningless case into the most correctness-sensitive
code in the product). Requiring quorum at creation (cannot be known then; the
author is the only participant at that moment).

**Revisit if.** A solo goal-tracking mode becomes a product. That is a different
table, not a quorum of one.

### D31. `lapsed` is the system's word, and enforcing that needs invoker rights

**What.** `invited → lapsed` is a legal transition, but only the table owner may
write it — meaning only `cancel_contest()` and `app.activate_due_contests()`,
which are SECURITY DEFINER. A client attempting it is refused. This is enforced
by `app.forbid_client_lapse()`, a separate trigger that is deliberately *not*
SECURITY DEFINER.

**Why.** `declined` is an answer and `lapsed` is silence. If a client could write
`lapsed`, an invitee could file their own refusal as silence and the distinction
would stop meaning anything M7 can read.

The mechanism is the interesting part, and it is a trap worth recording. The
obvious implementation — check `current_user` inside the existing transition
trigger — silently does nothing, because that trigger is SECURITY DEFINER and
inside a definer function `current_user` is the function's *owner*, not the role
that called it. The check therefore compares the owner against the owner and
passes for everybody, including `authenticated`. It was written that way first
and the test caught it.

Under invoker rights `current_user` is whatever was in effect at the call site:
the owner when a definer function is doing the writing, `authenticated` when
PostgREST is. So the check has to live in its own invoker-rights trigger, and the
owner is read from `pg_class` rather than hardcoded because it is `postgres` on
Supabase and whichever role ran the migrations anywhere else.

**Rejected.** Dropping `lapsed` and reusing `declined` (one less state, loses the
signal). A session GUC set by the definer functions to mark system writes (works,
and adds a mechanism whose failure mode is silent where this one's is a refusal).
Hardcoding `current_user <> 'authenticated'` (correct on Supabase, wrong on any
rig with different role names, and `postgres` is itself granted `authenticated`
there).

**Revisit if.** More statuses become system-only. The trigger generalises to a
column-and-value list the way `app.forbid_column_change()` does.

### D32. A definer function in `app` that no policy calls must have PUBLIC EXECUTE revoked

**Amended by D82.** The installed `pg_cron` job runs as the migration owner, not
as `service_role`. The `service_role` grant remains a narrowly scoped recovery
and test path; among application roles it is still the only caller.

**What.** `app.activate_due_contests()` revokes EXECUTE from `public`, `anon`,
and `authenticated`, and grants it to `service_role` alone. M1's predicates in
`app` do not, and must not.

**Why.** Two defaults combine into a live privilege-escalation path. Postgres
grants EXECUTE on every new function to `PUBLIC`, and the baseline migration
grants `authenticated` USAGE on the `app` schema so that RLS policies can call
the predicates living there. Together they mean a SECURITY DEFINER function in
`app` is callable by any signed-in user unless it is explicitly revoked — and
this one opens contest windows and cancels contests for want of a quorum. Left
as created, a client could activate a contest early or cancel one out from under its
participants.

The distinction that decides which functions need this is "called by a policy"
versus "called by nobody but cron". A policy expression is evaluated with the
privileges of the querying role, so revoking EXECUTE from `authenticated` on
`app.is_friend()` and its siblings would break the very policies they exist to
serve. Those grants are load-bearing, not oversights. Anything in `app` that no
policy calls should be revoked, and the test suite asserts both halves.

**Rejected.** Moving the function to a third schema with no `authenticated`
USAGE (works, and splits the private-helper convention across two places for one
function). Making it SECURITY INVOKER and relying on table grants (it must
update contests, which no client may do, so it has to be definer).

**Revisit if.** More cron entry points appear. The revoke should become a
reviewed default for anything in `app` that a policy does not call, rather than
something remembered per function.

### D33. Contest co-participation is the third route to profile visibility, and it survives a block

**What.** `profiles` is readable by yourself, by a friend or group co-member
(subject to blocks, as in M1), and now by someone who accepted the same contest
once that contest has actually opened. The third route sits *outside* the block
check; the first two remain inside it.

**Why.** This is the M1 deferral, and implementing it surfaced a distinction the
deferral had not: which contests count.

Being outside the block check is necessary. Two people in a live contest may end
up owing each other's charity money, and a settlement screen that cannot render
the counterparty is not acceptable — nor should blocking someone erase your view
of an obligation you still hold to them (D29).

Restricting it to *accepted* participants of an *opened* contest is what keeps
that from becoming a way around a block. If a merely invited person counted, then
inviting someone and waiting for them to block you would buy permanent visibility
of a profile they had just withdrawn from you — precisely the circumvention
blocks exist to prevent. Nothing is lost by leaving the pending case to the other
two routes, because an invitation can only be sent across a route that already
grants visibility (D28); what the third route actually fixes is the pair who
unfriend mid-contest, which the deferral's "a duel between two people who are not
friends" was really pointing at.

**Rejected.** Any shared contest in any state (renders every case, reopens the
block hole above). Inside the block check like the other two (safe, and blanks
out the counterparty on a live settlement). A separate narrower policy for
settlement screens only (the visibility question is the same one; two policies
would drift).

**Revisit if.** Group contests want to be visible to the whole group. That is a
narrowed view over `contests`, not a widening of this policy — a group contest's
stake and roster are an arrangement between the people in it, and publishing who
pledged what to whom to everyone else in the group is a different product
decision.

### D34. A frozen reference may be cleared but not repointed — and M1's could not be cleared

**Amended by D81.** The clear-but-never-repoint mechanism remains correct when a
referenced row is actually deleted. M7 account deletion instead retains the
pseudonymous actor row, so actor references survive auth deletion as tombstones
and no referential `SET NULL` occurs for them.

**What.** `app.forbid_column_reassignment()` joins
`app.forbid_column_change()`: it refuses every change to the named columns
*except* one to NULL. It is used for the four frozen columns that are references
carrying `on delete set null` — `contests.created_by`, `contests.group_id`,
`contest_participants.invited_by`, and, retroactively, `groups.created_by`.
M1's `groups_freeze_columns` trigger was split to use it.

**Why.** A referential action is an UPDATE. When the referenced row is deleted,
Postgres runs `update ... set created_by = null` against the referencing table,
which fires BEFORE UPDATE triggers — so a strict immutability trigger on that
column refuses the referential action and the DELETE fails.

The consequence in M1 was live and silent: **no account that had ever created a
group could be deleted.** D20 states that account deletion goes through
`auth.users` and cascades, and that had not been true since M1 shipped. It went
unnoticed because nothing exercised it — every M1 test that touches `created_by`
asserts it cannot be *repointed*, which is the half that worked. Verified rather
than assumed: deleting such an account raises `column public.groups.created_by is
immutable` from inside the FK's own UPDATE. M2 would have added three more
instances of the same bug.

The fix separates two things the strict trigger had conflated. What the freeze
protects is reassignment — nobody may become the author of someone else's
contest, and a contest cannot be moved into a different group's reach after
people agreed to its terms. Clearing is not reassignment; it is the documented
behaviour when the referenced row goes away, and the contest is meant to outlive
both its author's account and its group because it is financial history. So
repointing still raises, clearing passes, and there are now regression tests on
both halves for groups and contests alike.

One related exclusion, for the same reason: the roster freeze (D29) compares the
whole row, so `invited_by` is excluded from that comparison too, or deleting an
inviter's account would fail against every contest they started that had since
opened. It is not thereby writable — the column grant covers exactly
`(status, timezone, charity_id)`, and repointing still hits this trigger.

**Rejected.** Dropping `created_by` from the freeze and relying on the withheld
column grant alone (fixes deletion, and gives up the second mechanism D21 exists
for — M1's own test asserts the trigger stops a privileged writer). Loosening
`app.forbid_column_change()` itself to tolerate NULL (fewer functions, and it
would silently weaken every other caller's contract; the strict version is
correct for the NOT NULL columns that use it). Changing the FKs to `on delete
restrict` (preserves authorship, and makes account deletion impossible on
purpose rather than by accident).

**Revisit if.** A frozen reference appears that must not be clearable either. It
would need `restrict` on the FK and an explicit decision about what account
deletion then means.

---

## M3 — Evidence ledger, device attestation, attested ingest

### D35. The ledger is append-only, and a revision appends rather than overwrites

**What.** `metric_snapshots` holds one row per *observation*: "at this moment,
this client reported that this participant's `steps` for this hour, from this
source, was 812." There is no unique constraint across
`(contest_id, user_id, metric, bucket_start)`, so a figure that grows as late
samples arrive accumulates rows. Reading it back has two steps: within one
source the revisions are a monotone series so the current figure is the largest,
across sources the contributions are disjoint so they add. `contest_evidence` is
that reduction.

**Why.** HealthKit's figure for an hour genuinely changes — a watch syncs late, a
workout is written after the fact — so the ledger has to represent revision
somehow. Storing one row per bucket and overwriting it would destroy the record
of what was claimed and *when*, and when is exactly what distinguishes a late
sync from a fabrication. A row per observation keeps the reporting lag of each
claim visible, which is what M5's quarantine rule will read.

The monotonicity trigger that refuses a downward revision is deliberately *not*
framed as anti-cheat, because it would be dishonest to: only the participant may
write their own rows, so a downward revision harms nobody but its author. What
it buys is that "the value for this bucket from this source" is single-valued —
the latest observation and the largest are the same number — so the scoring
engine, the standings, and a later audit cannot reach different totals from the
same ledger. It also makes a genuine deletion in the Health app surface as a
dispute for M7 rather than as a quiet rewrite of banked evidence.

**Rejected.** One row per bucket, updated in place (smaller, and it makes the
ledger a cache rather than evidence — and it needs UPDATE on an append-only
table). A separate revisions table (the same data with a join and two RLS
surfaces). Refusing revisions entirely (simplest, and it discards every late
sync, which is most of them).

**Revisit if.** The row count becomes a problem. The fix is retention on
finalized contests, not overwriting live ones.

### D36. A bucket is an hour in the participant's frozen zone, not a UTC hour

**Amended by D62.** “Frozen zone” below is the immutable base epoch. After a
consented relocation, the same alignment rule uses the zone effective for that
bucket, without relabelling earlier evidence.

**What.** `bucket_start` must be aligned to a whole hour in the timezone frozen
on the participant's roster row (D5). Enforced by `app.prepare_metric_snapshot()`
and mirrored in the client's `HourlyBucketer`.

**Why.** Daily cadence asks whether you hit 10,000 steps on *your* Tuesday, so
every bucket has to lie inside one local day. Not every zone is a whole number of
hours from UTC: India is +05:30, Nepal +05:45, Chatham +13:45. A UTC-aligned hour
therefore straddles the local day boundary for something like a fifth of the
world's population, and daily cadence would silently attribute part of Tuesday to
Monday for exactly those participants — a wrong answer with no error, in the
scoring of a money pledge.

A locally-aligned hour lies inside one local day by construction. `Calendar`
`dateInterval(of: .hour,)` and Postgres's `date_trunc('hour', ts at time zone
tz)` both truncate to the local hour rather than to a multiple of 3600 seconds
since the epoch, so both sides get the half-hour and quarter-hour offsets right,
and both get the 23- and 25-hour days at a daylight-saving transition right.

The unfairness this does leave is at the window edges: a participant whose offset
is not a whole number of hours relative to the contest's bounds loses part of the
first and last hour, because a bucket must lie *wholly* inside the window. That
is bounded at one bucket per end and it fails in the conservative direction.

**Rejected.** UTC hourly buckets (one canonical bucketing, wrong for every
non-whole-hour zone). Fifteen-minute UTC buckets, which compose exactly into
every real zone's day (correct, and four times the rows and four times the
cellular payload). Letting the client send the local date it computed (moves the
authority for day attribution to the party with the motive to move it).

**Revisit if.** A zone appears whose offset is not a multiple of 15 minutes, or
one that transitions at a time other than a local hour boundary. Both exist
historically; neither is live.

### D37. The server stamps the local day; the client never supplies it

**Amended by D62.** The server stamps from the timezone epoch effective at
`bucket_start`; the roster zone remains the base epoch rather than the only
epoch.

**What.** `metric_snapshots.local_day` and `local_hour` are written by
`app.prepare_metric_snapshot()` from the participant's frozen zone. The insert
lists them only because they are NOT NULL; whatever a caller passes is
overwritten.

**Why.** Day attribution is what a daily-cadence settlement turns on, so it is
not a field the client gets to fill in. But the interesting half is why it is
*stored* rather than computed on read: the row is append-only and the zone is
immutable, so the two can never come to disagree, and storing it means the day
attribution a settlement rests on is the one the server recorded at the time
rather than whatever a query would compute later. It also makes the decision
auditable — you can see what the server concluded, not just re-derive it.

**Rejected.** A generated column (cannot reference another table, and the zone
lives on `contest_participants`). Computing it in the scoring engine (correct
today, and it means M4 and any dashboard each own a copy of the rule).

### D38. Provenance is part of the ledger's key, and admissibility is generated

**What.** The uniqueness within a batch is
`(batch_id, metric, bucket_start, provenance)`, monotonicity is keyed on
provenance too, and `is_admissible` is a stored generated column computing
`provenance in ('device', 'third_party')`.

**Why.** A real hour routinely holds samples from more than one source: an
iPhone's pedometer, a watch, a running app, and sometimes a figure typed into the
Health app years ago. One row per bucket would mean choosing one provenance for
the whole hour, and the only safe choice is the least trusted one present — so a
single stray hand-typed step would discard five thousand genuine ones and lose
somebody a day they actually walked. Splitting keeps each source separately
admissible.

Generating `is_admissible` rather than storing it means no code path can produce
a row whose flag disagrees with the provenance it derives from. The line it
draws is D6's: `manual` and `unknown` have no tuning parameter, so they are
invariants; whether a *particular* third-party app is trustworthy is a heuristic
and belongs to M5.

**Rejected.** One row per bucket with the least-trusted provenance (simpler, and
it is the fairness bug above). Bundle identifier in the key (finer, and it makes
the key unbounded in something the client controls). A plain boolean column
(one code path away from disagreeing with itself).

### D39. The client reports everything it sees; the server decides what counts

**What.** An inadmissible observation is *stored*, not refused. The client sends
`manual` and `unknown` rows, `record_metric_batch()` accepts them, and
`contest_evidence` leaves them out.

**Why.** A client that filters its own evidence is a client whose silence has to
be trusted. If hand-typed samples were refused at ingest, a cheating client would
simply not send them and we would learn nothing; accepting them means an honest
client's data records the attempt, and 20,000 hand-typed steps become a fact
about that participant that M5 can weigh and a dispute can cite.

The same reasoning runs through the whole milestone: the client's provenance
classification is a *report*, not an authorisation. Nothing downstream treats it
as proof. What makes it worth reading at all is App Attest — an assertion
establishes that the binary doing the classifying is the one that shipped.

**Rejected.** Refusing inadmissible rows at the API boundary (a smaller ledger,
and it hands the decision about what is evidence to the party with the motive).
Refusing them in the client (same, one layer earlier).

### D40. There is no client write path into the ledger at all

**What.** `authenticated` holds SELECT on `metric_snapshots`,
`ingest_batches` and `device_attestations` and nothing else. Rows appear only
through `public.record_metric_batch()` and `public.register_device_key()`, which
have EXECUTE revoked from `public`, `anon` and `authenticated` and granted to
`service_role` alone.

**Why.** What authorises a write here is an ECDSA signature over the request
body, and RLS cannot check a signature — so there is no policy that could express
the rule, and any client write path would be one that skipped it. That makes the
missing grant load-bearing rather than tidy, which is the third instance of D32's
trap: Postgres grants EXECUTE on every new function to `PUBLIC`, so a definer
function that writes the evidence ledger is callable by every signed-in user
until it is explicitly revoked. Left as created, any client could write any other
user's evidence, unattested, by passing their uuid. D32 said the revoke should
become a reviewed default rather than something remembered per function; this
milestone treats it as one.

`record_metric_batch()` lives in `public` rather than `app` for a specific
reason: PostgREST can only reach exposed schemas, and the Edge Function calls it
over the Data API. So it is a public function only `service_role` may execute.

### D41. Signatures are checked in TypeScript; the counter is enforced in SQL

**What.** `verifyAssertion()` checks the ECDSA signature, the rpId hash and the
authenticator-data shape. It does *not* compare the assertion counter against the
stored one. `record_metric_batch()` does that, under a row lock, in the same
transaction as the insert.

**Why.** D6's line, and this is the cleanest example of it in the codebase so
far. The signature check needs crypto and has no invariant to state. The counter
check is a monotonic counter — a hard invariant — and it has to be *atomic with
consuming it*: in application code it is a read followed by a write, so two
concurrent copies of a captured request would both read the old value and both
pass. Splitting them puts each half where it can actually be correct.

`device_attestations` carries the same rule twice, deliberately (D21): the
trigger refuses a decrease from any writer, and `record_metric_batch()` requires
strictly greater. The trigger tolerates equality because it also fires on updates
that touch other columns; "no movement" is only a replay in the context of
consuming an assertion.

**Rejected.** Comparing the counter in the Edge Function (natural, and it is the
race above). Enforcing it only in the trigger (cannot distinguish "equal" from
"advanced" without knowing why the row is being written).

### D42. Idempotency is checked before the assertion counter is consumed

**What.** `record_metric_batch()` looks up `(user_id, client_batch_id)` first. If
the batch exists it returns the original result with `replayed = true`, without
touching the counter. Only a genuinely new batch consumes one. A repeated batch
id with a *different* payload digest is an error rather than a silent
deduplication.

**Why.** A phone that times out mid-request retries, and the retry carries the
assertion whose counter the first attempt already spent. Checking the counter
first would turn every timed-out retry into a permanent failure: the client can
never make progress and the day's evidence is lost through no fault of its own.
The ordinary idempotency-key contract solves it, and this domain wants it for the
ordinary reason.

Refusing a reused id with different contents is the other half. Returning the
first result would drop the second batch's evidence without telling anyone, which
is the worst available outcome — silent data loss in a ledger.

**Rejected.** Counter first (correct in the abstract, unusable on a real
network). Returning the first result for any reuse (hides the loss).

### D43. Evidence must lie inside the window, and in an hour that has finished

**What.** Two checks in `app.prepare_metric_snapshot()`. The bucket must be
wholly inside `[starts_at, ends_at]`, and `bucket_start + 1 hour` must not be in
the future. Plus: the contest must be `active`, and `now()` must be before
`ends_at + app.ingest_grace_period()`.

**Why.** The window rule is the other half of D25. That rule stops a contest
naming a window already in the past; this one stops evidence being tendered for
hours outside the window it named. Either alone leaves the exploit open from the
other end and neither is expensive.

The finished-hour rule closes something the window rule cannot. Every hour from
now until a contest ends is *inside* the agreed window, so without a separate
check a client could bank a complete winning scoreline for the rest of an open
contest, in advance, from figures it made up. No tolerance for clock skew, for
D25's reason: a grace period here is exactly the amount of the future it lets you
report, and a client that is a second early retries a second later.

The grace period after `ends_at` is the one genuinely tunable number this
migration puts in SQL, and it is there because it gates whether a row may exist
at all. Six hours: long enough that a phone which spent the night asleep does not
cost its owner the last day of a contest, short enough that the window in which
somebody already knows they lost — and can still write into the hours they lost
it in — stays small. It is a named function rather than a literal because M7's
finaliser must not run before it elapses, and two copies of that number would
eventually differ.

**Revisit if.** Legitimate syncs start failing on the grace period. M5's
quarantine is the better lever than widening it.

### D44. Append-only stops at UPDATE, because a DELETE trigger would make accounts undeletable

**Amended by D81.** Once M7 removes the account cascade, ordinary deletion can
be forbidden without blocking account removal. D81's guarded, policy-versioned
retention worker is the sole deliberate raw-row deletion path, so a blanket
DELETE prohibition is still too broad.

**What.** `metric_snapshots` and `ingest_batches` carry
`app.forbid_mutation()` on UPDATE. Neither carries it on DELETE. DELETE is
withheld from clients by the missing grant and the absent policy only.

**Why.** This is the D34 family again, and it would have been the third
instance. A referential action is a real statement: `metric_snapshots` cascades
from `ingest_batches`, which cascades from `contest_participants`, which cascades
from `profiles`, which cascades from `auth.users`. So deleting an account issues a
genuine DELETE against the ledger, and a blanket BEFORE DELETE prohibition
refuses it and takes the account deletion down with it — meaning no account that
had ever recorded a step could be deleted, which is precisely the bug that had
been live since M1 shipped.

Verified rather than assumed, in both directions: `100_metric_snapshots.test.sql`
deletes an account with banked evidence and asserts it succeeds, and adding a
DELETE trigger to that table makes the same deletion fail with "DELETE is not
permitted". The passing assertion is the regression guard for anyone who later
decides append-only demands the trigger.

This is the honest state of it rather than a comfortable one. Evidence for a
settled obligation should outlive the account and today it does not. D81 resolves
the product choice in favor of pseudonymization; once its M7 migration replaces
the cascade path, ordinary DELETE can be refused without blocking account
removal, while D81's explicit retention path remains possible.

**Rejected.** `on delete restrict` along the chain (preserves the evidence, makes
account deletion impossible on purpose rather than by accident). A trigger that
tries to detect a referential action from `current_user` (D31 is what happens
when a security trigger depends on that subtlety).

### D45. `contest_evidence` is declared `security_invoker`

**What.** `create view public.contest_evidence with (security_invoker = true)`.

**Why.** A view runs with its *owner's* privileges by default, and the owner here
owns `metric_snapshots` and is therefore exempt from its policies. Without this
one option the view would hand every authenticated user the entire ledger — every
participant's hourly movements, which is a detailed picture of when people sleep,
work and travel — with RLS enabled and doing nothing. It is a single word whose
absence is a silent, total read hole, so it is asserted in the suite as a
privilege test rather than trusted to review.

Worth stating as a repo-wide rule since this is the first view: any view over an
RLS-protected table declares `security_invoker`, or it is a hole.

### D46. Apple's App Attest root is configuration, not a constant

**What.** `verifyAttestation()` takes the root certificate as a parameter;
`appAttestRootCertificate()` reads `APP_ATTEST_ROOT_CA_PEM` and throws if it is
absent or unparseable. The staging setup fetches Apple's direct App Attestation
Root CA PEM and refuses to upload it unless its SHA-256 fingerprint is
`1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32`.
The functions therefore refuse to start without a parseable, pinned root.

**Why.** The pinned root is the anchor the whole certificate chain hangs from.
Get its bytes wrong in the harmless direction and every attestation fails; get
them wrong in the other and the server accepts a chain Apple never issued. Those
bytes are published by Apple and are not something to reproduce from memory —
which is the same judgement D26 made about charity EINs, for the same reason: a
plausible-but-wrong value for a security anchor is worse than an absent one,
because absent fails loudly.

Refusing to boot is the correct failure mode, matching D11: a deployment that
cannot verify attestations must not accept snapshots.

The suite now consumes Apple's public 2026 validation vector. It pins the real
root and chain, strict nonce-extension DER, EC2/ES256/P-256 COSE key, little-
endian validation category, bundle version, and 65-byte uncompressed public-key
representation. It also binds the COSE key to the leaf certificate key and the
key id to `SHA256(public_key)`.

The COSE/extensions suffix is new in iOS 27. An iOS 18–26 attestation validly
ends after `credentialId`; that legacy shape remains accepted and still binds
the leaf-certificate public key to the key id. If any suffix byte is present,
the complete deterministic COSE key and both extensions are mandatory and
strictly checked. A deployment that configures an allowed category or bundle
version fails closed when a legacy attestation cannot supply that signal.

Apple's vector is internally inconsistent: its certificate nonce uses the raw
example challenge despite prose that requires the challenge hash, and its
printed public-key digest does not match the supplied certificate. The test
records those contradictions component by component; production verification
does not weaken its challenge or key binding to make the example pass.

> **Remaining M6.5 device gate:** capture one current-device attestation and
> assertion against staging. Record the category/build signals when the device
> OS supplies them, or their explicit absence on iOS 18–26. Apple has not
> published a current assertion vector, so assertions remain the observed
> strict 37-byte authenticator-data form until a real or published fixture
> proves an extension shape. The device run must also confirm the receipt bytes
> and shared monotonic counter in storage.

### D47. The attestation challenge is derived, not stored

**What.** `POST /attest-device/challenge` returns
`HMAC(GAMETIME_ATTEST_CHALLENGE_SECRET,
"gametime.appattest.v1:<userId>:<10-minute window>")`. Registration accepts the
current window or the one before it. No table of nonces.

**Why.** A challenge exists so a captured attestation cannot be replayed. A
derived one is verifiable without state, unguessable without the secret, and
bound to the one account that may present it. What a stored nonce would add over
that is single use — and here that is already covered from the other side:
`key_id` is a primary key, so a replayed attestation is a re-registration of a
key that already exists, and `register_device_key()` refuses that for anyone but
the key's original owner. The replay a nonce table prevents is a replay that
cannot achieve anything.

The trade is a ten-minute window in which one challenge is valid more than once
for one account. All that permits is that account re-registering its own key,
which is already idempotent.

The HMAC key is deliberately independent from access-token verification.
Hosted Supabase may verify user sessions with public asymmetric JWKS, which
cannot supply a secret HMAC key, and rotating an auth signing key should not
silently rotate or expose the challenge construction.

**Rejected.** A `attestation_challenges` table (textbook, and it is a table, a
cleanup job, and an RLS surface for a property already held elsewhere). A
challenge derived from the account id alone (no expiry at all).

**Revisit if.** Registration acquires a side effect that re-running is not
harmless. The nonce table becomes worth its cost the moment that is true.

### D48. The ingest credentials travel as headers, because the assertion signs the body

**What.** `x-gametime-key-id` and `x-gametime-assertion`. The body is exactly the
bytes the assertion covers, read once and hashed before anything parses them.

**Why.** An assertion cannot be a field of the document it signs — adding the
signature changes the document. The alternatives are a canonical subset of the
body (something for two implementations to disagree about) or an envelope
carrying the payload as an escaped string (works, and double-encodes every
request). Headers make the body the document, with nothing to agree on.

Hashing before parsing matters for the same reason. JSON has many encodings of
one value — key order, whitespace, number formatting — so hashing a parsed and
re-serialised body would hash a different document than the client signed, and
every assertion would fail for reasons that look like a crypto bug.

The digest is then stored on the batch, which is what keeps "this evidence was
attested" checkable after the fact rather than a claim about a payload nobody
kept.

### D49. CBOR is written here and strict; X.509 is a dependency

**What.** `_shared/cbor.ts` is a small codec supporting text-keyed maps, arrays,
byte strings and small unsigned integers, and refusing everything else —
indefinite lengths, tags, floats, non-minimal encodings, non-text map keys,
duplicate keys, trailing bytes. Certificate chain verification uses
`npm:@peculiar/x509`.

**Why.** Opposite answers to the same question, because the two problems are not
the same size. App Attest's CBOR is a fixed, tiny subset, and the valuable
property is *refusal*: a general parser accepts many encodings of one logical
value, and each is a way for two parties to disagree about what a document says
while both believe they parsed it correctly. Owning it means strictness is the
code rather than a library's configuration flag, and the rejection cases are
testable — which they are, one per refusal.

X.509 is the other extreme. Hand-rolling DER parsing and chain validation for a
security boundary is not defensible when a maintained implementation exists, and
the same library lets the suite mint a synthetic Apple-shaped chain, which is
what makes the attestation path testable at all without a device.

**Rejected.** A CBOR library (fewer lines, and its behaviour on hostile input
becomes somebody else's decision). Hand-rolled X.509 (several hundred lines of
DER parsing between an attacker and the ledger).

### D50. The client prorates straddling samples rather than asking HealthKit to bucket

**What.** `HourlyBucketer` splits a sample across the local hours it covers,
prorating by overlap. Instantaneous samples land whole in the hour they happened.

**Why.** A HealthKit cumulative sample covers an interval, and an interval can
cross an hour boundary — a 90-minute walk is one sample spanning three buckets.
Proration is exact when a sample lies inside one bucket, which is the ordinary
case since the pedometer records in short spans, and a linear estimate when it
does not.

The exact alternative is `HKStatisticsCollectionQuery` with an hourly interval
anchored to local midnight, which buckets without estimating. It was rejected
because a statistics collection reports sums without saying which source produced
them, and provenance is the point of this milestone. Recovering it means one
statistics query per source, so the query count grows with however many health
apps the user happens to have installed.

**Rejected.** Attributing a straddling sample wholly to the hour it started in
(no arithmetic, and it misplaces most of a long workout). One statistics query
per source (exact, and unbounded work per sync).

**Revisit if.** Proration error shows up in a dispute. The per-source statistics
query is the fix, and it is a client change only.

---

## M4 — Scoring engine

### D51. A contest is pass/fail against its terms, and the comparison is among those who passed

**What.** Every accepted participant either qualified or did not. One qualifier
wins. Several qualifiers is a tie, resolved by `contests.tie_break`. No
qualifier voids the contest and nobody donates. Highest score does not win.

**Why.** This is what the cadence enum already says it is: `'cumulative'` means
hit the target once across the window, `'daily'` means hit it on each day.
Neither says "whoever did the most", and the difference is a real settlement
outcome rather than a reading preference. The case that decides it is two friends
who each pledged $25 against a 100,000-step month, where one walked 40,000 and
the other 12,000. Under "highest total wins", the participant who missed their
goal by 60% collects a donation from a friend for a month in which neither of
them did the thing they staked money on. Voiding says the true thing: they both
failed, so nobody owes.

The consequence worth stating plainly is that ties become the *ordinary* result
rather than a rare edge. Two friends who both walk their 10,000 steps every day
have both qualified, and the tie-break is then the entire settlement. That is
also the retrospective justification for `tie_break` being declared at creation
and carrying a default (D22): under a highest-total rule, exact ties are
freak events and a four-option enum defaulting to `integrity_score` would be
over-engineering. Under this rule it is the main path.

**Rejected.** Highest score wins outright (one fewer concept, and it turns a
shared goal into a wager on the one path in the product that moves money).
Highest score wins among those who reached the target, voiding only when nobody
did (this is the same rule for cumulative and strictly worse for daily, where it
would mean a 29-of-30-day record beats a 28-of-30 one and the target has already
done its work at the day grain). Requiring a perfect record for daily *and*
ranking on it (already the rule; the note is that "perfect" is per whole local
day, not per calendar day of the window — see D52).

**Revisit if.** Real contests void often enough that users read it as the app
failing to pick a winner. The measurement to take first is how often a void is
"nobody qualified" versus a tie-break, because the fixes are opposite.

### D52. Daily cadence scores whole local days only, and ranks on the rate

**Amended by D62.** Whole days are computed separately inside each timezone
epoch. A consented transition drops the adjoining part-days from both sides.

**What.** A daily contest asks about the local days the window *wholly* covers in
the participant's frozen zone. Part-days at either edge are dropped from the
numerator and the denominator alike. Qualifying means clearing the target on
every one of those days, and the ranking key is `qualifyingDays /
scoreableDays`, never the raw count.

**Why.** Two participants in different zones cannot both have whole local days
inside one instant range. A window that is seven whole days in New York is six
whole days plus two part-days in Kathmandu (+05:45), because the window's bounds
land at 10:45 local there. Ranking on the count of qualifying days would cap the
Kathmandu participant at 6 against the New York participant's 7 and make them
unable to win a contest they played perfectly — a zone-dependent handicap, in
the scoring of a money pledge, which is exactly the unfairness D5 froze the
timezone to avoid. Rating makes the two comparable: 6/6 and 7/7 are both 1.0.

Dropping part-days rather than counting them as failures is the same
conservative direction D36 already chose one grain down for buckets. A part-day
cannot be fairly judged against a whole-day target — 18 hours is not a day — and
the alternative punishes a participant for their offset a second time. It also
closes an attack that the ledger cannot: evidence in a part-day is legitimately
writable, so a participant who missed a Wednesday could otherwise stuff the
edge day and manufacture a qualifying day out of an hour that was never a day.
Pinned by `fraud/stuffing-the-part-days-at-the-window-edges`.

**Rejected.** Counting every calendar day the window touches (simplest, and it
scores an 18-hour day against a 24-hour target). Ranking on the raw count (the
zone handicap above). Recomputing each measurement's local day in the engine
(D37 already rejected this, and the engine reads the stamped `local_day` for
exactly that reason — the only thing it derives is the denominator, which is a
fact about the window rather than about any row).

**Revisit if.** A contest shape appears where the number of days is itself the
score — "most days hit, no perfection required" — which is a different product
question than the one D51 settles.

### D53. Scoring is done in integer hundredths

**What.** Every measurement and target is converted to whole hundredths and
summed as an integer. A value carrying a third decimal place raises rather than
being rounded.

**Why.** Both columns are `numeric(12, 2)`, so every value is exactly a whole
number of hundredths, and IEEE doubles cannot represent most of them.
`8.7 + 0.1` is `8.799999999999999`, and `28.45 + 1.24 + 0.20 + 0.11` is
`29.999999999999996` — so a participant who logs exactly 30.00 minutes against a
30-minute target fails a float comparison by four parts in a quadrillion. That
is not a rounding-display concern; it is the qualification test from D51, and it
decides whether somebody donates. Landing precisely on the target has to
qualify, and integer arithmetic is the only way that is true every time rather
than usually. 12 digits of precision is at most 1e12 hundredths, comfortably
inside the range where integer arithmetic on doubles is exact.

Raising on a third decimal rather than rounding it is the same instinct as the
citext trap in D14: the value cannot come from the column it is supposed to come
from, so something upstream is reading the wrong thing, and rounding it would
make that invisible while still changing a total.

**Rejected.** Float arithmetic with an epsilon on the comparison (an epsilon is
a tuning parameter on a settlement rule, and picking it wrong is silent).
Rounding the total to two places at the end (fixes the display and not the
comparison — the comparison is the part that matters). `BigInt` (exact and
unnecessary at this magnitude, and it does not serialise to JSON).

### D54. An unresolvable tie is reported, not guessed

**What.** `integrity_score` is supplied by M5 through M4's optional input seam.
If that map is unavailable, an `integrity_score` tie-break returns `undecided`
with reason `integrity_score_unavailable` rather than an outcome. A tie the
declared tie-break genuinely cannot separate — equal integrity scores, or two
people crossing the target in the same hour — returns `undecided` too.

**Why.** Every way of manufacturing an answer here is worse than admitting there
isn't one. Falling back to the higher total silently applies a tie-break the
participants did not agree to at creation, which is precisely the thing declaring
it upfront was meant to prevent. Voiding cancels a contest that somebody won.
Ordering by user id settles a donation by whose UUID sorts lower. `undecided` is
the only answer that leaves the contest in a state M7's finaliser can refuse to
settle, which is what should happen to a contest whose winner is not yet
determinable.

A partial set of integrity scores is treated as none, because otherwise whoever
is missing a score loses by default — a worse failure than declining to answer,
and one that would look like a real verdict.

The related rule is that standings *are* fully ordered, including a final
fallback to user id, because a leaderboard is a list and has to render while a
contest is live. Ordering and deciding are kept strictly apart: `decide()` never
consults the ordering, and `scoring.test.ts` pins that two participants identical
in every respect produce a stable display order and no winner.

**Rejected.** Falling through a fixed chain of tie-breaks (deterministic, and it
still substitutes rules nobody agreed to). Coin-flip on a seed derived from the
contest id (reproducible and arbitrary, and impossible to explain to the loser).

**Revisit if.** Production integrity scores tie often, at which point the
question is what the second-order tie-break is — and it should be declared at
creation like the first, not chosen afterwards.

### D55. The engine scores; it does not flag

**What.** 90,000 steps in one hour scores as 90,000. A bucket first reported
eleven days after the hour it covers scores too. The engine excludes only what
the contest's own terms exclude: another metric, a bucket outside the window, a
part-day under daily cadence, someone not on the accepted roster.

**Why.** Admissibility is already settled before the engine sees a row —
`contest_evidence` filters `is_admissible` and reduces revisions (D35, D38) — and
a second opinion about what counts is exactly the drift D3 exists to prevent.
Plausibility is different in kind: it needs a tuning parameter, which makes it a
heuristic, which puts it in M5 by D6. An engine that quietly dropped an
implausible hour would also produce standings nobody could audit, since the
number it scored would appear nowhere.

What the engine owes M5 instead is the aggregate that makes the judgement
possible without re-reducing the ledger: per participant, the bucket and sample
counts, the largest single hour, and the worst reporting lag. Lateness in
particular cannot disqualify on its own — a watch that syncs on Friday is most
syncs, not an attack — but the lag between a bucket closing and its being
reported is what separates a late sync from a fabrication, so it is surfaced
rather than acted on. Both cases are in the corpus as fixtures that must *pass*,
so that nobody mistakes the engine's silence for a verdict.

The one thing it refuses outright is a ledger that contradicts itself: a bucket
carrying two different `local_day` values raises. `contest_evidence` groups
`local_day` rather than aggregating it precisely so that this arrives as two
rows (D37), and picking one would decide a day's total with nobody able to tell
which row was chosen.

**Rejected.** A plausibility ceiling in the engine (needs the tuning parameter
M5 owns, and a ceiling low enough to catch spoofing is low enough to catch a
genuine ultramarathon). Returning flags alongside standings (M5's remit, and the
engine would then have two reasons to change).

### D56. M4 ships the engine and no endpoint

**What.** A pure function and its corpus. No Edge Function, no RPC, no delivery
surface.

**Why.** Purity is what D3 wanted from TypeScript in the first place — the
milestone is defined as an engine with fixture tests including fraudulent ones,
and every case in the corpus is a function call rather than a request. Adding a
standings endpoint now would fix a response shape before the two milestones that
change it: M5 adds integrity scores and flags, M6 adds check-in and
workout-overlap adjustments. M7 owns settlement and is the natural home for the
read surface, since it needs standings anyway and will have both by then.

**Rejected.** A `score-contest` Edge Function now (gives the milestone something
reachable, at the cost of a response contract that churns twice before anything
consumes it, plus an authorization surface — who may read whose standings — that
belongs with settlement).

**Revisit if.** The M8 client shell needs live standings before M7 lands. The
engine is already the hard part; the endpoint is a read and a call.

## M5 — Anti-cheat rules and integrity scoring

### D57. Integrity is a sidecar to scoring, and feeds only the existing seam

**What.** `assessContestIntegrity()` reads the same fixture-shaped input as M4
and emits flags plus a complete score map. `scoreContestWithIntegrity()` passes
that map through `ScoringInput.integrityScores`. It does not change
`scoreContest()`, qualification, totals, or `contest_evidence`.

**Why.** A heuristic and an admissibility rule answer different questions.
"Manual evidence never counts" is an invariant; "15,000 steps in an hour needs
review" is a tunable judgment. Letting the second quietly behave like the first
would create two definitions of evidence and standings whose missing values
could not be explained from the ledger. The existing M4 seam was designed to
avoid exactly that change: integrity can decide the declared tie-break without
becoming a second scoring engine.

Calling M4 once before assessment also gives M5 exactly M4's accepted roster and
validates the ledger before a flag is produced. A caller-supplied integrity map
is ignored during assessment, so nobody can seed the result with a score they
chose themselves.

**Rejected.** Filtering flagged buckets before calling M4 (quietly disqualifies
admissible evidence). Adding flags to `ContestScoring` (makes the scoring engine
own heuristics D55 explicitly kept out). Scoring only participants who have at
least one flag (a missing score loses an integrity tie by accident; D54 requires
a complete set).

### D58. Every integrity threshold and penalty is versioned configuration

**What.** Current launch tuning lives in `DEFAULT_INTEGRITY_TUNING`; the exact
pre-timezone `m5-v2` shape remains exported as `M5_V2_INTEGRITY_TUNING` for
reproducible old assessments. The configuration carries per-metric hourly
ceilings, same-hour corroboration rules, minimum travel distance, maximum travel
speed and gap, reviewed third-party bundle identifiers and reputation tiers,
timezone-change handling where the version supports it, reporting-lag and
quarantine thresholds, severities, points per flag, and per-rule penalty caps.
The default scale starts at 100, subtracts capped penalties, and floors at 0.
Every assessment names the configuration version.

**Why.** These numbers will move against real data. Keeping them in one data
object makes a tune a reviewed configuration change rather than a rewrite of
the evaluator, while the version makes old flags reproducible. Per-rule caps
stop one noisy device generating twenty identical hours from consuming the
entire score through volume alone.

Invalid tuning raises. A quarantine threshold earlier than the ordinary lag
threshold, a negative penalty, or a rule that corroborates itself is a broken
configuration, not an alternate scoring policy to accept quietly.

**Rejected.** SQL CHECKs for ceilings (a migration per tune, and turns judgment
into rejection). Severity names with hard-coded weights (two tuning surfaces
that can disagree). Uncapped per-occurrence subtraction (measures sync volume as
much as integrity).

**Revisit if.** Production calibration wants contest-type or cohort-specific
profiles. They should still be immutable versioned objects selected before an
assessment, not branches inside the evaluator.

### D59. Impossible travel requires an explicit location signal

**What.** M5 accepts optional `(user, observed_at, latitude, longitude,
accuracy)` observations. Consecutive points raise `impossible_travel` only when
the configured minimum distance and maximum speed are both crossed after both
accuracy radii are subtracted. M6's accepted, attested geofence locations are
the concrete producer.

**Why.** Metric buckets contain a time and a frozen timezone, not a physical
location. Inferring a city from that zone would turn every traveler and every
large multi-city zone into false evidence, while claiming precision the input
does not have. Making location an explicit input lets the rule and fixtures
exist now without laundering an inference into a fact.

**Rejected.** Treating a timezone change as travel (timezone is frozen, and a
zone is not a point). IP geolocation on ingest (records a network exit, performs
poorly on cellular relays and VPNs, and adds location collection to an endpoint
that does not need it).

### D60. Retroactive quarantine is review state, not a new admissibility bit

**Amended by D76.** Pending or rejected peer review gates finalization and
settlement, not provisional scoring. After the bounded independent path ends,
M7 may record `inconclusive` without treating the evidence as approved or
filtering it out.

**What.** `evidence_quarantines` records the exact snapshot, rule version,
signal key, configured threshold, server-derived reporting lag, and details.
`evidence_quarantine_reviews` records immutable votes. A duel needs its opponent;
a group needs a strict majority of the other accepted participants. Silence is
`pending`; enough no votes to make approval impossible is `rejected`.

The snapshot remains untouched and still appears in `contest_evidence`.
Provisional standings may still score it. M7 may persist a settlement-bearing
result only after its complete integrity assessment is recorded and every
materialized quarantine is either peer-approved or explicitly cleared through
D76 adjudication. Pending review, rejected review without a clearance, and an
incomplete assessment all gate finalization; none means M5 secretly recomputes
the score without the value.

**Why.** The ledger must show both facts: "the attested phone reported this
value" and "it reported it late enough to require review." Overwriting
`is_admissible`, deleting the row, or filtering the M4 view would erase the
first fact in order to express the second. Append-only review votes make the
approval path auditable and prevent someone reversing a vote after seeing the
emerging outcome.

Creation is service-role-only and derives identity and lag from the snapshot;
participants cannot manufacture a quarantine against a rival. Review goes
through one definer function that checks the caller is another accepted
participant. Identical retries are idempotent and conflicting retries fail.

**Rejected.** A mutable `quarantine_status` column (loses who decided and how).
The evidence owner self-approving (no review). Timeout-as-approval (silence
becomes consent in the exact path meant to fail closed). Excluding pending data
from `contest_evidence` (silent disqualification and a second definition of
admissibility).

**Revisit if.** Product wants reviewers to revise a mistaken vote. That needs a
new append-only supersession row and an explicit window, not UPDATE.

### D61. Third-party reputation is a versioned sidecar, never admissibility

**What.** `contest_evidence_sources` exposes the current M3 `provenance` and
`source_bundle_id` beside, rather than inside, `contest_evidence`. It is a
`security_invoker` view over the same RLS-protected ledger. Within one bucket and
provenance it follows M3's current-value rule; identical current observations
collapse to one source signal, and equally current observations that disagree
about their bundle identifier resolve to `NULL` instead of choosing one.

`DEFAULT_INTEGRITY_TUNING.sourceReputation` carries a canonical lower-case
allow-list plus independently weighted `unrecognized`, `missing`, and
`malformed` tiers under one participant-level cap. The launch `m5-v2` list
contains reviewed Garmin Connect, Nike Run Club, and Strava identifiers. A
known identifier raises no flag. A lower tier raises
`third_party_source_reputation`, records `evidenceStillScores: true`, and may
lower only the complete integrity-score map passed through D57's M4 seam.
Device provenance bypasses this third-party rule.

**Why.** D38 intentionally made `third_party` admissible while reserving the
reputation of a *particular* app for a heuristic. Bundle identifiers are useful
signals but not proof: a malicious client has a motive to lie, and even an
attested honest client can receive missing attribution when two HealthKit
writers share a bucket. Versioning the list and tier weights makes later
calibration reproducible. One shared cap prevents a participant's sync volume
from mattering more than the reputation judgment itself.

The view is deliberately parallel to `contest_evidence`. Adding provenance
columns to M4's aggregate would either split a scored hour into extra rows or
force the scoring engine to own a heuristic. Keeping source metadata beside the
score preserves the one definition of each bucket while making the integrity
decision auditable.

**Rejected.** Removing unknown sources from `contest_evidence` or rewriting
`is_admissible` (silent disqualification and a second evidence rule). A database
CHECK or foreign key allow-list (turns a tunable reputation judgment into an
ingest invariant). Penalizing device rows for bundle syntax (confuses audit
metadata with first-party provenance). Counting identical retry observations as
new flags (makes network behavior change a tie-break).

**Revisit if.** The reviewed list needs an operational owner or faster release
cadence. It should become an immutable, signed configuration selected by version,
not a mutable lookup whose meaning can change underneath an old assessment.

### D62. A timezone relocation is a consented, prospective epoch

**What.** `contest_participants.timezone` remains the immutable zone a
participant accepted. A relocation is recorded beside it as an append-only
request, immutable votes, and—only after approval—an immutable applied change.
The requester must be accepted in an active contest. Every other accepted
participant must approve: one opponent in a duel, all opponents in a group.
Silence stays pending and one rejection is final.

The effective instant is server time when the last approval is recorded, never a
caller-supplied value. Ingest resolves the applicable zone from the latest
applied change at or before `bucket_start`; a late revision from before the move
therefore still uses the old zone. An hour cut by the effective instant belongs
to neither epoch and is refused.

Daily scoring computes whole local days independently inside each timezone
epoch. A transition cuts the adjoining part-days out of both numerator and
denominator, and days are keyed by epoch plus civil date so crossing the date
line cannot merge two different days with the same `YYYY-MM-DD`. The portable
client bucketer applies the same schedule and drops the same transition-cut
hours.

The scoring API requires callers to supply the complete applied-event ledger,
including an explicit empty ledger. Omission fails closed rather than silently
scoring every hour and day in the base zone.

An applied event raises the distinct `timezone_change` integrity flag under the
versioned `m5-v3` tuning. It may lower the integrity-score tie-break by 10 points
per change, capped at 20, but never removes evidence or pretends that a timezone
is a location.

**Why.** Rewriting the one roster timezone would rewrite history without
touching a ledger row. A delayed correction to an old bucket could suddenly fail
alignment or acquire a second `local_day`, while M4 would recompute the entire
daily denominator in the new zone. The result would depend on when the
relocation was approved rather than when the activity happened.

Prospective epochs preserve both facts: which zone governed an old claim, and
that opponents consented to a real move. The participant-row lock shared by
approval and ingest makes the effective boundary atomic with evidence writes.
Unanimity is deliberate because the change alters the scoring contract each
opponent accepted; D60's majority rule reviews a claim, it does not amend terms.

**Rejected.** Updating `contest_participants.timezone` in a definer function
(triggers still reject it, and bypassing them would relabel history). A
caller-chosen effective instant (retroactive boundary shopping). Following the
device's live zone (the original D5 exploit). Majority approval in a group
(changes an opponent's agreed comparison without their consent). Treating the
move as `impossible_travel` (D59: a zone is not a location).

**Revisit if.** Group contests need a more available approval rule. That requires
an explicit product decision about who may amend shared terms, not reuse of the
evidence-review quorum by analogy.

## M6 — Geofence check-ins and workout-overlap validation

### D63. A geofence check-in is immutable evidence, not a client verdict

**What.** `contest_geofences` is service-provisioned before activation and
immutable thereafter. A contest-row lock makes provisioning atomic with
activation. The row fixes the center, radius, accepted accuracy, minimum dwell,
maximum sample gap, and minimum workout overlap. The signed client body reports
only raw, explicitly located Core Location observations and one HealthKit
workout; it never reports an `inside` boolean or a dwell total.

Postgres computes and stores every Haversine distance and sample classification,
then stores one closed, deterministic outcome on the append-only check-in row.
A cryptographically invalid request never reaches the ledger because its user
and evidence cannot be authenticated. Once authentication succeeds, a
well-formed semantic failure is retained rather than disappearing: future or
out-of-window evidence, simulated or inaccurate locations, an outside venue,
insufficient dwell, and workout conflicts are all auditable facts.

**Why.** Letting a client send "I was at the gym for ten minutes" makes
attestation protect a conclusion the same client chose. Recomputing from the
raw signal under immutable terms gives disputes both the claim and the rule that
judged it. Keeping failed signed attempts closes the quieter attack in which
only successful evidence survives and repeated boundary probing leaves no
trace.

The RPC is executable only by `service_role`, after the Edge Function verifies
JWT ownership and the App Attest assertion over the exact body bytes. Client
roles receive no insert, update, delete, or execute path. RLS lets an accepted
rival inspect shared geofence terms and derived outcomes, but exact raw and
trusted coordinate rows are owner-only; the server-side integrity consumer
retains them through `service_role`. The development bypass is permanently
marked `attested = false` and its locations never enter the trusted-location
view.

**Rejected.** A mutable venue row (changes what old evidence means). Trusting a
client-computed distance or dwell (signs an opinion, not evidence). Inferring a
venue from timezone, IP, or HealthKit totals (none is a location). Storing an
invalid signature as somebody's attempt (the claimed identity was not proven).
Appending an alternative venue after activation (changes the allowed terms
without participant consent).

### D64. Dwell and workout overlap are unions of observed absolute-time segments

**What.** Credited dwell is the sum of consecutive `inside -> inside` sample
intervals whose gap is no greater than the geofence's configured maximum.
Outside, low-accuracy, or simulated points break the chain. A long sampling gap
also breaks it; the server does not fill an unobserved interval.

Workout validation intersects its half-open absolute range with those credited
segments and sums the intersections. It does not intersect against the
first-to-last visit envelope, which can contain broken or unobserved gaps.
All inputs are `timestamptz` instants. Touching `[start, end)` endpoints do not
overlap, and neither a participant timezone nor a calendar is consulted.

**Why.** Sampling is discrete, so there is no perfectly knowable continuous
visit. Crediting only bounded adjacent observations is conservative,
deterministic, and explainable from the ledger. Using the visit envelope would
award a workout that happened during a ten-minute gap between two otherwise
valid samples. Absolute half-open arithmetic gives the same answer through DST,
offset changes, and reordered input.

One workout is attached to one check-in in M6. Supporting a workout set would
need a canonical union and a product rule for mixed provenance; silently
inventing either would make the first implementation impossible to reproduce.

**Rejected.** Client-calculated dwell (not authoritative). A fixed number of
inside samples (depends on sampling frequency). Filling gaps up to the whole
visit (credits time without evidence). Local wall-clock overlap (ambiguous at
DST folds and nonexistent at gaps).

### D65. Only accepted check-ins reserve visit and workout evidence

**What.** Accepted rows are subject to three database-enforced replay rules:
one user cannot have overlapping accepted visit ranges, cannot have overlapping
accepted workout ranges, and cannot accept the same workout UUID twice. The two
range rules are partial GiST exclusions using the existing `btree_gist`
extension. They apply across contests for the user, and half-open boundaries may
touch. Failed attempts remain in the audit ledger but reserve nothing, so a
corrected submission can reuse the real workout.

The caller-generated check-in UUID is unique per user. An identical retry is
recognized by the SHA-256 digest of the exact signed bytes before the shared App
Attest counter is consumed and returns the original result. Reusing the UUID
with different bytes fails loudly. A per-user profile lock serializes the
idempotency lookup, assertion counter, and accepted-range decision, while the
constraints remain the final concurrency backstop.

**Why.** The same physical presence or workout must not validate two simultaneous
claims simply because they name different contests or device keys. Making only
accepted evidence reserve time avoids turning a low-accuracy first attempt into
a permanent denial of service against its corrected retry. Digest-bound
idempotency handles the common timeout-after-commit case without weakening the
monotonic assertion counter.

**Rejected.** A uniqueness check in the Edge Function (races across instances).
Consuming the assertion counter before checking an identical retry (makes a safe
network retry look like a replay attack). Excluding failed ranges (lets invalid
evidence block valid evidence). Treating boundary-touching workouts as overlap
(half-open intervals share no elapsed time).

### D66. M6 remains an integrity sidecar, and only accepted attested locations travel

**What.** Check-in validation never updates `metric_snapshots`,
`contest_evidence`, admissibility, qualification, or totals. The
`contest_checkin_integrity` view supplies two new versioned signals under
`m6-v1`: `geofence_checkin_failure` for venue/window/dwell/visit failures and
`workout_overlap_validation` for workout trust, reuse, and overlap failures.
Historical `m5-v2` and `m5-v3` tuning objects remain loadable with both rules
disabled, so an old assessment does not acquire a new penalty.

`contest_location_observations` is the concrete producer D59 anticipated. It
contains only `inside` samples from an `accepted` and `attested` check-in.
Simulated, inaccurate, outside, failed, and development-bypass observations
remain visible to their owner and the service in the raw audit ledger but cannot
raise `impossible_travel` or expose a failed location to a rival.
The portable Swift evaluator mirrors distance, dwell, and overlap only for
immediate UX; Postgres remains authoritative. Its retry queue retains the exact
body bytes that App Attest signed and can restore persisted pending values after
an app relaunch.

**Why.** A geofence result is a useful credibility signal, but it does not prove
that an otherwise admissible HealthKit total is false. Rewriting the evidence or
score would create a second scoring engine and erase the distinction between
"reported activity" and "venue validation failed." Feeding only trusted,
explicit coordinates into impossible travel finally enables that rule without
pretending timezone or aggregate exercise data locates a person.

**Rejected.** Deleting or filtering metric evidence after a failed check-in
(silent disqualification). Feeding every raw location to impossible travel
(turns spoofed evidence into a penalty). Making Swift's advisory answer
authoritative (two engines can diverge). Re-encoding queued JSON on retry
(changes the bytes the assertion covers).

### D67. Review quorum is an immutable request fact

**Amended by D81.** The roster cascade described below is historical; M7
preserves the pseudonymous participant row. The snapshotted denominator and
non-cascading vote identity remain required audit invariants.

**What.** A quarantine or timezone request snapshots the number of eligible
reviewers when it is created. Votes retain the reviewer's UUID without a
cascading foreign key to `profiles`; deleting an account cannot erase a vote or
shrink the stored denominator. Status is derived from the immutable denominator
and retained votes, never from today's roster.

**Why.** When D67 shipped, account deletion still cascaded through
`contest_participants`. Deriving quorum from that live table made deletion a
vote: it could reopen a rejection or turn a missing approval into consent. A
pseudonymous UUID is enough to prove that one eligible identity voted once
without retaining a social profile.

**Rejected.** `ON DELETE CASCADE` (rewrites a terminal decision). `RESTRICT`
(makes account deletion impossible). Recomputing from the surviving roster
(silence becomes consent).

### D68. A timezone epoch must be strictly inside the contest window

**What.** Final approval computes one millisecond-precision server instant,
validates `starts_at < effective_at < ends_at`, and stores that same value. A
database trigger enforces both the precision and boundary invariants for
privileged fixture or maintenance writes too, and the hardening migration
refuses to certify an existing ledger until any prior violation is reconciled.

**Why.** Reading the clock once for validation and again for insertion allowed a
contest to end between the two operations. The resulting epoch could not be
scored, because the scoring engine correctly rejects boundaries outside the
window. Truncation also means a just-after-start wall clock can equal a
microsecond-precision start. Failing the transaction and retrying is safer than
persisting an unscoreable contest.

### D69. `service_role` is a route to guarded RPCs, not a ledger editor

**What.** M5/M6 migrations revoke environment-default table rights from
`service_role`, then grant back only required reads, geofence-definition insert,
and guarded RPC execution. Derived consent, quarantine, check-in, and location
rows cannot be forged or deleted directly by that role.

**Why.** Supabase projects created under different defaults disagree about
whether `service_role` receives automatic CRUD on new public tables. Security
must not depend on project age. Security-definer RPCs run as their owner, so the
caller does not need direct table mutation rights.

### D70. The check-in queue never evicts irreplaceable evidence

**What.** Pending check-ins are codable exact-byte values with a validating
restore initializer. A full queue refuses the new request and surfaces the
event; it does not discard the oldest request.

**Why.** HealthKit metric batches can be reconstructed by querying HealthKit
again. A sampled Core Location visit cannot. A bounded buffer is still useful,
but eviction would silently destroy the only copy of physical-world evidence.
Persist-and-restore makes the idempotency contract survive a relaunch rather
than only a timeout in one process.

### D71. An App Attest receipt is quarantined outside the client schema

**What.** Registration requires Apple's non-empty `attStmt.receipt` and stores
the initial and current copies in `app.device_attestation_receipts`, keyed to
the verified device row. Both are bounded to 32 KiB, cascade only with the
device identity, and are exposed by no client or `service_role` table grant.
The server independently verifies the bounded BER/PKCS#7 signature and Apple
Root CA G3 chain, the dedicated receipt-signer certificate marker, App ID,
creation time, and stored public-key binding. It uses the row's immutable first
capture time as the freshness boundary. Every failure leaves
`current_receipt_verified_at` null. After all checks pass, only a narrowly
scoped, `service_role`-only security-definer RPC may set that timestamp; the RPC
row-locks the candidate and requires the SHA-256 digest of the still-current
receipt to match. No fraud or eligibility decision may use a quarantined
receipt.

**Why.** Apple returns the receipt for later fraud-risk assessment. Discarding
it during registration would make that assessment permanently impossible
without forcing the user to generate a new device key. It is opaque server
credential material, not profile data, so keeping it beside the public,
RLS-readable device-key row would expose it for no product benefit. The
security-definer registration RPC is the only capture route. The App Attest
certificate nonce authenticates the key registration, not an arbitrary receipt
field placed beside it, so the server captures first, verifies independently,
and marks only the exact bytes it verified. A generic certificate chaining to
the same Apple root is insufficient without Apple's receipt-signer marker.
Retaining an immutable initial copy and a separately rotatable current copy also
supports Apple's later receipt-refresh contract without erasing the audit
source.

### D72. Hosted functions verify user JWTs from JWKS in code

**What.** Hosted functions read `SUPABASE_JWKS` and accept only a uniquely
selected ES256 or RS256 verification key. Local or explicitly legacy
deployments may use an HS256 secret. Every accepted token must name this
project's `${SUPABASE_URL}/auth/v1` issuer and the `authenticated` audience.
All three endpoints set the gateway's legacy `verify_jwt` option to false,
authenticate immediately after the method check, and only then read a request
body. Hosted `SUPABASE_SECRET_KEYS` reach PostgREST through `apikey` only;
opaque `sb_secret_` values are never treated as bearer JWTs.

**Why.** A new Supabase project can issue asymmetric user sessions while the
legacy gateway verifier and legacy service-role conventions still assume
JWT-shaped API keys. Leaving both assumptions in place makes a correct staging
token fail before application code runs, or makes an opaque admin key fail as
an invalid JWT. Code-level verification supports the project's actual signing
keys while preserving the invariant that no unsigned caller reaches an ingest
write. The configured trust source, not the token header, selects the permitted
algorithm.

### D73. Staging mutations require a checked-in project identity

**What.** `supabase/staging-project-ref` is the single reviewed allowlist for
M6.5 staging. It contains `UNCONFIGURED` before a dedicated project exists and
must contain the reviewed nonsecret ref before any staging mutation. The
secret-upload script refuses a different `SUPABASE_PROJECT_REF`; the fixture
wrapper additionally requires a direct database URL whose
`db.<project-ref>.supabase.co` host carries that exact ref. The SQL refuses to
replace either reserved fixture ID if its existing row does not carry the
expected synthetic identity.

> **Implemented 2026-07-25 in `cc8f440`:** the dedicated staging identity was
> reviewed and configured. A working copy that still reads `UNCONFIGURED` is
> behind `origin/main` and must be reconciled before using either staging
> script.

**Why.** Calling a project “staging” in the same command that selects it is not
an independent safety check. A mistyped production ref would otherwise enable
development attestations there, and the fixture intentionally recreates one
contest. Recording the nonsecret staging identity in reviewable source makes
the mutation target a repository decision rather than an operator assertion at
the dangerous moment.

## M7 — Settlement and finalization product contract

These decisions are intentionally recorded before the M7 schema. They define
what the later result, obligation, dispute, reliability, and notification rows
must mean; they do not bypass M6.5's physical-device gate.

### D74. Honoring a pledge requires a claim plus an independent confirmation path

**What.** GameTime still does not move money. A donation obligation becomes
actionable only after D78's result-dispute window has closed and every timely
result dispute is resolved—the later of those events—and is due 30 days later,
using server timestamps. The debtor may then submit an append-only claim naming
the obligation, donation time, amount, charity, and evidence kind. The charity
must match the obligation snapshot, and the allocated amount must cover the
stake. Launch is USD-only: obligation amounts, claim amounts, receipt totals,
and receipt allocations are integer US cents. No currency conversion or
floating-point amount enters confirmation. The claimed donation time must be no
earlier than the debtor's acceptance of that pledge and no later than the
claim's server-recorded submission time.
When the provider or receipt path is used, its evidence must substantiate the
same time; a future assertion or a receipt predating the pledge cannot qualify.
A donation receipt here means a redacted proof of a charitable donation; it is
unrelated to the private App Attest receipt in D71.

A claim becomes confirmed as honored through any one of three independent
paths:

1. a verified charity or payment-provider integration confirms it;
2. the winner accepts the claim; or
3. a receipt-backed claim survives a seven-day challenge window without a
   dispute.

Self-attestation alone records `claimed`, not `honored`. It can still become
honored through winner acknowledgement or an adjudicator's decision, which
keeps cash, employer-match, and other receiptless donations possible without
turning an unchecked tap into reliability credit. A declared `both_donate`
result has no winner, so any accepted co-participant may challenge one of its
self-directed claims; acknowledgement is not available as a shortcut there.
A receiptless claim not acknowledged within seven days expires and stops
pausing default. The debtor may dispute that expiration under D78 if independent
evidence requires adjudication.

The claim's submission time decides whether an eventual confirmation was on
time. A claim submitted by `due_at` does not default while its challenge or
dispute is open. No qualifying claim at the deadline records a default. Later
proof may append a late-honored resolution, but it never erases the fact that
the pledge first defaulted. During the challenge window, every person authorized
to challenge under this decision may see the claim fields and a redacted receipt
preview sufficient to assess charity, amount, date, and reuse. The original
receipt object remains private to the debtor, a confirming provider, and the
adjudicator. Receipt objects are immutable and content-digested. Claims allocate
receipt value to obligations, and the server refuses allocations beyond the
receipt's total, so one larger donation may legitimately cover several pledges
without being double-counted.

**Why.** Self-attestation alone makes the product's most important reputation
fact self-awarded. Requiring the winner to act in every case makes silence a
veto and fails completely for `both_donate`. Requiring a charity integration at
launch would make the curated charity list unusable until every destination had
one. The combined rule gives ordinary receipt-backed donations a bounded path,
keeps a social acknowledgement path for legitimate receiptless donations, and
leaves a stronger machine-verification seam without pretending it already
exists.

The seven-day claim challenge is deliberately separate from both the seven-day
result-dispute window and the 30-day donation deadline. Nobody is prompted to
donate while the result can still change. A debtor may act on day 30 and still
receive a fair claim-review window; submitting on time pauses default rather
than forcing the counterparty to review instantly.

**Rejected.** Self-attestation as confirmation (the debtor awards their own
reliability credit). Mandatory winner acknowledgement (silence can hold an
obligation forever, and there is no winner in `both_donate`). Receipt upload as
immediate proof (a file can be forged or reused). Timeout with no evidence
(silence becomes payment). A charity integration as the only launch path
(coverage would be smaller than the curated list).

**Revisit if.** A donation provider supplies signed, idempotent confirmations
for most supported charities. That path can then become the preferred UX, but
the social and receipt paths should remain for donations made elsewhere.

### D75. Every contest that ran finalizes to an explicit result, not necessarily a winner

**What.** `finalized` means the evidence boundary and computation are fixed; it
does not mean somebody won. A contest that opened gets an immutable result with
one of four kinds:

- `winner`: one winner, with one normal obligation per other accepted
  participant under D4;
- `all_donate`: the declared `both_donate` tie-break, with one full-stake,
  self-directed obligation for every accepted participant;
- `void`: the scoring rules answered that nobody owes, because nobody qualified
  or the declared tie-break was `void`; or
- `inconclusive`: GameTime could not produce the agreed deterministic answer,
  including a genuine `tie_break_inconclusive` or D76's review failure.

`void` and `inconclusive` create no donation obligations. A contest that never
opened remains `cancelled`, with its existing cancellation reason, rather than
acquiring a result row.

The scoring engine retains `insufficient_participants` as a defensive answer for
non-open input, but activation cancellation is the only product path for a
contest that missed quorum. Receiving that answer for an already active contest
is an invariant failure: M7 retries and alerts without persisting a result. It
does not reinterpret that failure as `void`.

The `all_donate` mapping deliberately uses the complete accepted roster, not
only the tied qualifiers currently returned by the M4 shape. Otherwise a group
participant who missed the target would owe nothing while the participants who
met it donated. Each person donates to their own preselected charity because
there is no agreed winner whose nomination could supply a destination, and each
person's exposure remains exactly the stake they accepted. M7 must update the
`Outcome` domain contract and its fixtures so `all_donate` carries the complete
accepted roster. The finalizer validates that exact match and refuses a mismatch;
it does not reinterpret or repair scoring output while persisting it.

Every result records its evidence cutoff, scoring version, integrity
configuration version, and finalization time. Result rows are append-only. If
D78 authorizes a correction, a new row supersedes the old one and matching
release/replacement obligation events are appended; no historical verdict or
obligation is rewritten.

`integrity_score_unavailable` is not a fifth result kind. M7 always owns a
complete integrity assessment, so that reason is an operational failure to
retry and alert on. Persisting it as a terminal user outcome would turn a
missing dependency into a product rule.

**Why.** Lifecycle and outcome answer different questions. The row can be
finished even when its honest answer is "nobody qualified" or "the agreed
tie-break could not separate them." Keeping `finalized` as the lifecycle state
lets ingest close once, while the result says whether settlement exists and why.
It also prevents the two worst fallbacks: leaving an ended contest `active`
forever or manufacturing a winner merely to reach a terminal state.

**Rejected.** New top-level `void` and `inconclusive` contest statuses
(duplicates result state across two places). Treating a void result as
`cancelled` (confuses an earned outcome with a contest that never ran). Treating
every non-winner result as void (hides the difference between "nobody qualified"
and "the system could not decide"). Assigning group `all_donate` only to tied
qualifiers (rewards a nonqualifier for failing).

**Revisit if.** A future contest format legitimately has several winners. It
should add a new result kind and an explicit obligation mapping rather than
overload `winner`.

### D76. Grace closes ingest; peer review and adjudication are separately bounded

**What.** The six-hour value returned by `app.ingest_grace_period()` remains the
earliest possible finalization time. Evidence may arrive until that instant,
and no result is fixed before it. Quarantine review never shortens or reopens
ingest.

Before the absence of a quarantine can permit finalization, the trusted path
serializes with ingest, runs and persists one complete versioned integrity
assessment over the frozen evidence, and materializes every quarantine that
assessment requires. A failed or incomplete assessment retries and alerts; zero
rows is meaningful only after successful completion and never counts as a clean
result by itself.

Eligible peers may review as soon as a quarantine exists and D77's bounded facts
are available, including while the contest is live. Its peer deadline is 72
hours after the later of grace close and that quarantine's creation, so early
review is useful and a quarantine materialized after grace still receives a full
window. Finalization may proceed only after grace, successful assessment, and
approval or explicit operator clearance for every quarantine. A quarantine that
reaches `rejected` escalates immediately; one still `pending` at its peer
deadline escalates then. Neither state changes `contest_evidence`, and neither
silence nor a timer means approval.

Escalation creates an append-only adjudication request for a platform operator
and a seven-day operator deadline measured from the later of grace close and
escalation. The adjudicator may explicitly clear the gate, using the existing
evidence as recorded, or declare the contest `inconclusive` because the evidence
cannot safely support settlement. The adjudicator may not delete the bucket,
substitute a value, or pick a winner. An early clearance still cannot bypass
grace or the complete assessment. If the operator deadline passes unanswered,
M7 finalizes the contest as `inconclusive` with reason `review_timeout` and
creates no obligations.

The peer and operator durations are named server configuration, like the ingest
grace period, rather than copied constants in a worker. Pending timezone-change
consent is different: if it never reached approval there is no applied epoch,
so it neither extends finalization nor changes scoring.

**Why.** Finalizing at the six-hour boundary would give a last-second snapshot
no meaningful review. Waiting forever would let an opponent or an absent
reviewer hold every other participant in an active contest indefinitely.
Auto-approving would defeat the fail-closed property D60 exists to provide.
Bounded peer review followed by independent adjudication gives silence an exit
without giving it evidentiary force, and the final fallback says the honest
thing: the system could not verify a settlement-grade result.

Immediate escalation on rejection also avoids making a rival's vote a power to
void the contest unilaterally. The immutable vote remains part of the audit
trail, but a separate authority owns its consequence.

**Rejected.** Finalizing exactly at grace close despite pending review (no real
review opportunity). Timeout-as-approval (silence becomes consent). Automatic
void on the first rejection (one rival controls the outcome). Unbounded staff
review (moves the indefinite wait one queue downstream). Excluding rejected
evidence and rescoring (creates the second admissibility rule D60 rejected).

**Revisit if.** Production response data shows 72 hours is too short for peer
review or seven days is operationally unrealistic. Change the named durations,
not the state semantics.

### D77. Standings belong to accepted participants, with integrity detail revealed by role and phase

**What.** Live and final standings are readable only by accepted participants
in that contest and by the trusted finalization/adjudication service. An invite,
friendship, shared group, or public profile is not standings access. Access
survives a later block and, after pseudonymization, continues for the remaining
accepted participants because neither action may hide the record an obligation
rests on.

The participant surface is deliberately layered:

- While live, every accepted participant sees ranks, progress, qualification
  state, whether a review is required, and a prominent `provisional` label.
  They see their own exact integrity score, flags, and supporting detail. For a
  rival they see neither exact deductions nor raw flag evidence before the
  evidence window closes. As soon as a quarantine exists, an eligible reviewer
  may see only the claim they must judge—participant, metric, bucket, value,
  provenance class, recorded time and lag, rule/version/threshold, and revision
  history—and may vote even before contest end. They do not receive coordinates,
  device or source identifiers, or unrelated flags.
- From contest end through ingest grace and D76 review, the same result remains
  `provisional`, with an `awaiting_ingest` or `under_review` reason. Grace close
  does not reveal rival details by itself; the bounded reviewer access above
  continues only while that review requires it.
- Once final, every accepted participant sees the exact totals, qualification,
  tie-break inputs, integrity score, configuration versions, and bounded
  rule-level rationale that produced the result. That is enough to explain and
  dispute the verdict.
- Raw coordinates, device identifiers, attestation material, donation receipts,
  third-party source identifiers, and private adjudicator notes are never part
  of a rival's standings response. The subject may inspect their own raw records
  while they remain inside D81's retention window, then only the retained
  aggregate and adjudicated facts; an authorized adjudicator may inspect what
  the case requires.

M7's standings response is the canonical client read surface. Existing broad
rival access to audit tables must be narrowed where it would bypass these
phase- and role-specific disclosures. A live ordering is presentation only and
must not be described as a predicted winner.

**Why.** A participant must be able to audit the rule that may make them donate,
but live anti-cheat details are also a tuning oracle: they show exactly which
behavior changed an integrity tie-break while there is still time to submit
evidence. The phased surface preserves final explainability without publishing
a health timeline, a location trail, or a receipt to a group. Restricting the
audience to people who accepted also preserves M3's rule that an unanswered
invitation cannot buy access to another person's activity.

**Rejected.** Public or group-wide standings (publishes health-backed pledge
terms beyond the people who accepted them). Any roster row as authorization
(includes declined and lapsed invitations). Full rival integrity detail while
live (a gaming and harassment surface). A final result with no rationale
(cannot be meaningfully disputed). Raw location in standings (never necessary
to render rank or explain a derived check-in result).

**Revisit if.** GameTime deliberately launches public leagues. That requires a
new consent and redaction model; widening this policy is not enough.

### D78. Disputes pause consequences and are resolved by an independent, audited authority

**What.** There are two user-filed scopes:

- any accepted participant may dispute a contest result event whose D78
  `user_filing_deadline` is open; and
- the debtor, winner, or other D74-authorized challenger may dispute a pledge
  claim, claim expiration, confirmation, default, release, or reinstatement
  event whose `user_filing_deadline` is open.

An initial challengeable event records a deadline seven days after its durable
notification intent. Events declared user-terminal below record no new deadline;
the receipt-timeout confirmation exception is also explicit below. Storing the
nullable deadline on the event makes authorization depend on the decided
lineage, not on a caller reconstructing which seven-day rule applies.

A platform operator may open a case for a systemic error only while the evidence
required for that scope remains inside D81's applicable raw-evidence retention
window and its persisted `operator_open_until` has not passed. Permanently
retained aggregate or adjudicated facts do not keep that window open. The
operator acts through an explicit adjudicator authorization and a guarded RPC,
may not be a party to the case, and never receives direct UPDATE rights on
results, obligations, claims, or evidence.

Disputes are append-only event streams with a 14-day adjudication deadline from
filing:

`filed -> under_review | withdrawn | timed_out | superseded`

`under_review -> upheld | denied | withdrawn | timed_out | superseded`

A filer may withdraw their own support before adjudication; the case becomes
`withdrawn` only after the filing window closes, every user filer has withdrawn,
and no operator has adopted it. Until then another eligible user may join, and a
support-free case cannot be adjudicated unless an operator adopts it. Every
challengeable event has an immutable version. Exactly one user case may ever
exist for the same `(scope, target, event_version)`: a later eligible filer
joins it, and no participant may refile after its terminal decision. An
operator report adopts that case while it is unresolved. After it closes, at
most one separately keyed operator-origin case may target that event version
while raw evidence remains. Any case opened before the event's user filing
deadline remains open and joinable until that deadline, regardless of who opened
it, and cannot publish a terminal decision earlier. An eligible filer joining an
operator-origin case consumes the same single user opportunity rather than
creating another case. No two cases for the same challenged event version may be
unresolved at once. A correction creates a new event version rather than
reopening either case. Identical retries are idempotent.

A confirmation recorded while its claim deadline is still open inherits that
deadline rather than resetting seven days. A receipt-backed claim that
auto-confirms after surviving the deadline, and a winner acknowledgement by the
only ordinary counterparty, record no second deadline. A later provider
confirmation with no open claim window is a materially new event version and
gets one user deadline.

Obligations remain visible but non-actionable during the initial result-dispute
window. If no result dispute is filed, they become actionable when that window
closes and D74 starts their 30-day due clock. A result dispute keeps every
obligation from that result non-actionable until both the original window has
closed and every timely case is resolved.

A later operator-opened result case makes every affected obligation
non-actionable and pauses its due, claim, default, and reliability clocks. If
the result remains unchanged, actionability is restored and all clocks resume
with the union of paused intervals added. If it is superseded, release and
replacement events own the new schedule. Likewise, a denied or withdrawn timely
result dispute makes its obligations actionable at the later of the original
window close or case resolution and due 30 days later.

Every challengeable obligation event that would add, replace, or remove a
reliability contribution remains provisional throughout its seven-day filing
window. It does not change the published score until the window closes
uncontested or its case resolves. During review, that obligation keeps its last
terminal contribution—or none—and the profile is marked `under_review`;
unrelated terminal contributions continue to recompute normally. A newly
recorded default therefore cannot lower a score, and a contested release cannot
inflate one, before the right to challenge it is usable.

Filing an obligation dispute also pauses that obligation's remaining due clock,
automatic confirmation, default, and other future transitions. A denied or
withdrawn dispute resumes each clock with the unioned elapsed pause added,
rather than consuming the user's window while the platform reviewed it.

A result dispute is parent to any open dispute on one of its obligations. The
obligation case may collect evidence, but cannot resolve until the result case
does, and its 14-day adjudication clock pauses during that parent case. If a
superseding result releases or replaces the obligation, the child case closes
as `superseded` without a reliability effect. Paused time is the union of open
intervals, not a sum per filing, so overlapping cases can never extend a
deadline twice.

Upholding a result dispute authorizes only a deterministic rerun from the frozen
evidence or an `inconclusive` superseding result with released obligations. An
adjudicator never types in a winner. A `review_timeout` result can be rerun to a
settlement-bearing result only if the D78 adjudicator first appends an explicit
D76 clearance for every still-gated quarantine; otherwise it remains
`inconclusive`. The clearance changes review state, not evidence.

Upholding an obligation dispute may confirm or reject a claim, or release an
obligation for a documented exception. If an erroneous release is successfully
challenged, the resolution appends a reinstatement or replacement obligation
that becomes actionable at case resolution when user-terminal, or after any user
window granted to an operator-origin correction closes and every timely case
resolves. It is due 30 days after that actionability instant; the resolution
never rewrites the release or creates a retroactive default. A rejected claim can
be replaced while time remains; if its adjusted due time has passed, the
obligation defaults. Every effect is a new result or obligation event, never an
edit.

A superseding result emits a durable decision notification. A result produced
by resolving a result case with a user filer is user-terminal and does not open
a second seven-day result window; appeals are not a launch feature. A
materially different superseding result produced by an operator-opened systemic
case with no user filer is a new event version and receives one user window,
even when an older version had a user case. That is review of the operator's new
action, not an appeal of the earlier decision. Replacement obligations wait
until the applicable window or case closes, then receive a fresh 30-day due
schedule.

The same per-event-version rule applies to obligation decisions. A confirmation,
claim rejection, release, reinstatement, default resolution, or timeout release
produced by a case with a user filer is user-terminal and records no new
`user_filing_deadline`. A materially different operator-origin correction with
no user filer is a new event version and receives one user window. A replacement
claim containing materially new, non-reused evidence is likewise a new claim
event and receives D74's ordinary challenge window; resubmitting the same
evidence is an idempotent retry, not an appeal.

If no adjudicator resolves a case within 14 days, `timed_out` ends it
fail-closed. A result becomes `inconclusive` and its obligations are released;
an obligation is released without positive or negative reliability credit.
This is an operator-severity event and notification, not approval of either
party's factual claim.

Filing, withdrawing, or losing a dispute has no reliability penalty. Only the
terminal uncontested or adjudicated obligation state contributes under D79,
which avoids discouraging a participant from reporting a real error.

**Why.** A winner is an interested party and can acknowledge evidence, but
cannot be the final authority when the evidence is contested. The same is true
of the contest creator. A separate, auditable operator is the smallest authority
that works for evidence fraud, engine defects, and genuine hardship without
giving either side a veto. Pausing consequences makes the right to dispute real;
a score that falls or a pledge that defaults during review is already a
punishment even if the filer later wins.

**Rejected.** Winner or creator adjudication (conflicted). Majority vote by the
contest roster (popularity decides a financial reputation fact). Mutable
`dispute_status` and corrected result rows (erase the audit trail). Disputes
that do not pause deadlines or reliability (the harm happens before the answer).
An adjudicator selecting a winner (replaces the agreed scoring engine with human
judgment). Unbounded adjudication (lets a filed case freeze consequences
forever). A separate case per filer (competing verdicts and double-counted
pause time).

**Revisit if.** Case volume justifies a second appeal tier. An appeal must still
append to the same history and preserve the no-manual-winner rule.

### D79. Reliability measures confirmed pledge behavior, not popularity or response speed

**What.** Launch reliability is obligation-only and versioned as
`pledge-reliability-v1`. For each obligation on which the profile is the debtor:

- confirmed on-time honor contributes `1`;
- confirmed late honor contributes `0.5`; and
- a current default contributes `0`.

Released obligations and obligations from void or inconclusive results do not
enter the denominator. A contribution becomes score-bearing only when D78's
filing window closes uncontested or its case reaches a terminal decision. Until
then, the obligation retains its prior score-bearing contribution, if any. An
existing default therefore remains `0` while a late claim is pending; if
confirmed late honor becomes terminal, the current contribution becomes `0.5`.
The append-only history still shows both events.

Every score-bearing obligation has equal base weight regardless of dollar
amount, then receives recency weight with a 365-day half-life from its adjusted
due time:

`elapsed_days = max(0, as_of - adjusted_due_at) in UTC seconds / 86,400`

`weight = 0.5 ^ (elapsed_days / 365)`

`score = round(100 * sum(weight * contribution) / sum(weight))`

`as_of` is one transaction-stable server timestamp captured for the complete
calculation, not a client clock or one clock read per row. The canonical server
evaluator uses fractional elapsed days, returns `calculated_at = as_of` with the
formula version, and is the only implementation; clients display its result
rather than recomputing it. Fixtures use a fixed `as_of`.

A history with fewer than three score-bearing obligations displays `Unrated`
plus that count instead of the numeric score, not a misleading perfect
percentage.
The calculation keeps full stored precision until the final expression, clamps
to 0–100, and rounds once to the nearest whole point with an exact half rounded
up. Wherever a profile is already visible, its score, rating state, and
score-bearing-obligation count are visible; the underlying history remains
limited to its parties and adjudicators.

The half-life compares outcomes by due-time recency; it is not calendar-time
forgiveness. Once every included due time is in the past, time passing alone
multiplies all weights by the same factor and cannot change the score. An older
outcome matters less only relative to a newer score-bearing outcome.

Declining an invitation, letting one lapse, missing a quarantine vote, filing a
dispute, and losing a contest do not affect this score. Those facts may support
a separately named responsiveness feature later, but mixing them into pledge
reliability would make a social refusal look like an unpaid donation.

**Why.** Confirmation semantics and reliability must describe the same event.
The formula rewards doing what was pledged, gives partial rather than full
credit for eventually curing a default, and makes older history less influential
relative to newer behavior without erasing it. Equal obligation weights prevent
a large stake from turning the score into a wealth measure. The three-obligation
display threshold makes a new or barely tested account visibly different from a
long reliable history without inventing a hidden prior.

**Rejected.** Self-attested claims in the numerator (self-awarded reputation).
Amount weighting (wealth dominates behavior). A lifetime unweighted ratio (one
old default brands a person forever). Starting every new account at 100 (looks
proven before any pledge). Invitation and review response in the same number
(conflates responsiveness with donation behavior).

**Revisit if.** Production data supports a calibrated half-life, minimum sample,
or late-honor credit. A change creates a new formula version and never changes
what an old persisted result meant.

### D80. M7 writes durable notification intents; M8 owns delivery

**What.** M7 owns a transactional, append-only notification outbox. A business
transition and its notification intent commit together, with a semantic
idempotency key per event, recipient, and reminder stage. M8 owns APNs tokens,
authorization, presentation, retries, and device delivery. Deadlines use server
timestamps and never depend on whether Apple reports a push as delivered.

M7 emits intents for:

- contest invitation, activation/cancellation, and final result;
- quarantine review requested, reminder, escalation, and resolution;
- timezone consent requested, reminder, and resolution;
- obligation created, actionable, due reminder, released or reinstated, and
  default;
- pledge claim submitted, challenge deadline, expiration, acknowledgement,
  dispute, and confirmation; and
- dispute filed, adjudication reminder, status changed, resolved, and timed out.

The outbox payload contains an event type and opaque entity identifiers, not
health totals, location, integrity allegations, receipt contents, or dispute
notes. The client fetches authorized detail after opening the app. In-app inbox
state can therefore share the same event ledger even when push is disabled.

**Why.** Invitation, review, consent, and pledge flows all require another human
to act. If each feature calls APNs directly, a transaction can commit while its
only prompt is lost, and retries can send duplicates. The outbox makes
action-required state queryable and delivery replaceable while preserving the
M7/M8 boundary. Generic push text also keeps sensitive activity and donation
facts off lock screens.

**Rejected.** Direct APNs calls inside settlement transactions (split-brain
failure and no device layer yet). Client-scheduled reminders (disappear on
reinstall and trust the phone clock). Push delivery as a deadline precondition
(an external best-effort system controls correctness). Sensitive values in the
payload (lock-screen disclosure).

**Revisit if.** A second channel such as email is added. It should consume the
same outbox rather than create another source of business events.

### D81. Account deletion pseudonymizes the actor; it does not erase an agreement

**What.** Authentication identity and durable contest identity become separate
lifetimes. One guarded, service-only deletion RPC locks the actor and its
transitionable workflows, creates the scoped capability secrets described below,
records only their hashes, performs every lifecycle/outbox/revocation change,
pseudonymizes the stable actor, and removes the auth principal in one database
transaction. All of it commits or none of it does; the successful response is
the one opportunity to return the capability plaintexts.

Pseudonymization records `deleted_at`, resets the profile timezone to `UTC`,
replaces the handle with a random opaque internal tombstone value that is not
derived from the UUID, replaces the display name with `Deleted member`, and
removes the avatar, push tokens, friendships, group memberships, and blocks.
Every authenticated policy rejects an actor with `deleted_at` even if an
already-issued JWT has not expired. Discovery and `find_profile_by_handle`
exclude deleted actors. The former normalized handle's plaintext is discarded,
but a server-keyed digest reserves it against later impersonation for as long as
the tombstone remains; registration compares digests without exposing the
reservation. The stable UUID is never reassigned to a new account.

This is deliberately called pseudonymization, not anonymity: someone who shared
a contest can still infer which former participant the tombstone represents,
while users outside that retained history cannot discover it.

Deletion first resolves pending participation in the same transaction. A
pending contest created by the departing actor is cancelled with the existing
`creator_cancelled` reason and its invitations lapse. In another creator's
pending contest, the departing actor's accepted row becomes `withdrawn`, while
an unanswered invitation becomes `lapsed`. Those lifecycle changes and their
D80 intents are written before auth removal inside the same transaction and
commit with it. No deleted actor can therefore cross the activation boundary
later; an actor whose contest is already active receives the retained access
described below.

Accepted roster rows, results, obligations, claims, dispute events, and immutable
review votes retain that pseudonymous actor UUID. An outstanding obligation is
not released merely because its debtor deleted their account; it follows the
same due and dispute rules, while remaining counterparts see only the tombstone
identity. Deleting during an active contest revokes further authenticated
evidence ingest but does not withdraw the accepted stake; the result and an
obligation may still follow. Deletion is not blocked by either state, and the
confirmation screen must explain both consequences before the account is
removed.

Deletion serializes with activation, finalization, and settlement event writes
so a workflow cannot cross one of those boundaries between the access check and
auth removal. Every active contest and every finalized contest lineage still
inside a result, obligation, or D78 operator-open window gets a high-entropy
contest-lineage capability covering its current and later results, obligations,
claims, and disputes. An existing standalone obligation or dispute not already
covered gets an equally scoped case capability. This includes a `void` or
`inconclusive` result still open to dispute and a winner who may later need to
acknowledge a claim.

Plaintext is returned once and only its hash is retained. The capability exposes
the durable event timestamps, the subject's own raw records while D81 still
retains them, and D77/D74-redacted result, rationale, obligation, claim,
receipt-preview, and case facts needed for that workflow. When the deleted actor
is the debtor, it may submit a D74 pledge claim, allocate eligible receipt value,
and append claim evidence. It may also submit an authorized result or obligation
dispute, join its shared case, append case evidence, withdraw its own case
support, and acknowledge or challenge a claim when D74 would have authorized
the actor. It cannot restore authentication, read a profile, enumerate records
outside its scope, ingest new contest evidence, or enter a new contest. It
expires only when no covered workflow is open and the persisted D78 operator
cutoff has closed, so a later systemic correction cannot create an unreachable
obligation. No push channel survives deletion, so the capability holder must
poll and server deadlines continue. Losing or declining this capability does
not block deletion, but the product warns that no later action will be possible
without it.

Sensitive raw material follows minimization rather than the tombstone forever.
Launch policy `raw-evidence-retention-v1` starts only after the relevant result
or obligation is user-terminal and all child challenge and dispute cases are
closed:

- exact coordinates and unredacted location samples are deleted after 30 days;
- raw hourly metric values, source-identifier history, per-contest App Attest
  public-key and counter observations, and opaque App Attest receipts are
  deleted after 90 days; and
- donation-receipt objects are deleted after 90 days.

At user-finality the server persists `operator_open_until` per contest or
obligation scope as the latest deletion deadline among the raw objects that can
support that scope. Paused clocks and scoped holds update that cutoff
transactionally. Case admission checks both the cutoff and the required
evidence; permanently retained aggregates never extend it. A lineage capability
uses the maximum cutoff across its covered scopes and remains valid while any
such cutoff or workflow is open.

An active device registration's current public key and counter are operational
state, not historical evidence, and remain until the device is revoked,
replaced, or its account is deleted. Historical pruning must never remove that
active state. Account deletion revokes each registration in the same transaction
without cascading its evidence. After revocation, per-contest material remains
until the last applicable contest clock expires. An open finalization,
challenge, or dispute pauses the relevant clock. A receipt allocated across
obligations starts its 90-day clock only after the latest allocation is
user-terminal and all of its cases are closed. A verified legal or provider
requirement may create a logged, scoped hold with an expiry; changing these
defaults requires a new policy version, not an unrecorded exception.

Before a live device row or raw observation can be removed, its current cascade
must be replaced. Historical ingest, quarantine, and check-in records retain
only the attested or adjudicated fact, assertion count, payload digest, and
non-reversible key fingerprint needed for audit. Deleting a registration must
never cascade through an ingest batch, metric snapshot, quarantine, check-in, or
result. The accepted roster, immutable result and aggregate totals,
configuration versions, receipt digest, adjudicated facts, and retention events
remain so contest and reliability history do not change.

The M7 migration must replace today's `auth.users → profiles →
contest_participants` cascade and the device-key evidence cascades with this
explicit pseudonymization path before any durable result can exist.

> **Working-tree implementation 2026-07-26:** the D81 foundation now replaces
> those cascades, adds durable actors, stale-JWT denial, atomic service-only
> deletion, scoped capabilities, retention rules/holds/events, and a guarded
> hourly pruner. It is not yet an integrated or deployed feature: full
> database/CI/concurrency/staging verification, user-facing capability handoff,
> and future result/obligation/dispute/receipt child scopes remain open.

**Why.** Keeping the current cascade would make account deletion the cheapest
way to erase a losing pledge and could change a finalized roster underneath its
result. Refusing deletion forever is not acceptable either. A pseudonymous
durable actor preserves the minimum relationship needed to explain history
without retaining a login or a discoverable social identity. Separating bulky,
sensitive evidence from the small adjudicated fact also avoids treating
append-only as a reason to retain every raw byte forever. A scoped case
capability preserves the ability to finish an existing pledge without quietly
keeping the deleted social account alive.

**Rejected.** Cascading deletion through contest history (rewrites agreements
and obligations). `ON DELETE RESTRICT` while any contest exists (effectively no
account deletion). Keeping the old handle and avatar on a disabled profile
(still personal and discoverable). Releasing every open pledge on deletion
(makes deletion an exit from a loss). Retaining exact coordinates and receipts
for the life of the tombstone (unnecessary sensitive data). Deleting a device
registration through today's cascades (erases the evidence and review history
the result needs). Keeping a full auth session solely for open cases (the
account was not actually deleted).

**Revisit if.** A verified legal or provider retention requirement demands a
different raw-evidence period. That changes the retention schedule, not the
pseudonymous result and obligation model.

### D82. Activation is a named one-minute database job

**What.** M7 installs `pg_cron` and one named job,
`gametime-activate-due-contests`, whose command is
`select app.activate_due_contests();` every minute. The job is created by and
runs as the migration owner. Application roles cannot use the `cron` schema;
`service_role` retains only D32's explicit worker call for guarded recovery and
tests.

One minute bounds ordinary activation lag without promising exact wall-clock
execution. Repeated or overlapping sweeps are safe: pg_cron serializes instances
of one job, the worker locks each due contest, status moves only forward, and
D80's semantic outbox key makes every recipient/event/stage intent idempotent.
The database transition and its intents remain one transaction. The migration
does not backfill old rows as if their historical transitions just happened.

**Why.** Activation is a database state transition with no external I/O. Keeping
its clock beside the guarded function removes an Edge Function, network hop,
credential, and split-brain failure from the trust path. A stable job name makes
the installed schedule inspectable and keeps future timed M7 workers in one
reviewed registry.

**Rejected.** Client-driven activation (a caller can open or cancel someone
else's contest early). An Edge Function timer for a database-only transition
(adds availability and credential failure modes). A once-daily sweep (an
unacceptable start-time delay). Treating push delivery as the clock (D80 makes
delivery explicitly best-effort).

**Revisit if.** Activation volume makes a one-minute full pending scan costly.
The partial `(starts_at) where status = 'pending'` index exists for this query;
measure it before moving to a queue or sharded workers.

## M8 — Product iOS app

### D83. The product app and the device-conformance harness are separate targets

**What.** `ios/GameTime` is the production-shaped SwiftUI app with its own app,
unit-test, and UI-test targets. `ios/GameTimeConformance` again contains only the
focused M6.5 App Attest harness. Both target iOS 18 and depend on
`GameTimeCore`, but the product app additionally pins `supabase-swift` and owns
authentication, product presentation, and live client adapters. D101 later
narrows the normal V1 shell to Personal accountability; dormant social paths
and adapters remain only for V2/regression compatibility.

Each product tab owns an independent typed `NavigationStack`. One observable
router owns the selected tab, the three normal Personal paths, retained dormant
social path types, and item-driven sheets. The root state is explicit
(`launching`, `signedOut`, `onboarding`, `signedIn`), and leaving `signedIn`
clears every route, sheet, and loaded user value.

Xcode 26.2 build 17C52 schedules `ExtractAppIntentsMetadata` for app and test
bundles even when they intentionally have no `AppIntents.framework` dependency.
Fresh unsigned Debug, Staging, and Release simulator builds and the product and
conformance test builds complete successfully while emitting exactly
`Metadata extraction skipped. No AppIntents.framework dependency found.` The
projects contain no App Intents import, declaration, extension target, linked
framework, package, or linker flag. This is an accepted toolchain self-skip, not
a missing product dependency or incomplete build.

**Why.** A staging product loop and a security-protocol harness have different
failure modes and release responsibilities. Keeping them independent prevents
sample product UI from obscuring conformance behavior, while typed per-tab
navigation makes sign-out cleanup and deep-link growth testable.

**Rejected.** Continuing to turn the conformance binary into product UI on
Simulator (one target silently means two products). One untyped navigation path
for all tabs (cross-tab state and reset behavior become implicit). Adding a
dummy App Intent or unused framework solely to silence metadata extraction, or
disabling the extraction task with a broad warning suppression.

**Revisit if.** Never for the target boundary. Navigation ownership may move to
feature modules when the route surface is large enough to justify modules.
Recheck the metadata boundary if App Intents become a real feature, a later
Xcode version changes the diagnostic, or extraction becomes build-failing.

### D84. Social reloads are bounded and contest creation is one idempotent transaction

**What.** `list_my_friendship_cards()` returns only the active caller's pending
and accepted relationships, the other actor's minimum profile card, direction,
and timestamps. It takes the same active-actor lock used to defeat stale JWTs
and removes blocked or tombstoned actors before disclosure.

`create_contest_with_invites_v1(...)` names one immutable payload with a
caller-generated request UUID. A private `(actor_id, request_id)` ledger stores
its SHA-256 payload hash and contest ID. An identical retry returns the original
contest; changed terms fail. Contest terms, the accepted author, initial
invitations, and the ledger record commit or roll back together. M8.1 sends one
invitee, while the RPC accepts a bounded array for later group contests.

**Why.** The app must reload its social state without reconstructing private
profile joins, and a lost mobile response must not create two pledges. The
transaction is the only place that can make contest and invitation atomic.

**Rejected.** Client-side joins across profiles and friendships (privacy rules
become query-shape dependent). Creating a contest and then sending invitations
in separate requests (orphan contests). Automatic retries of a mutation (the
user cannot tell whether a second commitment was attempted).

**Revisit if.** Group-contest product rules need terms not represented by the
current contest model. Keep the request UUID and atomic roster boundary.

### D85. Apple identity is exchanged natively and app configuration is public-only

**What.** The product app uses AuthenticationServices with a cryptographically
random nonce, hashes that nonce for Apple, and sends Apple's ID token plus the
raw nonce through Supabase's native token exchange. Apple's name is read only
on first authorization and held only long enough to prefill editable onboarding.

The app accepts only a Supabase HTTPS URL and `sb_publishable_…` key. Missing or
invalid values fail closed; `sb_secret_…` keys and legacy service-role JWTs are
rejected. Handles become read-only after onboarding, and the UI uses initials
rather than collecting avatar objects.

**Why.** Native exchange keeps the Apple credential path inside the supported
SDK flow without giving the client privileged backend authority. Minimizing
first-sign-in metadata and postponing mutable identity surfaces reduces
impersonation and retention risk.

**Rejected.** Embedding a service-role key (total RLS bypass). Persisting Apple
name as an authoritative profile value (Apple supplies it once and the user
controls their display identity). Shipping avatar upload before storage policy.

**Revisit if.** Server-enforced handle throttling and an avatar bucket with
reviewed object policies exist.

### D86. M8.1 is staging-mutable, release-locked, and refresh-driven

**What.** Staging persistently labels every screen
`Test environment—no real pledge` and permits the social/challenge loop. Release
compiles without fixture routing and cannot create or accept contests until the
evidence/App Attest slice closes. Account deletion, group feeds, sensor
permissions, finalization, settlement, and disputes are absent from live M8.1
routing; Debug fixtures may render later states for design and accessibility
work.

The app refreshes on launch, foregrounding, pull-to-refresh, and successful
mutations. It does not add Realtime, does not automatically retry mutations,
and treats cancellation as a normal outcome.

**Why.** The first product slice proves navigation and the live social contract
without implying that a pledge can yet be evidenced or settled. Explicit reload
points match D8's deliberate Realtime boundary and make force-quit recovery part
of acceptance.

**Rejected.** Hiding the staging nature in copy, enabling Release mutation
before evidence signing, or exposing nonfunctional settlement/privacy actions.
Realtime for convenience (another delivery contract before durable inbox/APNs).

**Revisit if.** App Attest/evidence collection passes its device/staging gate
and M7 exposes finalization/settlement contracts. Realtime still requires a
separate product and privacy decision.

### D87. Ambiguous challenge submissions persist per actor and retry only by explicit action

**What.** Before the product app sends a contest-creation RPC, it atomically
writes one versioned pending submission for the authenticated actor under
Application Support. The record uses complete file protection, backup
exclusion, and an actor-namespaced filename. It preserves every immutable term,
the caller-generated request UUID, attempt metadata, and canonical millisecond
timestamps as lossless `Date` bit patterns so relaunch cannot perturb the
timestamp values used by D84's backend payload hash. An existing record accepts
only identical terms and a monotonic next-attempt update; corruption or changed
terms fail closed.

An offline, cancelled, or otherwise ambiguous response retains the record.
Relaunch restores it only for the matching actor and requires the person to tap
Submit again. The app never automatically retries a contest mutation and blocks
a second request while a saved or unreadable record exists. A confirmed contest
UUID removes the record. The only other removal is a destructive, explicitly
warned discard that explains the lost idempotent-recovery risk. Sign-out clears
the in-memory view but not the protected actor-scoped record. Auth-generation
checks prevent work started for one actor from restoring, sending, or clearing
another actor's retry.

**Why.** D84 prevents duplicate contests only if the client can reproduce both
the request UUID and identical terms after a process death. SwiftUI `@State`
could preserve them while a sheet remained alive but not across force-quit.
Failing closed on unreadable storage is safer than silently generating a new UUID
after the server may already have committed the first request.

**Rejected.** `UserDefaults` for commitment terms (weak storage boundary),
reconstructing a request from a mutable draft (timestamp and payload drift),
automatic network retry (the user cannot tell that another commitment attempt
occurred), clearing on sign-out (silently destroys the safe retry), or allowing
parallel pending challenges before the product has a multi-action recovery
design.

**Revisit if.** M8 adds a general encrypted pending-action ledger or multiple
simultaneous contest drafts. Account deletion must explicitly purge this local
actor-scoped record after its server-side continuation decision is complete.

### D88. Cross-curve ECDSA certificate verification runs in portable TypeScript

**What.** The Supabase Edge Runtime implements `crypto.subtle.verify` for ECDSA
only as matched curve/hash pairs — P-256 with SHA-256 and P-384 with SHA-384 —
and throws `NotSupportedError` for the cross pairs. Apple's App Attest chain
requires one of them: the P-384 "Apple App Attestation CA 1" intermediate signs
the P-256 device leaf with SHA-256. `_shared/ecdsa_verify.ts` therefore carries
a pure-TypeScript ECDSA verifier (Jacobian point arithmetic for both curves,
DER signature and SPKI point parsing, and a public TBS/signature split of the
certificate DER). `verifyCertificateChain` in `appattest.ts` tries WebCrypto
first and falls back to the portable verifier only when the runtime raises
`NotSupportedError`; signature algorithm and hash come from the certificate
itself, never from caller input. The receipt path gets the same capability
through `pkijs_runtime.ts`, which installs a PKI.js `CryptoEngine` whose
`subtle` is wrapped so an unsupported verify delegates to the same fallback.
The fallback must reproduce the WebCrypto result bit-for-bit: the suite pins it
against Apple's official 2026 vector and against synthetic same-pair and
cross-pair combinations in both directions, including negative cases.

**Why.** Attestation verification cannot weaken to fit the runtime: skipping
the intermediate's signature or trusting an unverified chain would silently
accept forged attestations. The fallback runs only where the runtime proves it
cannot (a thrown `NotSupportedError`), so platforms with a complete WebCrypto
implementation keep using it, and the edge behavior matches the local Deno
behavior the suite already pins.

**Rejected.** Skipping the leaf-by-intermediate verification on the edge
(accepts forged chains), verifying attestations in Postgres or a separate
service (moves a security boundary for a runtime quirk), a WASM OpenSSL
dependency (deployment weight and audit surface far beyond two curves), or
waiting for the runtime to implement cross-pair verification (blocks M6.5's
device proof indefinitely on a vendor roadmap).

**Revisit if.** The Supabase Edge Runtime ships cross-pair ECDSA verification;
the fallback then becomes unreachable code that can be retired after the
deployed runtime is confirmed fixed. Also revisit if Apple's attestation chain
ever moves off ECDSA.

### D89. Challenge is the product term; a selected roster submits as one contest request

**What.** The product calls the person-created commitment a **challenge**.
Swift domain models, routes, clients, fixtures, screens, accessibility
identifiers, and current tests use that term. The stable database schema and RPC
contract continue to use **contest** because renaming persisted relations and a
versioned public function would add migration and compatibility risk without
changing the product behavior.

A creator explicitly selects 1–19 accepted friends. Review names every selected
friend and shows the closed roster size before submission. The client
canonically sorts those UUIDs, sets `max_participants` to the selected count
plus the creator, and makes exactly one
`public.create_contest_with_invites_v1` call with one request UUID. D84's
transaction therefore creates the contest, creator row, and every invitation
together or creates none of them; the client never loops over friends.

D87's protected pending envelope advances to version 2 and stores the complete
canonical invitee array. A version-1 single-invite saved-duel record is decoded
through an isolated legacy shape and atomically rewritten as version 2 while
preserving its actor, request UUID, invitee, attempt metadata, and exact
timestamp bit patterns. The Application Support directory name remains
unchanged so installed alpha builds can find their saved request. Unsupported,
malformed, duplicate, self-invite, empty, or over-capacity records fail closed.

**Why.** Challenge is clearer product language and applies equally to a friend
or a group of friends. One complete request preserves the backend's existing
atomicity and idempotency guarantees; request-per-friend submission would allow
partial rosters and make retry state ambiguous. Lossless in-place migration is
required because generating a new request UUID or reconstructing dates after an
ambiguous response can create a second contest.

**Rejected.** Renaming backend contest relations or publishing a cosmetic v2
RPC; sequential per-friend RPC calls; silently preselecting a friend; allowing
an open roster after submission; discarding version-1 pending data; or decoding
legacy and current envelopes through one permissive shape.

**Revisit if.** The product supports editable/open rosters, group-scoped
discovery, more than 20 participants, or a general encrypted pending-action
ledger. Each changes the immutable roster or persistence contract and needs a
new decision rather than an extension of this request.

### D90. Staging includes an isolated on-device demo; Release and Supabase do not

**What.** Debug and Staging builds may enter an explicit local demo mode from
the signed-out root or the You tab. Entry constructs a separate in-memory
`AppModel` with the same client protocols and fixture implementations used by
product tests. The live model remains retained but disconnected from the demo
view tree, so exiting returns to the same Apple-authenticated staging session.
A persistent banner says that demo changes stay on the device, and exiting
discards all demo relationships and challenges.

The interactive demo's accounts, challenges, payments, and uploads remain
fixtures, but its Personal step reader is the real on-device Apple Health
reader. That lets a “start right now” demo challenge count the holder's steps
since local midnight without sending them anywhere. Deterministic
`--fixture-mode` launches retain the synthetic step reader.

The demo directory includes memorable synthetic handles such as `david1` and
`david2`. A demo friendship request is accepted immediately and transparently
so one person can exercise exact-handle discovery, the Add action, accepted
friend selection, immutable challenge review, and local challenge creation
without controlling a second Apple identity. This shortcut exists only in the
interactive fixture scenario. Normal Debug fixtures retain pending-request
semantics, and live Staging continues to use the real RLS/RPC boundaries.
Release does not compile the fixture factory or expose demo entry.

**Why.** The immediate need is repeatable product-flow evaluation on one phone,
not proof of the two-user backend contract. Hosted login-capable dummy users
would either weaken D85's Apple-only identity rule or require a privileged Auth
admin path and credentials that must never be embedded in the app. A clearly
labeled local simulation provides faster design testing without polluting
staging data or diluting the separate M8.1 acceptance gate.

**Rejected.** Shipping shared dummy passwords; embedding a service-role key;
inserting non-login-capable `auth.users` rows and presenting them as accounts;
silently mixing fixture profiles with live Supabase rows; or treating instant
demo acceptance as evidence that two authenticated users can complete the
staging flow.

**Revisit if.** Testing requires cross-device notifications, RLS, relaunch
persistence, ambiguous network responses, or shared contest observation. Those
remain live two-user staging work and require real isolated identities rather
than expanding the local demo into a second authentication system.

---

## Resolved history and decisions still deferred

Recorded so they are not silently made later. Resolved items are retained as
history. Remaining entries state a working default when one exists. The audit
section retains the gaps it surfaced and points to the numbered decisions that
resolved them.

Five entries were resolved by M2 and now have their own decisions above: the
tie-break menu (D22's enum, declared at creation, defaulting to integrity
score — how each option is *computed* is M4's scoring), charity reference data
(D26), contest co-participants seeing each other's profiles (D33), the group size
cap (D28, resolved as a contest-level ceiling of 20), and whether a block ejects
either party from something shared (D29, resolved harder for contests than for
groups).

M3 resolved one more and sharpened a second. Provenance handling now has a
concrete shape (D38, D39: the client reports everything and the server decides
what counts), while D36 made any later timezone-change design preserve the zone
that governed every banked bucket.

M4 finished the tie-break menu M2 left half-open: each option now has a
computation (D51 for when a tie-break is reached at all, D54 for what happens
when the declared one cannot answer). It also made `integrity_score` a
load-bearing dependency. M5 now supplies a complete score map through the seam
M4 left, while genuinely equal integrity scores remain explicitly inconclusive.

M5 resolved the integrity-score configuration (D57–D58), explicit location
signals (D59), retroactive review (D60), source reputation (D61), and the
timezone-change consent path (D62). M6 supplied the concrete trusted-location
producer and geofence/workout signals (D63–D66); D67–D70 record hardening found
by the implementation-plan audit, and M6.5 adds the receipt and hosted-key
boundaries in D71–D73.

M7.1 resolved the settlement product contract before schema work: pledge
confirmation and deadlines (D74), explicit outcomes and obligation mappings for
contests that ran (D75), bounded quarantine review (D76), standings disclosure
(D77), disputes (D78), reliability (D79), notification ownership (D80), and
durable pseudonymization (D81).

M7.2 has implemented D80's durable outbox and D82's named one-minute activation
job. The reconciled branch also implements D81's pre-result durable-actor and
raw-retention foundation. M6.5 and hosted scheduler observations remain open and
still gate result finalization and settlement.

M8.1 and its first creation/durability follow-ups implement D83–D87 and D89: a
separate product target with typed navigation, a caller-bounded social-card API,
atomic caller-idempotent multi-friend challenge invitations, native Apple token
exchange, public-only configuration, staging disclosure, Release mutation lock,
refresh-driven live clients, and backward-compatible protected manual retry
recovery across relaunch. Its eligible-team, two-user Apple staging observation
remains open, and later M8 slices retain the sensor, App Attest, evidence queue,
inbox/APNs, and release responsibilities.

- **Quarantine and group approval (resolved by D60 and D76).** A duel needs its
  opponent; a group needs a strict majority of other accepted participants.
  Silence stays pending and the row remains admissible and visible. At the
  bounded deadline, M7 escalates rather than approving or silently removing
  evidence.
- **The ingest grace period (resolved by D76).** Six hours after `ends_at`, as
  `app.ingest_grace_period()` (D43). It is the one tunable number M3 put in SQL,
  because it gates whether a row may exist, and it trades a slow syncer's last
  day against the width of the window in which somebody who already knows they
  lost can still write into the hours they lost it in. M7's finaliser must read
  the same function rather than its own copy. Peer review may begin earlier, but
  its deadline is anchored no earlier than that boundary and never shortens or
  reopens ingest.
- **Third-party source reputation (resolved by D61).** `third_party` provenance
  stays admissible. A versioned reviewed allow-list is reputation-clean;
  unrecognized, missing, and malformed identifiers receive tunable, capped
  integrity penalties, and identical retries collapse to the same signal.
- **Retention on finalized contests (resolved by D81; foundation implemented).**
  The reconciled branch implements versioned rules, holds, cutoffs, immutable
  pruning events, and the raw metric/location/device worker. The append-only
  ledger remains intact while a result can change. After user-finality and
  closed cases, `raw-evidence-retention-v1` removes exact location after 30 days
  and raw metric/source plus device-attestation material after 90 days.
  Result, obligation, dispute, and donation-receipt scopes attach when those M7
  ledgers exist.
- **Reliability score formula (resolved by D79).** Equal-weight obligation
  outcomes decay with a 365-day half-life; timely honor, late honor, and default
  contribute 1, 0.5, and 0, with fewer than three results shown as `Unrated`.
- **Integrity score scale (resolved by D58).** Starts at 100, subtracts
  per-flag configured points with per-rule caps, and floors at 0. It never
  auto-disqualifies evidence.
- **Handle change throttling (later M8).** M8.1 makes handles read-only in the
  product UI after onboarding, but the server has no throttled rename contract.
  Swapping to a friend's handle shortly before settlement is a plausible
  impersonation play. Proposed: one change per 30 days, enforced by a
  `handle_changed_at` column, plus showing the change to anyone in an active
  contest with them.
- **Avatar storage bucket and its policies (later M8).**
  `profiles.avatar_path` holds an object path, but no bucket exists yet and
  nothing writes it. M8.1 renders initials. The bucket and its RLS arrive with
  the client that uploads to it.
- **Account deletion versus contest history (resolved by D81).** Authentication
  is deleted and social identity is pseudonymized, while a non-discoverable actor
  UUID preserves accepted rosters, results, obligations, and votes. Sensitive
  raw evidence is removed after its active retention purpose ends.
- **Timezone change mid-contest (resolved by D62).** The accepted zone remains
  the immutable base. A unanimously approved, server-timed event starts a
  prospective epoch; ingest and scoring preserve the earlier zone and drop only
  transition-cut hours and days.
- **Group contest visibility to the rest of the group (M8).** `contests` is
  readable by its participants only, so a group contest is invisible to group
  members who are not in it (D33). A group feed is plausibly wanted. It should be
  a narrowed view exposing the fact and not the terms — publishing who pledged
  what to whom to the whole group is a different product decision.
- **Invitation expiry and reminders (M8).** An invitation sits at `invited` until
  activation or cancellation lapses it. There is no reminder, and no expiry
  independent of the contest window, so an invitation to a contest starting in
  three months stays open for three months. Default: no expiry. A notification
  layer is the natural home for both.

### Surfaced by the 2026-07-25 plan audit

These gaps were recorded before M7 so its schema would not decide the product by
accident. M7.1 resolves the product gaps in D74–D82. The transactional outbox,
scheduled activation, and D81 pre-result foundation are now implemented at the
repository stages described above. The next backend slice is the
standings/finalization orchestrator and its bounded adjudication path. It may be
developed while M6.5 awaits external device proof, but no settlement-bearing
finalization bypasses that gate.

- **How a donation is confirmed (resolved by D74).** A claim needs provider
  confirmation, winner acknowledgement, or receipt evidence that survives a
  seven-day challenge. Self-attestation alone never awards reliability credit.
- **The terminal state for a contest that ran (resolved by D75).** `finalized`
  remains the lifecycle state. An append-only result distinguishes `winner`,
  `all_donate`, `void`, and `inconclusive`, and only the first two create
  obligations.
- **Whether review or the grace period bounds finalization (resolved by D76).**
  Peer review may begin when quarantine materializes, but grace always closes
  ingest before finalization and each peer deadline is at least 72 hours after
  grace, followed when needed by bounded independent adjudication.
- **What happens when a reviewer never votes (resolved by D76).** Silence never
  approves evidence. It escalates, and unanswered adjudication eventually
  finalizes to `inconclusive` with no obligations.
- **The scheduler (resolved by D82).** A named one-minute `pg_cron` job calls
  `app.activate_due_contests()` as the migration owner. Application roles cannot
  inspect or mutate the scheduler; `service_role` keeps a guarded recovery path.
  Staging still must prove an actual cron firing against committed rows because
  pgTAP transactions cannot be observed by the background worker.
- **Where notifications live (resolved by D80).** M7 transactionally records
  generic, idempotent notification intents. M8 owns APNs credentials, delivery,
  presentation, and retries; no deadline depends on push delivery.

---

## M8 staging continuation — product App Attest identity

### D91. Keep conformance primary; allow a bounded product identity only outside production

**What.** `APPLE_BUNDLE_ID` remains the reviewed primary App Attest identity,
`com.gametime.conformance`. Registration and metric assertion verification may
also try a strict, unique `APPLE_ADDITIONAL_BUNDLE_IDS` list with at most three
entries in local, test, or staging. Attestation receipt verification uses the
exact App ID that successfully verified that attestation. Check-in verification
remains primary-only, and production refuses the additional list.

**Why.** The conformance harness and staging product have distinct Apple App
IDs but share the same verifier deployment. A bounded staging-only list lets
both exercise the existing App Attest trust path without changing the
conformance identity, accepting a caller-supplied identity, or adding a bypass.
Binding the receipt to the successful identity prevents the verifier from
attesting one App ID and independently scoring the receipt as another.

**Rejected.** Replacing the global primary with the product bundle and breaking
conformance; accepting wildcards or request-provided App IDs; enabling
`ATTEST_DEV_BYPASS`; duplicating the whole service per target; extending the
product identity to check-in before Core Location is in scope; or allowing a
multi-ID production verifier without storing and reviewing an explicit device
identity binding.

**Revisit if.** Production needs more than one shipped App ID, the conformance
harness moves to its own backend, product check-ins enter scope, or the device
key record gains an immutable App ID column that can replace bounded
verification attempts with one stored identity.

### D92. Reconcile Apple step sources in HealthKit before writing one device contribution

**What.** For the M8 explicit Apple-device steps slice, this supersedes D50's
raw-sample proration; D50 remains the portable rule for provenance-separated
sample inputs. The product adapter uses raw `HKQuantitySample` rows only to
identify samples that independently classify as genuine Apple-device data and
to construct a bounded source-revision/device predicate. It then requests
`HKStatisticsCollectionQuery` cumulative sums for the exact completed
frozen-local-hour intervals supplied by `HourlyBucketer`. HealthKit's merged
statistic becomes one `device` observation per hour. The adapter does not
include manual, unknown, or third-party contributions in this first slice, and
the UI names the result as device-recorded steps rather than an all-source
Health total.

**Why.** iPhone and Apple Watch often record the same walk. Adding their raw
samples treats overlapping sources as disjoint and can double-count steps.
HealthKit statistics apply the person's source priority while merging
cumulative data. The existing evidence view correctly adds genuinely disjoint
provenance contributions, but it cannot represent both a reconciled all-device
total and overlapping per-device components without counting them twice.
Using one merged device row preserves the ledger's revision rule, keeps frozen
timezone and contest boundaries identical on both sides of the framework
adapter, and makes the displayed sync total match the exact signed request
bytes.

**Rejected.** Summing raw phone and watch samples; taking the largest raw
device total; labeling an all-source HealthKit total as first-party device
data; silently folding manual or third-party rows into `device`; inventing a
client-side source-priority algorithm; or uploading both the merged total and
its overlapping components.

**Revisit if.** The ledger gains a source-reconciled total plus a non-additive
provenance sidecar, third-party step sources enter the friend-test scope, Apple
changes statistics-query merge semantics, or physical acceptance shows the
scoped statistic does not match Health's Apple-device total.

### D93. Installed builds carry public client configuration and one provisioned identity

**What.** A versioned `PublicClient.xcconfig` supplies the hosted Supabase URL
and modern publishable key to Debug, Staging, and Release. Staging and Release
have no machine-local configuration include. Debug alone may optionally include
a gitignored local override. Until a separate production App ID and matching
Supabase Apple audience are provisioned, all product configurations use the
already verified `com.mjenkins.gametime.staging` App ID and Apple team. A target
build phase refuses malformed public configuration or a mismatched bundle ID.

**Why.** A Supabase publishable key is public mobile-client identification, not
a privileged credential; every installed binary necessarily reveals it.
Requiring each tester to create an untracked build file made a valid archive
depend on the machine that compiled it and caused clean installs to stop at a
configuration screen. A single provisioned bundle identity also keeps Apple's
ID-token audience equal to the client ID accepted by Supabase Auth.

**Rejected.** Runtime entry of backend settings; distributing xcconfig patches;
embedding an `sb_secret_…`, service-role key, Apple private key, or database
credential; silently using a developer's local override in an archive; or
shipping the unprovisioned production bundle ID and discovering the Apple
audience mismatch only after installation.

**Revisit if.** A production Supabase project and Apple App ID are provisioned.
At that point Release receives its own versioned public-client configuration
and bundle identity, while Debug/Staging remain isolated from production.

### D94. Detect lead loss at standings publication and keep push best effort

**What.** A new provisional standings snapshot detects when the prior rank-one
participant falls below first and writes one generic `contest_lead_lost`
notification intent keyed by that snapshot. APNs token and delivery state are
actor-bound and separate from the append-only intent. The alert contains no
metric totals or health data, opens the accepted participant's standings, and
offers an **I’m coming back 😤** action. That reaction is append-only and
idempotent per participant and latest provisional snapshot; it is accepted only
while the caller is below first.

**Why.** Standings publication is the first authoritative place that knows a
lead was actually lost. Detecting there avoids client polling and cross-device
duplicates. Keeping delivery state separate preserves D80's durable intent
ledger, while a generic payload limits lock-screen disclosure. Treating APNs as
presentation rather than correctness keeps scoring and deadlines independent
of permission, token, provider, or retry failures.

**Rejected.** Client-side rank comparison; embedding activity totals, health
values, or rival identity in the push; mutating or deleting notification
intents as delivery state changes; trusting contest/snapshot IDs from the
client without accepted-participant and latest-snapshot checks; and allowing a
reaction to affect scoring.

**Revisit if.** Reactions become visible to other participants, a durable
in-app inbox owns notification actions, multiple reaction types are introduced,
or a provider abstraction replaces direct APNs delivery.

## M9 — Personal accountability V1

### D95. A model discriminator preserves history and owns lifecycle dispatch

**What.** Every challenge has exactly one model:
`legacy_charity_contest`, `personal_accountability`, or the reserved
`social_accountability`. The migration backfills every existing row as
`legacy_charity_contest`. Existing social creation also writes that model.
`social_accountability` has no V1 creation route.

Activation quorum, accepted-participant requirements, ingest grace, assessment,
result publication, standings, winners, and obligations dispatch on the model.
A personal challenge activates with one accepted owner and can never create a
standing, winner, charity obligation, or participant payout. Legacy challenges
retain their 2–20 participant, six-hour ingest, winner/tie, charity, and
obligation behavior.

**Why.** Existing social rows are agreements and historical records. Inferring
"personal" from roster size, a null charity, or a missing invitation would
reinterpret data whose original meaning was different. One explicit value
makes compatibility testable and gives every shared service a safe dispatch
point.

**Rejected.** Treating all old one-person pending rows as personal; overloading
`max_participants = 1` as the only discriminator; renaming or rewriting legacy
results; and merging an old feature branch whose assumptions predate current
account-lifecycle and Daybreak work.

**Revisit if.** A genuinely new challenge model cannot share the base challenge
identity and evidence ledger. That model should receive a new discriminator or
separate aggregate through an explicit migration, never inference.

### D96. Personal terms freeze seven local days from the next midnight

**What.** Personal terms are keyed by challenge and owner and freeze cadence,
whole-step target, commitment amount in USD cents, `USD`, `test_only`, terms
version, IANA timezone, agreement time, and close time. The base challenge
mirrors the metric, cadence, target, commitment, and window for evidence-ledger
compatibility, but the personal terms are authoritative and equality is
enforced.

The trusted transaction timestamp determines the first local midnight strictly
after creation in the frozen timezone. The end is local midnight seven civil
dates later, converted through the same IANA zone. It is not calculated as
`start + 168 hours`; daylight-saving windows can differ from 168 elapsed hours,
including by non-whole-hour offsets in zones whose transitions are not 60
minutes.
Daily targets apply to each of the seven dates. Cumulative targets apply once to
their combined window. Targets are integers from 1 through 1,000,000 steps.

**Why.** The user is agreeing to named local days, not an elapsed-seconds
duration. Server calculation removes client-clock manipulation and ensures the
stored window and evidence attribution use one timezone database. A generous
upper bound prevents numeric abuse and obvious input mistakes without choosing
a recommended fitness level for the user.

**Rejected.** Fixed 24-hour multiplication; a live timezone; client-supplied
start/end instants; UTC calendar days; fractional steps; and allowing the
mirrored base terms to drift from the personal record.

**Revisit if.** Product research supports variable duration or travel-timezone
changes. Either changes the agreement and needs a versioned terms model rather
than an in-place edit.

### D97. One open slot and exact retries are database invariants

**What.** Personal creation is one transaction: require an active actor, verify
no active eligibility hold, hash the exact request terms, reserve the user's
single open slot, create the base challenge, create the accepted owner row,
freeze personal terms, and record the request UUID. An exact retry returns the
same challenge even if time has advanced. Reusing the UUID with changed terms
fails.

The open slot remains occupied while the challenge is scheduled, active, in its
24-hour grace period, or awaiting its first result. It closes only when a
pre-start cancellation commits or the first terminal personal result publishes.
Cancellation takes its own request UUID. An exact retry returns the already
cancelled challenge even after its former start instant; a new cancellation
request after the start is refused. A uniqueness constraint or equivalent
transactional enrollment record, not a client query, prevents concurrent open
challenges.

**Why.** Duplicate taps, network ambiguity, multiple devices, and scheduler
races are ordinary conditions. If correctness depends on a read-then-insert
client flow, two requests can both observe an empty slot. Keeping an unassessed
challenge open also prevents a user from starting another while the first could
still produce a hold.

**Rejected.** Client-only availability checks; deleting cancelled rows; changing
request dates on retry; releasing the slot at `ends_at`; and treating a repeated
cancellation as a new decision.

**Revisit if.** The product intentionally supports parallel free challenges.
That would replace, not weaken, the one-open invariant and would need explicit
resource and notification limits.

### D98. Stage A settlement is server-written `test_only`

**What.** The public personal creation function does not accept a settlement
mode. It writes `test_only` itself, and the database rejects any other value.
The only commitment amounts are 1,000, 2,000, 3,000, 4,000, or 5,000 USD cents.
The Stage A app displays **Test commitment — no money will be charged.** before
confirmation and on open-challenge surfaces. Local and Staging may mutate;
Release retains the existing mutation lock.

**Scope update (August 6, 2026).** This decision remains authoritative for
internal Stage A rows and fixtures. D114 supersedes only the distribution
Release boundary for the invite-only Stripe sandbox beta; it does not convert
Stage A history or permit live settlement.

No Stage A code creates a payment method, authorization, charge, transfer,
participant payout, charity obligation, collection retry, or debt. Legal,
processor, and App Store references are risk gates, not clearance.

**Why.** A client flag is not a safety boundary: a modified client can omit or
change it. Removing the choice from the request and constraining the stored
value makes the no-charge promise true at the authoritative write layer.

**Rejected.** A hidden `live_fee` option; a seven-day card authorization hold;
collecting card details "for later"; reusing the legacy charity stake as a
payment instruction; and enabling Release creation before Stage A acceptance.

**Revisit if.** Every Stage B legal, processor, App Store, HealthKit, age, and
jurisdiction gate is satisfied in writing. Live fees require a new terms version
and migration; they are not an enum value to turn on.

### D99. Coverage is decided before success, and holds distinguish fault domains

**What.** Personal sync appends two kinds of trusted facts: admissible metric
observations and the completed local-hour intervals the signed HealthKit query
covered. Coverage may exist without a positive step row, so a real zero-step
period is not mistaken for missing evidence. Across the seven local dates, the
expected set is every calendar-derived interval wholly contained in
`[starts_at, ends_at)`. It is generated from the frozen IANA timezone using the
same authoritative bucketing rule as collection. No fixed bucket count is an
invariant because offset changes can be non-hour transitions. The expected set
must also be non-overlapping in absolute time before success or miss is judged.
If the platform calendar returns overlapping intervals for a transition, V1
records `inconclusive / gametime_outage` and creates no eligibility hold. It
must not double-count the overlap or blame the user while a non-overlapping
personal collection rule is still unproved.

One query may persist metric observations and coverage as separate append-only
facts, but delivery is ordered: all positive metric batches from that query
must receive durable acceptance before its coverage batch is eligible to send.
An ambiguous, queued, or refused metric upload keeps the matching coverage
queued. This prevents a partial network delivery from certifying an hour whose
positive observations never reached the ledger.

After `ends_at + 24 hours`, the service first decides completeness. Exact
coverage plus resolved, non-conflicting trusted evidence may be scored. A daily
goal is met only at 7/7; a cumulative goal is met at or above its target.
Outcomes and reason codes are:

- `met_goal` / `target_reached`;
- `missed_goal` / `target_missed`; or
- `inconclusive` / `missing_coverage`, `quarantined_evidence`,
  `conflicting_evidence`, `unresolved_evidence`,
  `user_device_sync_failure`, or `gametime_outage`.

Every inconclusive result waives the test commitment. A confirmed GameTime
outage does not create a hold. An unresolved user/device sync failure creates an
append-only eligibility hold. Only a successful App Attest-backed HealthKit
diagnostic performed strictly after that hold began can append its clearance.

**Why.** Comparing a target before proving what data was observed turns missing
data into a false miss and can also turn selective uploads into a false success.
Separating platform outages from device/user failures avoids punishing someone
for GameTime while still preventing repeated challenges on an unresolved sync
path.

**Rejected.** Treating absent step rows as zero; peer voting; letting a client
declare completeness or outage; silently dropping quarantined evidence; a
diagnostic timestamp equal to or before its hold; and leaving an inconclusive
challenge open forever.

**Revisit if.** HealthKit or Apple provides a stronger read-completeness signal.
It may strengthen the trusted coverage record but cannot retroactively weaken
the fail-closed rule for stored terms.

### D100. Personal records are owner-readable and service-writable

**What.** The owner may read only their own personal terms, progress, coverage
summary, diagnostic state, results, and eligibility hold through explicit
grants, RLS, and caller-bounded RPCs. Clients cannot insert, update, or delete
those tables directly. Creation and cancellation are the only authenticated
personal mutations.

App Attest-backed diagnostic and activity recorders, assessment input, evidence
classification, result publication, and hold clearance are service-only.
Privileged functions use a blank search path, active-actor checks where a user
is involved, narrow execute grants, and immutable or append-only tables.

**Why.** Health activity and device state are private even when there is no
opponent. RLS answers which rows a reachable object may expose; explicit grants
answer whether the Data API role may reach the object at all. Both are required.

**Rejected.** `TO authenticated` without ownership; user-authored result or hold
rows; exposing a service key to iOS; relying on an RPC while leaving direct table
verbs granted; and placing an unguarded `SECURITY DEFINER` function in the
exposed schema.

**Revisit if.** A support workflow needs bounded operator reads. It must use a
separate audited capability and must not broaden owner or service-role policies.

### D101. V1 has three personal tabs and an isolated pending envelope

**What.** The normal shell contains Today, Challenges, and You, each with its
own navigation stack. Friends, invitation acceptance, roster, standings,
winner, charity, reaction, and tie-break routes are absent. Today and Challenges
use dedicated personal list/detail/progress models. You keeps public-handle
profile behavior and adds Health access, latest diagnostic, privacy, and hold
state. Only steps is offered.

Personal creation uses a new protected store and versioned envelope containing
only the personal request UUID, cadence, whole-step target, commitment preset,
timezone, owner, and exact retry metadata. The existing social v1/v2 directory,
types, and bytes remain untouched for dormant compatibility. A personal decoder
categorically refuses them. Personal fixtures and previews are the default;
legacy fixtures are explicitly V2/regression-only.

**Why.** Forcing an empty invitee list through social types keeps forbidden
concepts alive in validation, retries, copy, and routes. A separate envelope
prevents an ambiguous response saved by an older app from being reissued under
new meaning.

**Rejected.** Hiding the Friends tab while retaining deep links to standings;
decoding social and personal records through a permissive union; overwriting the
old pending directory; presenting unsupported metrics; and redesigning away
from the approved Daybreak system.

**Revisit if.** V2 returns social accountability. It gets its own model and
routes and may read the dormant social envelope only through an explicit
migration; it does not widen the personal decoder.

### D102. Direct legacy participant reads are self-only

**What.** Authenticated direct SELECT on `contest_participants` returns only the
active caller's row. A versioned, caller-bounded legacy summary RPC returns
immutable challenge terms, caller state, aggregate roster counts, socially
visible author minimum profile before acceptance, and accepted minimum profiles
after acceptance. It omits pending identities, participant timezones,
participant charities, evidence, integrity state, and other private fields.

This is a selective reimplementation of the reviewed behavior at `6cfae0b` on
current `main`; none of that branch's stale UI or documentation is merged.

**Why.** Hiding social UI does not revoke Data API access. An unanswered invite
must not be enough to enumerate a pending roster or health-adjacent participant
state. Keeping the bounded summary preserves dormant legacy readability without
reopening the broad table policy.

**Rejected.** Leaving broad direct reads because V1 has no Friends tab; merging
the old branch wholesale; returning pending invitee handles; and widening
profile visibility to make a summary convenient.

**Revisit if.** V2 needs a different roster disclosure. Publish a new versioned
RPC with explicit acceptance/privacy rules rather than widening direct table
access.

### D103. Hold causes are durable and clearance is a one-time state transition

**What.** A user/device sync failure inserts one eligibility-hold row with its
cause, challenge, result, and placement time. Those facts never change. A
successful trusted diagnostic whose Health query began strictly after the hold
may set `cleared_at` and `cleared_by_diagnostic_id` exactly once. Deletion,
cause changes, reopening, client-authored clearance, and clearance by an old or
overlapping query are forbidden.

This clarifies D99's use of "append-only eligibility hold": hold creation is
append-only, while the two explicit clearance fields form a guarded one-way
transition rather than a separate clearance table.

**Why.** Eligibility is queried frequently by creation and profile surfaces. A
single guarded row makes active-hold enforcement atomic while preserving the
failure and recovery audit trail through the diagnostic foreign key. A second
table would add join and uniqueness races without preserving more evidence for
Stage A.

**Rejected.** Deleting a cleared hold; overwriting its reason or source result;
letting a diagnostic that began before placement clear it; treating a client
timestamp alone as proof; or permitting a cleared hold to become active again.

**Revisit if.** Policy requires multiple clearance reviews, operator approval,
or a complete event-sourced eligibility timeline. Add an append-only clearance
event then, with an active-state projection that preserves these one-way rules.

### D104. Background step delivery is Staging-only and reuses the durable sync path

**What.** The Staging app installs one long-lived step-count HealthKit observer
during application launch and requests hourly background delivery. Debug,
fixture, and Release configurations do not start it. Background enablement is
idempotently retried after the user completes Health authorization, without
installing a second observer.

If HealthKit wakes the app before SwiftUI has attached the personal store, the
coordinator retains one pending completion and coalesces later wakes because the
eventual sync requeries the entire eligible frozen challenge window. Once the
handler exists, it drains the same durable exact-byte metric and coverage queues
used by manual sync, then calls HealthKit's completion handler. An observer
error completes without asserting coverage.

**Why.** A separate background uploader would create a second ordering and
retry protocol exactly where evidence completeness must stay deterministic.
Installing at launch preserves the platform wake contract, while retrying
enablement after authorization closes the first-launch race. Full-window
requery makes wake coalescing safe without treating wake count as evidence.

**Rejected.** Enabling background delivery in Release; treating registration
success as proof a wake occurred; installing another observer after every
diagnostic; certifying coverage before pending metric bytes are accepted; or
calling the HealthKit completion handler before durable sync processing ends.

**Revisit if.** A signed physical Staging run shows the platform suspends this
bounded handler or fails to redeliver after an interrupted wake. Simulator tests
prove only gating and callback ordering, never real background delivery.

## M10 — Owner-only Solo contract domain

### D105. Solo is a new aggregate, not a reinterpretation of Personal or Social

**What.** Step 2A introduces `solo_contracts`, `solo_evaluations`, and
`solo_appeals` after the Personal V1 migrations. A Solo row owns its contract
policy, preliminary-failure, appeal, and logical-settlement lifecycle. It does
not reuse `personal_challenge_results`, change a `contest` discriminator, or
rename/drop/disable any historical Social relation. The Solo creation switch is
seeded off, so the current Personal app and the dormant aggregate cannot both
create through a normal client path.

**Why.** Personal V1 publishes one terminal test result and deliberately has no
appeal child workflow. Adding a preliminary result and appeal state to those
tables would change the meaning of already-reviewed records. Historical Social
agreements are an even stronger boundary: they include participants, charity,
standings, and obligations that Solo must never infer or overwrite.

**Rejected.** Renaming `personal_*` tables; treating a one-person contest as a
Solo contract; adding appeal columns to the Personal result; dropping dormant
Social RPCs; and hiding a cross-domain conflict behind client routing.

**Revisit if.** A later migration deliberately unifies the Personal evidence
aggregate with Solo contracts. It must define a one-way mapping, cross-domain
open-slot ownership, and historical read compatibility before enabling both
creation paths.

### D106. A contract locks an immutable policy digest and local civil-day window

**What.** The private Solo policy registry is append-only. Creation requires the
caller's expected version to equal the runtime's active version, then copies
both the version and its SHA-256 policy digest into the contract. The first
policy is `solo-test-v1`: steps only, daily or cumulative cadence, a whole-step
target, integer USD cents from 1,000 through 5,000, `test_only` settlement, one
through seven local civil days, a 24-hour evidence grace, and a seven-day appeal
window. Frozen IANA timezone plus local start date derives the absolute start,
end, and evidence cutoff; duration is not calculated as `N * 24 hours`.

Owner, policy, goal, amount, currency, settlement mode, timezone, window,
lock time, and creation time are immutable. Evaluation and appeal rows copy the
same owner and policy version through composite foreign keys.

**Why.** A policy name without immutable content can be silently redefined, and
an evaluation under a different version is not a decision on the agreement the
owner accepted. Local civil dates preserve the product's existing DST rule.
Hard database bounds remain defense in depth even though the policy also stores
them.

**Rejected.** A client-selected live settlement mode; mutable policy rows;
unbounded cents or duration; UTC-only/fixed-hour windows; updating a locked term
in place; and letting an evaluator choose another policy version.

**Revisit if.** A new reviewed policy changes any bound, grace, appeal window,
or settlement behavior. Add a new immutable policy row and require explicit
client acknowledgement; do not edit `solo-test-v1`.

### D107. One unsettled slot spans failure and appeal, while facts only append

**What.** A partial unique index permits one `solo_contracts` row with
`closed_at is null` per owner. That slot remains occupied through scheduled,
active, evidence grace, preliminary failure, appeal, and settlement readiness.
Only pre-start cancellation or terminal logical settlement closes it.

The projection moves forward through `scheduled`, `active`,
`awaiting_evaluation`, and either settlement readiness or
`preliminary_failure`. A preliminary failure may receive exactly one timely
`filed` appeal event, moving it to `appeal_pending`; a service decision is a
second insert-only event and moves it to settlement readiness. Failure without
an appeal can settle only at or after its locked deadline. Evaluation rows and
appeal events reject UPDATE, DELETE, and TRUNCATE.

**Why.** Releasing the slot at `ends_at` would permit a new commitment while the
first still has a live consequence. Updating an appeal row from pending to
decided would erase the distinction between what the owner filed and what the
service later decided. Contract-row locking plus unique partial indexes make
appeal-versus-settlement races choose one valid serialized outcome.

**Rejected.** Multiple open Solo contracts; deleting cancellation history;
overwriting preliminary evaluation; adding a second ordinary appeal; settling
before the filing deadline; reversing terminal state; and representing a
decision as mutable columns on the filing.

**Revisit if.** Policy approves parallel commitments or an independent second
appeal tier. Either changes the slot and deadline model and requires a new
policy version plus new lifecycle states.

### D108. Database rollout gates and exact-request RPCs are the write boundary

**What.** The database, not an iOS build flag or JWT metadata, owns two mutable
creation gates: a singleton runtime switch/active-policy pointer and a positive
beta-eligibility row. Both are private and service-writable only through
versioned RPCs. The switch is off and the allowlist empty after migration.

Every owner or service mutation is a narrowly granted versioned RPC and records
an operation-scoped request UUID, canonical payload hash, and result. Exact
committed retries return that result before mutable gates or elapsed deadlines
are rechecked; changing a payload under the same request UUID fails. The sole
integration exception is account deletion: a versioned trigger function is
guarded by D81's serialized transaction marker and inherits D81's audit trail,
instead of manufacturing another request UUID for the historical deletion RPC.
Authenticated roles receive direct `SELECT` only on the three public tables,
with active-owner RLS. `anon` and direct `service_role` table writes receive no
grant.

**Why.** A client-side switch can be removed by a modified build and
`user_metadata` is user-editable. Network ambiguity is ordinary around creation,
cancellation, evaluation, appeal, and settlement; a retry must recover an
already-committed decision without turning into a new policy decision.

**Rejected.** Authorization from JWT `user_metadata`; public config tables;
direct service inserts; unversioned write RPCs; rechecking beta eligibility on
an exact creation retry; and using a client read-then-insert query for the open
slot.

**Revisit if.** Hosted rollout needs cohorts, percentage allocation, or expiry.
Add a server-authored eligibility policy and preserve the same exact-retry and
active-policy acknowledgement contract.

### D109. Account deletion closes only an unstarted Solo agreement

**What.** A forward profile-tombstone trigger extends the existing atomic
`delete_account` transaction without rewriting its historical migration. Every
Solo RPC follows owner-profile then contract lock order. When deletion owns that
profile lock, the trigger cancels a scheduled contract only if the trusted
server time is strictly before `starts_at`, marks beta eligibility false, and
retains every post-start contract, evaluation, and appeal row. Service lifecycle
RPCs may finish retained facts for a tombstoned owner; a stale owner JWT reads
nothing and cannot file an appeal.

**Why.** Deletion must not become a way to escape an agreement after it begins,
but an unstarted test agreement can be cancelled safely. Retention preserves the
audit trail while the durable profile UUID is already pseudonymized by D81.
Using the same lock order prevents deletion/create and deletion/appeal races
from leaving an orphan or half-transition.

**Rejected.** Cascading Solo history from `auth.users`; cancelling an active or
appealed contract; blocking deletion on any Solo history; replacing the large
D81 function; and allowing stale bearer identity to keep owner access.

**Revisit if.** Real-money policy is approved. Before a paid policy can launch,
deleted-owner review rights, capability handoff, notices, refunds, and legal
retention need an explicit design rather than inheriting this test-only rule.

### D110. Step 2A has logical dispositions and no authorization interface

**What.** `released`, `forfeited`, and `waived` are test-only logical settlement
dispositions. Step 2A stores no payment method, processor customer, mandate,
authorization, hold, capture, charge, transfer, payout, retry, or provider
identifier. No nullable provider-shaped column is reserved in advance.

**Why.** The contract lifecycle can be reviewed and race-tested without moving
money. Inventing an authorization shape before even a fake adapter exists would
silently choose processor semantics and make a dormant schema look closer to
paid launch than it is.

**Rejected.** A Stripe-shaped foreign key; a seven-day authorization hold;
collecting a card for future use; treating `forfeited` as a charge instruction;
and enabling Solo creation merely because the logical domain passes locally.

**Revisit if.** The next reviewed slice adds a fake adapter. It should introduce
the minimum private processor-neutral authorization aggregate in a forward
migration, keep real providers absent, and leave hosted/real-money gates closed.

### D111. Step 2B makes fake authorization atomic, private, and append-only

**What.** Step 2B takes D110's explicit revisit path through one forward
migration. `app.solo_authorizations` stores one immutable
`processor_neutral_fake` / `local-fake-v1` fact for a v2-created contract.
A composite foreign key binds the authorization to the exact contract, owner,
policy version and SHA-256 digest, commitment amount, `USD` currency, and
`test_only` settlement mode. `app.solo_authorization_events` repeats that
binding and permits exactly two append-only positions: an initial `authorized`
event and at most one terminal `cancelled`, `released`, `forfeited`, or `waived`
event. Both private tables enable RLS and grant no direct privilege to
`public`, `anon`, `authenticated`, or `service_role`.

`create_solo_contract_with_fake_authorization_v2` is the new authenticated
owner boundary. It reuses the complete v1 profile, active-policy, beta,
runtime-switch, terms, and one-open-slot checks, but atomically commits the
contract, one authorization, its initial event, and the canonical exact-request
result. `create_solo_contract_v1` keeps its reviewed contract-only semantics.
A request UUID already committed through v1 cannot be upgraded into a linked v2
authorization. Exact v2 retries return the committed result before mutable gates
are rechecked, while changed terms under that UUID fail.

The pure private adapter reads only typed frozen facts and supports four
deterministic local scenarios. `authorize` creates the complete linked
aggregate. `refuse` and `retryable` commit their exact outcomes without leaving
a contract or authorization. `injected_failure` raises after candidate contract
creation so the contract, v1 request record, authorization, event, and v2 result
all roll back. The public v2 RPC selects only `authorize`; callers cannot choose
a test failure mode.

Contract finality owns fake resolution. A pre-start owner cancellation appends
`cancelled` in the same `cancel_solo_contract_v1` transaction. D109 account
deletion appends the same event, sourced to `delete_account`, in the existing
serialized deletion transaction. A terminal `settle_solo_contract_v1` call
appends exactly the contract's logical `released`, `forfeited`, or `waived`
disposition. Evaluation, preliminary failure, appeal filing, and appeal decision
do not resolve the authorization; it remains open until cancellation or logical
settlement. Contract and authorization locks plus the unique second-event slot
make concurrent or repeated resolution choose one committed outcome. A
contract-only v1 row has no authorization and continues through the original
lifecycle unchanged.

The adapter accepts and stores no credential, provider secret or identifier,
payment instrument, card data, customer ID, mandate, webhook body, arbitrary
payload, or other raw sensitive value. It logs nothing, calls no external API,
and cannot capture, charge, transfer, or pay out. The Solo creation switch
remains off and the beta allowlist remains empty.

**Why.** A second RPC version makes the new atomic contract explicit instead of
silently changing v1. Relationally copying every frozen term prevents a
different owner, policy, amount, currency, or settlement mode from being linked
later. An append-only initial fact plus one terminal event is enough to exercise
authorization, cancellation, settlement, appeal, deletion, idempotency, and
race behavior without importing processor concepts or pretending that money
moved. Rolling non-authorized candidates back prevents half-linked contracts,
while committed refusal/retry results remain exactly recoverable.

**Rejected.** Mutating `create_solo_contract_v1`; linking authorization after
contract commit; a nullable provider-shaped column; a client-selected fake
scenario; storing request bodies or instruments; updating an authorization
status in place; resolving on preliminary failure or appeal; a second
resolution event; treating `forfeited` as a capture or charge; enabling the
runtime switch; seeding beta users; and adding an iOS route, public Edge
endpoint, scheduler, Personal-to-Solo mapping, cross-domain slot rule, hosted
configuration, provider SDK, credential, webhook, or external call.

**Revisit if.** A reviewed client or worker needs this boundary, or every Stage
B legal, processor, App Review, HealthKit, age, and jurisdiction gate is
satisfied in writing. Either requires a new reviewed slice; the fake adapter is
not a provider abstraction to toggle live. Local fake-adapter tests do not prove
a real processor, money movement, legal or App Review approval, hosted
scheduling, physical-device behavior, or hosted multi-user isolation.

### D112. App Attest extensions are optional after a strict COSE key

**What.** Attestation authenticator data accepts three reviewed shapes after the
credential id: the existing suffix-free compatibility form, one deterministic
EC2/ES256/P-256 COSE key, or that same COSE key followed by Apple's exact
validation-category and bundle-version extensions map. Any non-empty suffix
must begin with the complete COSE key. A second value, when present, must be the
complete extensions map; malformed or additional values are refused.

The COSE key remains bound to the leaf-certificate public key and the key id
remains `SHA256(public_key)`. A deployment that configures a category or bundle
allowlist still fails closed when the attestation omits that signal.

**Why.** A physical Staging iPhone supplied one well-formed CBOR value after the
credential id. D46's requirement that every non-empty suffix contain both the
COSE key and extensions map rejected it before the server could perform the
existing certificate, nonce, key-id, receipt, or database checks. WebAuthn
defines the credential public key as attested credential data and extension
output separately. Apple's published 2026 vector proves the two-value shape,
but does not prove that every physical attestation includes those extensions.

This decision supersedes only D46's OS-version inference and mandatory-extension
claim. D46's pinned root, strict deterministic CBOR, certificate chain, nonce,
COSE/certificate binding, key-id binding, receipt verification, and fail-closed
deployment policy remain unchanged.

**Rejected.** Making extensions mandatory whenever a COSE key is present;
ignoring malformed extensions; accepting an incomplete or non-P-256 COSE key;
inferring extension presence from an OS version; adding an ED-bit gate that
would reject the pinned Apple vector; and removing the suffix-free compatibility
path as part of this incident fix.

**Remaining gate.** Local tests prove the parser and handler paths only. After
an explicitly approved `attest-device` deployment, the trusted diagnostic must
be rerun on the physical iPhone. A later certificate, nonce, receipt, or
database refusal would be a separate observed failure, not proof that this
parser correction was sufficient.

## M11 — Stripe sandbox payment foundation

### D113. Stage B saves a payment method and charges only a confirmed miss

**What.** Stage B begins in Stripe test mode through a new forward terms version.
During challenge creation, after Health access succeeds and before final
confirmation, GameTime creates a Stripe `SetupIntent`. It saves an approved
payment method for later off-session use and binds the provider identifiers,
frozen amount, terms version, and explicit consent to the exact creation request.
GameTime stores no card data. Starting a challenge creates no authorization hold,
`PaymentIntent`, or charge.

The seven-day challenge keeps its 24-hour final-sync period. No payment decision
occurs before the evidence cutoff. `met_goal`, `inconclusive`, and pre-start
cancellation resolve with $0 charged. Missing, conflicting, or unresolved step
data remains fail-closed and cannot become a miss.

A complete `missed_goal` is provisional when published. Its immutable
`review_deadline` is exactly `published_at + interval '7 days'`; this replaces
the ambiguous “day 14” wording. No charge may occur before that deadline or
while a timely review remains unresolved. No review by the deadline, or a
completed review that confirms the miss, makes the frozen amount chargeable. A
review that overturns the miss, or remains unresolved at the deadline, waives
the amount.

One confirmed miss permits exactly one idempotent off-session Stripe
`PaymentIntent` for the frozen amount. If that attempt fails or requires
customer action, GameTime does not retry automatically. The owner must take an
explicit payment-recovery action. The unresolved payment blocks another paid
challenge until it succeeds or policy waives it; GameTime does not run repeated
retries or debt collection.

Stripe sandbox objects use test credentials and move no real money. Sandbox UI
must identify payment test mode and plainly state that no real money moves.
Live Stripe mode remains disabled. D114 permits only the invite-only Release
beta to reach this sandbox path; hosted configuration or any real charge still
requires separate approval and evidence.

**Why.** An ordinary card authorization may expire before seven challenge days,
the 24-hour sync period, and the review gate finish. Charging at creation would
turn the product into a refundable deposit and would charge people who meet
their goal or receive an inconclusive result. A `SetupIntent` records the
payment method and mandate without charging. A later `PaymentIntent` makes the
single confirmed consequence explicit and independently retry-safe.

The absolute `review_deadline` makes the rule auditable across time zones and
prevents “day 14” from meaning either a calendar date or elapsed time from an
unspecified event. Pausing payment until review closes keeps a provisional
result from producing a financial consequence.

**Rejected.** A seven-day authorization hold; charging or capturing at challenge
creation; creating a `PaymentIntent` for `met_goal`, `inconclusive`, or
pre-start cancellation; treating missing data as a miss; charging while review
is open; client-authored payment status; multiple off-session attempts;
automatic retries; debt collection; raw card storage; rewriting Stage A or Solo
history; enabling Release from a client flag; and calling test-mode payment
objects live-payment proof.

**Remaining gate.** D113 is implemented locally in a sandbox-only client and
server path. Stage A and Solo remain `test_only`, and no hosted environment was
changed. The Release source selects the sandbox contract but is not yet a
candidate: D115 adds the local default-off tester allowlist and kill switch, but
that migration remains unhosted and disabled. The candidate still needs the
final Apple identity and redirect scheme, test secrets, a registered signed
webhook, an approved hosted dispatcher, and end-to-end reconciliation proof.
Live rollout additionally requires written Stripe approval, US legal review,
App Store and HealthKit clearance, age and jurisdiction controls, and a
separately approved production rollout.

### D114. The invite-only Release beta may use Stripe sandbox only

**What.** The distribution Release build may create Personal challenges only
when its frozen settlement mode is `stripe_sandbox`. Release requires
production App Attest, keeps legacy social mutations disabled, and must accept
only Stripe test-mode objects. Internal Stage A remains `test_only`; no existing
row is rewritten.

The Watch connection foundation may remain in source for Debug and Staging, but
its coordinator and shared handshake code are excluded from the Release iPhone
target. A Watch companion is not embedded in or accepted as part of this beta.

**Why.** The external cohort needs to rehearse the complete setup, review, and
settlement experience without creating a live financial consequence. Keeping
the sandbox path explicit and fail-closed makes that rehearsal independently
auditable while preserving the older no-provider Stage A contract.

**Rejected.** Enabling live Stripe; allowing Release to fall back silently to
`test_only`; reusing the staging redirect or bundle identity as final
distribution identity; exposing legacy social or Solo creation; embedding the
Watch prototype in the iPhone beta; and treating local configuration as hosted
or TestFlight proof.

**Remaining gate.** Name and register the final distribution App ID and Stripe
return scheme, add the iPhone icon and privacy manifest, pass the source
preflight, deploy the exact reviewed non-production backend behind database
allowlist and kill-switch controls, and complete signed physical-iPhone and
processed-TestFlight proof. Until those gates pass, external invitations remain
NO-GO.

### D115. Stripe sandbox beta admission is database-owned and default-off

**What.** Personal Stripe sandbox access is controlled by a private singleton
runtime switch and an exact-owner eligibility table. The migration seeds the
switch disabled and the allowlist empty. Only service-role versioned RPCs may
change either control, and an append-only exact-request ledger makes identical
configuration retries safe while rejecting a changed payload under the same
request ID.

The shared database mutation paths enforce admission so neither direct
authenticated RPCs nor Edge Functions can bypass it. Current active ownership,
the runtime switch, and exact eligibility are required for a new setup, a new
challenge commitment, a new confirmed-miss decision, automatic confirmation,
charge-command creation, and dispatch. Every admitted reader takes one shared
transaction lock before row locks, while every control writer takes its
exclusive form. This makes an atomic runtime/eligibility change serialize
without a mixed row-lock deadlock. Charge discovery also holds the currently
active eligible owners' profile rows through commit, so account deletion either
wins before discovery or waits until the claim transaction is complete.

New setups and agreements freeze
`personal-stripe-sandbox-beta-v1` authorization provenance. This allows an exact
retry of genuinely admitted work after later disablement without grandfathering
an older or manually created row. Changed retries still fail.

Turning the switch off does not hide state or obstruct risk-reducing work.
Owner status, review filing, waiver/no-charge resolution, setup-result
recording, signed webhook reconciliation, and provider-result reconciliation
remain available where appropriate. The worker performs overdue unresolved
review waivers before it returns an empty charge batch. No automatic payment
attempt is made while disabled.

**Why.** A client flag or Edge-only check would be bypassable because some setup
and commitment RPCs are callable directly. Default-off database enforcement
gives the founder one authoritative stop control, keeps tester admission
explicit, and still lets already-started provider facts reconcile without
creating duplicate or stranded obligations.

**Rejected.** A default-on switch; a JWT-metadata allowlist; Edge-only
enforcement; retroactively authorizing pre-control rows; blocking signed
webhooks or owner status while disabled; deleting eligibility rows instead of
recording a negative state; and treating local green tests as hosted proof.

**Remaining gate.** This decision is implemented and verified only in local
source. No hosted migration, control change, tester admission, Stripe call,
webhook change, or Cron change occurred. The prior five-migration rollout packet
does not contain this sixth migration and must be regenerated and reviewed.
Hosted deployment, read-back of the seeded disabled/empty state, any named
tester eligibility, runtime activation, and the full isolated Stripe smoke test
each require their own approved evidence.

### D116. App Attest assertions accept only the documented Apple extension map

**What.** Assertion authenticator data accepts either the legacy exact 37-byte
form or that prefix followed by exactly one deterministic CBOR map containing
`apple_validation_category_01` and `apple_bundle_version_01`. The map uses the
same strict types, category allowlist, and bundle-version grammar as attestation
extensions. No other keys, CBOR values, COSE key, or trailing bytes are accepted.
Verified assertions surface both signals when Apple supplies them.

**Why.** Apple's current server-validation guide explicitly directs servers to
verify these two values in assertion authenticator data. Refusing every suffix
made valid assertions from current builds look like an obsolete-client failure.
Sharing the existing extension parser fixes that compatibility boundary without
weakening the separate attested-credential/COSE path or the signed-byte check.

This supersedes D46's temporary 37-byte-only assertion constraint. It does not
alter D46's certificate, nonce, key-id, receipt, or physical-device gates, and
no hosted function was deployed as part of this source correction.

### D117. A rejected current App Attest key rotates once without rewriting saved evidence

**What.** A decoded assertion-verification refusal compare-removes the rejected
key only when it is still the current key for that account. A fresh metric or
coverage request then discards its exact signed bytes, creates a new request,
and retries once under a replacement key. A refusal for an older queued key
cannot remove a newer registration, and no queued body is ever re-signed.

**Why.** The server can legitimately stop recognizing a device key after a
reset, revocation, or registration change. Keeping the locally registered key
made every later sync fail with that same key forever. Treating every refusal
as saved evidence from an older build also hid failures involving a proof made
seconds earlier. The compare-and-remove boundary preserves immutable retries
while giving current device state one bounded recovery path and an accurate
error if that recovery is refused too.

### D118. The assertion-extension parser is hosted on every assertion consumer

**What.** On 2026-08-11, the D116 shared parser was deployed to hosted project
`jrkzdttophnmkxjoyioo`: `ingest-metrics` v44,
`personal-sync-coverage` v12, `activity-diagnostic` v12, and
`ingest-checkin` v43. Each deployment retains `verify_jwt = false` at the
gateway because its handler verifies the hosted JWKS before reading evidence.

**Evidence.** Before rollout, all 394 Edge Function tests passed. Hosted source
read-back for every function contains the legacy 37-byte branch and the strict
one-map assertion-extension branch. All four versions are active. A cold-start
POST without a bearer token reached each handler and returned its expected 401,
and the Edge logs attribute those four requests to the new deployment versions.

This deploys the backend compatibility fix only. It is not an authenticated
physical-device assertion proof, and no iOS binary containing D117's bounded
key recovery or revised sync copy was built, installed, or distributed during
this rollout. That proof still requires `GameTime-Staging` on a provisioned
iPhone followed by a successful metric and coverage sync read-back.

### D119. Assertion extensions have their own exact schema

**What.** Assertion authenticator data accepts either the legacy exact 37-byte
form or that prefix followed by exactly one deterministic CBOR map containing
the integer `validationCategory` and string `bundleVersion`. Attestation data
continues to require its distinct `apple_validation_category_01` byte string
and `apple_bundle_version_01` string. The two maps are parsed separately and
each rejects the other's field names and value representation.

**Why.** D116 incorrectly reused the attestation schema for assertions. Apple's
current server-validation guide names `apple_validation_category_01` and
`apple_bundle_version_01` only in the attestation steps, then names
`validationCategory` and `bundleVersion` in the assertion steps. Hosted evidence
made the boundary conclusive: four fresh development attestations completed
successfully, but every immediately following first assertion returned 401 and
left its stored counter at zero. App identity, environment, receipt, token, and
registration were therefore already passing; rotating another valid key could
not repair the assertion decoder.

**Rejected.** Sharing one parser between the signed structures; changing App ID,
certificate, environment, or sign-in configuration; treating another key
rotation as the fix; accepting either map shape in either context; and weakening
the exact-map, category, bundle-version, signature, or counter checks.

**Evidence.** Edge formatting, lint, type-checking, and all 394 tests pass. The
current extended-assertion shape passes through `ingest-metrics`,
`personal-sync-coverage`, `activity-diagnostic`, and `ingest-checkin`, while
cross-shape and malformed-type fixtures fail. The corrected shared verifier is
active as `ingest-metrics` v45, `personal-sync-coverage` v13,
`activity-diagnostic` v13, and `ingest-checkin` v44; source read-back contains
both dedicated parsers, and cold unauthenticated requests reached each new
version and failed at its expected 401 authentication boundary.

**Revisit if.** Apple publishes or emits a different assertion extension value
encoding, or a signed physical-device smoke test does not progress from
registration 200 to metric and coverage success with a consumed counter.

## M12 — Automatic Apple Health Personal progress

### D120. Personal v2 uses whole daily Health snapshots, not attested hourly evidence

**What.** New Personal challenges freeze `step_data_policy =
healthkit_nonmanual_daily_v1`. Historical challenges retain
`attested_hourly_v1`. The new policy queries HealthKit's cumulative statistics
for each of the seven exact challenge-local dates, lets HealthKit merge every
writer, and excludes only samples for which
`HKMetadataKeyWasUserEntered == true`. A third-party writer that omits that
marker is indistinguishable from automatic data and remains included.

One `PersonalStepSnapshot` contains the challenge id, a fingerprint of the
frozen terms, observation time, query-through time, and exactly seven ordered
daily totals. Its overall total is derived. The app caches and replaces that
whole snapshot per account and challenge; it never combines individual days
from separate reads. A successful zero or downward Health edit is authoritative.
Only a thrown or temporarily unavailable query preserves the prior value and
marks its update time stale.

The app refreshes automatically after Health permission is requested, an open
challenge loads or is created, launch or foregrounding, a HealthKit observer
change, and ordinary pull to refresh. Overlapping requests coalesce into one
active read and one trailing read. Results after an account or challenge switch
are discarded. Local Health values publish before network work, so upload
failure cannot hide or reduce displayed progress. Before cutoff, display
precedence is live Health, matching protected cache, server snapshot, then
legacy result fallback. After cutoff it is frozen server result, then local
fallback. **Connect Apple Health** remains the only permission action and there
is no positive-sample creation gate. The open challenge detail also exposes
**Sync now**, which runs the same coalesced whole-window refresh on demand.

The client uploads through one authenticated owner-bound
`upsert_my_personal_health_snapshot_v2` RPC. The server derives the user from
the session, exposes no direct snapshot-table writes, validates ownership,
lifecycle, frozen local dates, cutoff, timestamps, bounds, ordering, and
future-day zeros, and keeps one private mutable full-window snapshot. Older
observations are ignored, identical replays succeed, equal timestamps with
different payloads fail, and a newer snapshot replaces the entire old snapshot
even when totals decrease.

At `ends_at + 24 hours`, a snapshot queried through the challenge end may
produce `met_goal` or `missed_goal`. Missing or incomplete final data produces
a commitment-waived `inconclusive`. The finalizer copies the selected seven
totals directly into one immutable result and removes the mutable snapshot.
Snapshot-v2 results do not require the legacy evidence-assessment reference.
Only a complete sandbox miss may open review; met and inconclusive results
create no test charge path. Completed screens always show the frozen result.

This supersedes D99 through D104 for challenges on the new policy, D113's
manual “final sync” assumption, and D114's requirement that the Personal beta
use production App Attest. It does not rewrite v1 rows, weaken generic metric or
social attestation infrastructure, or alter the App Attest compatibility and
deployment history recorded by D112 and D116 through D119.

**Cutover.** Backend support ships first with the Personal result schedule still
inactive. After authenticated/RLS, replay/conflict, lower-total, cutoff,
finalization, and Stripe sandbox smoke tests pass, the v2-capable iOS build
becomes mandatory for the beta cohort. Completed and cancelled challenges stay
v1. Already-due legacy challenges resolve before migration. Remaining scheduled,
active, or grace-period challenges with a future cutoff migrate in place and
must perform a fresh full Health read; hourly evidence is never translated.
When the server reports v2 policy, clients retire old Personal eligibility holds
and pending hourly queues while server audit rows remain. Cron activation is a
separate explicit step after the backend smoke succeeds.

**Why.** HealthKit already owns source merging and late Watch reconciliation.
The product needs a fresh, understandable progress value and a stable published
history, not an attestation ceremony or a user-managed delivery protocol.
Replacing one whole seven-day observation preserves coherent reads, accepts
legitimate corrections, makes zero meaningful, and leaves missing final data
fail-safe while Stripe remains test-only.

**Rejected.** Translating hourly evidence into daily snapshots; splicing cached
days; requiring a positive sample before creation; treating zero as failure;
keeping a manual sync or saved-evidence action; hiding local progress after an
upload failure; accepting client-supplied owner identity; direct snapshot table
writes; equal-time conflicting payloads; mutable published results; migrating
already-due or completed history; activating Cron before backend smoke; and
using this trusted-client policy for real money without a new review.

**Revisit if.** Real-money settlement is proposed, Apple supplies a stronger
manual-entry or read-completeness signal, or the product needs multi-device
snapshot reconciliation. Each changes the trust boundary and requires a new
frozen policy rather than editing `healthkit_nonmanual_daily_v1` in place.

### D121. Main mode exposes start now and count today

**What.** Challenge creation in both demo and main modes offers **Start right
now (count today)** before the request is frozen. The default remains the next local midnight. Start-now
sends a minute-aligned request marker, but the server freezes `starts_at` at
the current frozen-timezone midnight, activates the challenge before creation
returns, and closes it after seven local dates. The exact marker remains part
of retry and Stripe sandbox consent identity. The shared challenge detail
offers **Sync now**, which immediately re-reads the whole HealthKit window and
publishes local progress before its authenticated upload.

**Why.** Starting now must include steps already taken today; opening the
scored window at the button-press minute would permanently omit them. Keeping
the server's canonical start on the local midnight also preserves the daily
snapshot and daylight-saving model while making the main and demo journeys
behave the same.

**Rejected.** Keeping start-now as demo-only; showing the main-mode toggle while
the live RPC still rejects it; scoring only steps after the button press;
accepting a marker from an earlier local date; and waiting for background
Health delivery instead of providing an explicit refresh.

**Revisit if.** A paid production settlement mode is proposed. Counting steps
from before agreement is an explicit beta product choice and must be reviewed
again before real money can depend on it.

### D122. Active cancellation is a retained sandbox lifecycle, not deletion

**What.** The existing `cancel_personal_challenge_v1(uuid, uuid)` boundary may
end a scheduled challenge before start or a still-active Personal challenge
when its frozen settlement remains demonstrably non-live: internal `test_only`
without a provider agreement, or Stripe `sandbox` with `livemode = false`.
Awaiting-final-Health, finalized, already-cancelled, other-owner, and future
live-mode rows remain refused. Exact retries return the original cancellation.

Cancellation preserves the frozen terms, activation timestamp, Stripe test
agreement, Health snapshot, and cancellation request audit. It closes the terms
and contest, releases the one-open slot, and makes result publication, payment
review, and charge-command creation unreachable. The Release client exposes
active cancellation for Stripe sandbox but not for a locked test-only Release
configuration.

**Why.** The invite-only beta needs demo parity and a safe way to recover its
single open slot without pretending history or consent never existed. Retaining
the facts keeps retries, support, and audit honest; checking provider,
environment, and `livemode` at the database transition keeps the exception from
becoming a future live-fee escape hatch.

**Rejected.** Physical deletion; clearing `activated_at`; deleting the Stripe
agreement or Health snapshot; client-only eligibility; cancellation during the
final Health window; allowing any provider-backed row; and changing the RPC or
adding a second cancellation method.

**Revisit if.** Live fees are proposed or cancelled Health snapshots receive a
new retention policy. Either requires a forward migration and explicit product,
legal, provider, and audit review.

## M13 — Adopted business model and forward planning

### D123. Friend duels and personal performance commitments are the adopted business model

**Date.** September 4, 2026.

**Decision.** The owner selected two core products: athletic friend duels with
agreed rules and credible results, and personal performance commitments with
measurable milestones and deadlines that may extend beyond seven days.
Participant stakes, pooled entry amounts and winner payouts are within future
product-design scope. Friends following progress and rematches are leading
engagement hypotheses. Spectator wagering, public prediction markets and
tradable contracts are outside the initial scope.

**Authority and supersession.** PROJECT_MEMORY.md records this adopted choice;
[docs/BUSINESS_MODEL.md](docs/BUSINESS_MODEL.md) and [PLAN.md](PLAN.md) define its
planning baseline. This supersedes the previous PLAN.md's solo-only future
scope and its Deferred V2 prohibition on pooling money or paying participants.
It also supersedes interpreting D95, D98, D101, D105–D111 or the archived charity
plan's no-prize restrictions as a global prohibition on new products. Those
rules continue to govern their historical Personal, Solo and charity records.
D113–D115 and D120–D122 continue to govern the implemented Personal sandbox,
step-data and cancellation contracts; they confer no live payment or new-duel
clearance. Earlier decisions are preserved, not renumbered or rewritten.

**Recommended implementation default.** Begin with a separate local,
default-off, simulated two-person same-event 5K agreement. The proposed human
pilot scores organizer-published chip times reviewed independently. Add native
acceptance, proof/results/review/rematches, then separate 28–90-day performance
commitments. Garmin Activity API and true-mile/asynchronous time trials are
later source-specific work, subject to access and verification. These narrow
formats, $20 simulated amounts, zero pilot fees, deadlines and cohort thresholds
are reversible planning recommendations, not owner-approved live commercial
terms. The owner example of a sub-six-minute mile remains in target scope;
a 1,600 m run cannot silently satisfy a mile.

**Compatibility.** Recommend new duel and performance-commitment aggregates
with immutable versioned agreements, explicit consent and separate request,
proof, result, review and settlement records. Reuse identity, privacy,
idempotency, review and notification patterns selectively. Do not reinterpret
`legacy_charity_contest`, `personal_accountability`, `solo-test-v1`, frozen
charity obligations, seven-day snapshots or old request envelopes. Do not enable
the reserved `social_accountability` path or dormant Solo just to accelerate
this work. Generic distance enums and a Garmin bundle identifier are not timed
running verification or an API integration.

**Payments.** All new local work and the proposed pilot are nonredeemable
simulation with no provider calls or real collection. Actual deposits, temporary
authorization holds and later failure-contingent charges are distinct funds
flows. For commitment forfeitures, the business, an approved beneficiary and
a named participant remain options; no recipient is selected. Every eventual
agreement must explicitly identify the destination and fee. A saved method
is never described as locked money. Ordinary Stripe is not assumed suitable
for prize duels: its published prohibited-business categories include
prize-bearing skill competitions and certain entry fees. The source review in
BUSINESS_MODEL.md is not account-specific approval.

**Unresolved gates.** Validate audience demand, proof credibility and fairness,
invitation acceptance, completed contests, rematches, return after loss and
willingness to pay. Select legal entity/jurisdiction, age and identity/location
rules, source permissions, provider and permitted funds flow, beneficiary,
fees, custody/refunds/chargebacks, injury and disputed-result operations, and
platform/Health-data clearance before any live launch. No region or live
provider is selected; a rejected funds flow stays disabled.

**Why.** The product decision is settled but feasibility and demand are not.
Separate future agreements preserve the meaning of existing records and let
simulated product learning proceed without pretending prior test infrastructure
has already established a trustworthy real-money sports product.

**Not done by this decision.** No application feature, migration, hosted state,
configuration, payment, deployment, distribution or outreach was performed by
the planning task. The original 502-line plan is preserved in
[docs/archive/2026-09-04_PRE_PIVOT_PLAN.md](docs/archive/2026-09-04_PRE_PIVOT_PLAN.md).
Current beta and design documents are scoped to the implementation or dated
exploration they describe; their solo-only language no longer controls future
strategy. The next build task is PLAN.md Phase 1A, with a copy-ready prompt.

### D124. Longer commitments start with a separate simulated owner agreement

**Adopted for the local Phase 3(a) implementation — September 5, 2026.**
Use private `performance_commitment_*` records and owner RPCs, preserving
Personal, Solo and duel agreement meanings. A policy preview returns the exact
terms digest; creation requires that digest, explicit consent and a new
actor-bound request. One open commitment slot is independent of duel and old
product slots. Terms and consents are immutable; replacement requires a new
agreement. Admission is server-owned, default-off and separately allowlisted.

**Reversible defaults.** The first policy is fictional official outdoor 5K
chip timing, whole-second precision and a strict target. Store 28–90 elapsed
UTC days with explicit instants and a display zone; start strictly after
agreement within 30 elapsed days. Freeze the 72-hour proof cutoff, seven-day
notice/reviewer windows and 30-day post-deadline finality cap for later scoring.
Use USD 2,000 simulated cents, fee zero, no redeemable value, recipient
`unselected` and payee null. These local choices do not select live pricing,
a beneficiary, launch jurisdiction, provider or a real-money funds flow.

**Agreement-only boundary.** Deadline passage projects awaiting proof without
freeing the slot or inferring a miss. Owner cancellation before start and
withdrawal/injury exits close with zero consequence and preserve history.
Account deletion safely closes open simulated commitments while retaining
terms/consent/requests against the tombstone. No automatic purge is added;
future proof and review need their own retention scopes and support access.

**Why.** A long performance goal needs one explicit, recoverable owner promise
before it has attempts, followers or a result. Exact UTC duration and digest
consent make boundaries reviewable without reusing seven-day arrays, old money
authority or another product's slot. See
[local acceptance and Phase 3(b) handoff](docs/PERFORMANCE_COMMITMENT_AGREEMENT_V1_ACCEPTANCE.md).
No native commitment feature, attempt evaluator, follower permission, hosted
operation or payment path was implemented in this slice.


### D125. Commitment attempts preserve successes and require explicit completeness for a miss

**Implemented locally for Phase 3(b) — September 5, 2026.** Keep the Phase 3(a)
terms unchanged. Use separate private nominated events, fictional sources,
reviewer grants/revocations, append-only per-attempt corrections and exact
requests. A later slower attempt cannot replace an earlier qualifying result.
A correction names that attempt's exact predecessor. The pure evaluator never
writes results or money, and the attempt boundary never releases the slot.

**Reversible implementation defaults.** Nominate before event start; require
the entire event window inside the agreed start/exclusive deadline; cap the
fictional event at 24 hours and the commitment at 32 distinct nominated events.
These conservative admission limits do not expand the frozen proof window.
Initial independent review must commit before the 72-hour cutoff. Corrections
require an admitted initial record and precede the finality cap. Candidate
results wait for the initial cutoff; later lifecycle work must persist notices
and preserve every full seven-day filing/reviewer window.

A miss requires either an explicit owner confirmation of the complete sorted
nomination set with all results independently confirmed nonqualifying, or an
explicit no-attempt acknowledgement when the set is empty. Confirmation occurs
after the deadline and before the proof cutoff. Missing or ambiguous records,
silence, notice failure, review timeout or insufficient time at the cap never
establish a confirmed miss. Any qualifying successful attempt suffices even if
another attempt lacks proof. An explicit correction can invalidate that attempt;
a persisted final remains authoritative and later changes require support.

**Retention and operator limits.** A dedicated local retention hold protects
proof through the longer goal and account deletion. There is no purge route,
real-proof retention duration or post-closure support capability yet. Reviewer
access needs a current server grant, real active session, independence from
the owner and audited source retrieval. Owner reads contain redacted receipts.
All new admission defaults off. Real organizer proof, result/review operation,
native screens, hosted rollout and money are later work. See
[Phase 3(b) acceptance](docs/PERFORMANCE_ATTEMPTS_V1_ACCEPTANCE.md).


### D126. Milestones and manual progress are owner reports in a separate ledger

**Implemented locally for Phase 3(c) — September 5, 2026.** Add immutable named
milestones and append-only check-ins/status changes bound to the existing
performance commitment owner. Keep consent, target, attempts, private organizer
sources and scoring snapshots unchanged. A claimed fast time or a milestone
marked complete is progress only; it never establishes a result, confirms an
attempt set, releases a slot or produces a financial consequence.

**Reversible implementation defaults.** Use 1–80-character milestone names,
1–500-character private notes, at most 32 milestones and 512 total entries per
agreement. Permit planning from agreement creation, including milestones due
before the goal starts. Due instants must be at/after milestone creation and
strictly before the agreement deadline. Admit writes only before that deadline
on an open agreement with a separate default-off progress gate. Self-reported
occurrence time cannot predate the agreement or linked milestone or be future.
Server receipt times preserve UTC microseconds independently.

Milestones transition from planned to completed or retired; a completed one
can reopen, while retirement is terminal. Every status change names the exact
previous status revision. Retire and replace a plan to preserve its original
name/date. A late due date never implies a miss. General notes and status changes
share one actor-bound exact-request namespace. Committed retries survive gate
shutdown, later status changes, deadline passage, full history and safe closure;
an inactive owner or revoked/expired session loses access.

**Privacy and retention.** Owner-only RPCs expose bounded history with a fixed
upper sequence, including milestone states at that sequence. Each entry is
explicitly owner-reported and not proof. Followers receive no implicit access.
A distinct local progress retention hold preserves definitions, notes and exact
receipts after safe closure/deletion; the legacy purge has no authority over
it. This is not a selected retention duration for real notes. Define sharing,
revocation and an appropriate release/purge policy before hosted operation.

See [Phase 3(c) acceptance](docs/PERFORMANCE_PROGRESS_V1_ACCEPTANCE.md).
Native commitment flows, following, result/review operations and live money
remain later slices.

### D127. Following shares explicit progress selections through revocable bilateral consent

**Implemented locally for Phase 3(d) — September 5, 2026.** Keep the owner
progress ledger private. An accepted friend receives selected goal facts and
explicitly published progress only after separate owner scope consent and
follower acceptance. Check-in publications omit note text and linked private
milestone identity; milestone publications freeze the selected name, date and
reported status. No automatic later progress, raw proof, financial details or
result projection is included. Following never affects proof or agreement terms.

**Reversible defaults.** Scope `goal_and_selected_progress_v1` shares the strict
5K target/window and the same selected publication set with all active followers.
Pending invitations expire within seven days or at the goal deadline, with 32
open/128 total invitations and 512 total publications per commitment. Card pages
are limited to 50 and reject a continuation after publication/retraction changes.
Reactions are three fixed encouragement codes, one current reaction per follow
and card. A follower can schedule one personal in-app reminder within 30 days
and before the deadline. No schedule or external delivery is installed.

**Safety and recovery.** Revocation, unfollowing, blocks, unfriending, either
person's deletion and safe commitment closure end prior grants permanently.
Unblocking/re-friending requires fresh consent. Sharing reads and writes serialize
with those changes and recheck active sessions after waits. Exact actor-bound
requests retain original action receipts, never previously shared content or
renewed access. Safe exits, retraction, report intake and private reporter history
remain available when admission stops.

**Support and retention.** Each named person may submit up to 16 private reports
per follow with 1–500-character plain-text notes. Report access is reporter-only
or requires an independent active operator's service-assigned, case-specific
grant lasting at most seven days; operator reads are audited and resolutions
are immutable. Following/report storage has a distinct local retention hold,
without an approved real-data duration or purge procedure. This is not a staffed
support operation, proof review permission or post-final result support.

See [local acceptance and the native/Phase 3(e) handoff](docs/PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md).
Native caches must clear on account/authorization changes and reject late actor
responses; that client work remains unimplemented. Commitment result/review
persistence, real organizers, hosted operation and money remain separate work.


### D128. Commitment finality uses complete proof snapshots and separate simulated consequences

**Implemented locally for Phase 3(e) — September 5, 2026.** Connect the unchanged
strict-target evaluator to a separate default-off lifecycle ledger. Preserve
all earlier policy/consent terms and agreement closure receipts. Durable owner
notices, append-only review cases and independent resolutions supply the frozen
seven-day filing and seven-day reviewer windows. Corrections require new
notices; neither worker delay nor the finality cap shortens those windows.
Missing proof, silence, timed-out review and insufficient windows cannot create
a confirmed miss or simulated loss.

Compare the entire private proof/lifecycle snapshot under owner/operator locks,
including unreviewed captured sources, before committing worker decisions.
Reevaluate after relevant state changes or a clock-boundary crossing; preserve
PostgreSQL microseconds. Service-only commits trust the versioned pure worker,
while clients/operators cannot choose clocks, results or consequences. The
manual operational adapter remains loopback-only with bounded stale retries.

Final results are immutable, release the independent slot and permanently end
existing follows/reminders. New following requires an unfinalized commitment;
no result-sharing consent is inferred. Old agreement status is a historical
receipt, with operational finality exposed separately. Account deletion remains
possible before/after finality and cannot change a saved result.

**Reversible operational defaults.** One owner case per durable notice; reasons
are wrong result, wrong identity or missing result. Independent review/support
assignments use separate per-commitment scopes lasting at most seven elapsed
days, with real active-session checks and audited reads. Post-final intake is
at most 64 bounded 1–500-character plain-text operator notes. It is separate
support history, not new qualifying proof or automatic redress. A current
support assignment can access retained records after owner deletion; an owner,
a follower or an earlier proof/social-support grant cannot claim that authority.

Append simulation after finality and recover interruptions idempotently. A
confirmed miss records 2,000 simulated lost cents; all other outcomes record
2,000 returned cents. Fee is zero, recipient remains unselected, payee is null
and nothing is redeemable or transferred. This preserves D124 rather than
selecting a live price, beneficiary or funds flow. A distinct fictional hold
retains result/review/support records until an approved retention policy exists.

See [acceptance and the native handoff](docs/PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md).
Native commitments, actual organizer/review/support operations, real-data purge,
hosted operation, external delivery and live money remain separate gates.

### D129. Native commitments begin with owner agreement and authoritative result history

**Implemented locally for the first Phase 3(f) slice — September 5, 2026.**
Add an opt-in Running goals route for explicit local development, with typed
owner preview/consent, agreement history, notices/reviews, safe exits and
separately recorded nonredeemable simulation. Release cannot open the route or
send these RPCs. Preserve all existing agreement and payment terms.

An original `open` agreement does not imply the absence of a final result.
Read the separate lifecycle and distinguish unknown/pending results from saved
outcomes and separately appended simulation. Preserve microsecond wire values
and full review windows; a cap never creates a loss from missing proof or an
incomplete review.

Persist complete actor-bound requests before sending, require explicit exact
recovery, bind returned receipts to freshly read history, and clear owner content
on account changes, backgrounding and failed reads. No auth credential or result
cache belongs in the envelope. The editor's 25:00 target, next-day start and
56-day duration are editable defaults, not new policy or launch recommendations.

Native attempt/completeness entry, private progress and selected following are
next. No result-sharing consent, actual organizer operation, staffed support,
hosted mutation or live funds flow is added. See
[the first native slice and handoff](docs/PERFORMANCE_COMMITMENT_NATIVE_V1_ACCEPTANCE.md).


### D130. Engagement rewards athletic progress and informed, voluntary participation

**Adopted September 6, 2026, in response to the owner's report-based change request.**
Optimize agreement comprehension, chosen athletic progress, credible results and
voluntary retention, constrained by pressure, privacy and exit guardrails. Remove
the pilot target for return within seven days after a loss. Do not optimize
committed dollars, paid-challenge frequency, app opens or notification clicks in
isolation; never use missed goals, losses or health data for revenue targeting.
No financial celebrations, forced daily exercise streaks, automated rematches,
stake escalation, repeated declined invitations or hidden risk/exit controls.

The current native change summarizes the existing fictional-5K simulated terms
before consent and keeps the complete detailed rules expandable. Exact consent
strings, policy/digest checks and historical receipts are unchanged. Dormant
native lead-loss/comeback notification category setup and launch permission
prompting are removed; foreground legacy notifications are suppressed and push
stays disabled. This is not a new reminder or preference system.

Future push requires contextual permission, explicit categories, caps, quiet
hours, current server authorization, suppression and deduplication. Future money
requires server-enforced aggregate outstanding and rolling new-commitment limits,
user pause and deliberate delayed increases without obstructing records, review,
exits, support or applicable money access. Limits, delay, notification caps,
forfeiture recipient and pricing remain unselected/proposed, not live policy.
Revenue research prioritizes transparent fees and optional club value without
relying on participant failure. New source/metric policies honor the owner's
participant-selected-distance direction; historic 5K agreements stay intact.

See [business requirements](docs/BUSINESS_MODEL.md#responsible-engagement-and-commercial-incentives),
[current implementation order](PLAN.md#current-implementation-order-after-the-engagement-review)
and [verification](docs/RESPONSIBLE_ENGAGEMENT_ACCEPTANCE.md). Native progress/
following, external reminders, financial limits and human-pilot evidence remain
explicit next work. No migration, hosted operation, external message, provider
integration or live money was added.


### D131. Weekly-first planning preserves completed formats and separates new rules

**Planning revision, September 6, 2026, requested by the owner.** The owner
explicitly dropped the mandatory fixed-5K format and accepts participant-chosen
supported distances. Friend challenges and personal commitments remain adopted.
This revision authorizes a reconciled plan, not a public launch, live money or
all candidate modes. D130 responsible-engagement requirements remain in force.

**Recommended sequence:** W1 cumulative weekly steps with a friend; W2 one
weekly community experiment; W3 Apple Watch Exercise minutes after source
validation; W4 configurable cumulative/timed distance and useful longer-goal
progress/following. Begin with W1A's pure fictional policy, qualification
evaluator and tests. Pause the organizer-nomination UI as the default next task.
The detailed [weekly specification](docs/WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md)
owns these planned slices; [PLAN.md](PLAN.md) owns their overall order.

**Reuse boundary:** keep old Personal/Solo/charity and fictional-5K agreements,
source semantics, exact pending requests, scorers, final results, simulated
returns and acceptance records. Reuse identity, consent, recovery, progress and
review/privacy patterns under new versioned contracts. Fixed distance and
exactly two participants are validated rules, not display defaults that can be
silently widened. Community enrollment and multi-winner allocation are new work.

**Proposed rules:** two friends can each meet their agreed weekly target. A
confirmed miss is distinct from missing or unreadable data. Public pooled goals
need a published difficulty policy; the formula is not selected. Weekly
activity windows and pending review are separate, so an explicit future-week
join need not wait for prior-week finality. All pending financial exposure must
still count toward server limits before any future real-money admission.

**Simulation and open decisions:** proposed weekly fixtures use 2,000 example
cents per person and zero fee; qualifiers recover entries and may share
confirmed forfeitures. Zero-winner forfeitures and division remainders remain
explicitly unallocated simulation with no payee. Community launch, real funds
flow, fees, recipients, provider, admission/financial limits and jurisdiction
remain unresolved. Other apps' economics are research, not approval or a
revenue forecast. New acceptance must cover all/none/some qualifiers, unresolved
proof, withdrawals, integer conservation and concurrent next-week participation.

**Pilot:** replace the earlier organizer-oriented first study with a proposed
20–30 adults over two consecutive weekly rounds, including solo joiners and
friend groups, after source/native/community/privacy/support acceptance. Use
nonredeemable simulation and descriptive comprehension, fairness, meaningful
progress and voluntary-return evidence. No loss-triggered outreach or growth
target for paid frequency. Recruitment/distribution remain separately gated.

This change updates planning documents and a forward-handoff note only. It does
not implement W1–W4, alter app/schema behavior, enable a provider or modify
hosted state. The historical phase and engagement acceptance remains intact.


### D132. Beta friend groups and one common community step goal

**Owner direction, September 6, 2026:** beta friend challenges should support
up to five friends. Community launch should use one goal everyone works toward,
starting with a weekly step goal. This supersedes D131’s pair-only W1 proposal
and personalized community target/difficulty formula for initial scope.

**Explicit working interpretations:** five participants total, including the
creator (2–5 per friend challenge); each community entrant individually meets
the same published weekly step target, rather than adding steps to a collective
total. The owner has not separately confirmed those interpretations. The numeric
community goal remains unselected. Individual custom friend targets remain a
proposed default, not a new owner mandate.

Update W1A’s pure evaluator for a frozen roster and all consents; cover every
group size, capacity violations and all/none/some qualifiers. W1B/C add group
invitations, roster consent, privacy and concurrency/native acceptance at the
beta capacity. New group simulation recommends equal sharing of confirmed
forfeitures, unallocated remainders and conservative whole-group refunds for
unresolved proof or safe exits. These are reversible simulation proposals.
W2 freezes one common target before joining and rejects per-person overrides;
no personalized baseline formula is needed for this launch format.

This is planning scope, not implementation, recruitment, deployment or payment
authorization. Source validation, target suitability, rollout clearance, actual
money rules and D130 safeguards remain required. Historical agreements and
unrelated work remain unchanged.
