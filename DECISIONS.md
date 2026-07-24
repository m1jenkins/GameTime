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
against `lapsed` — an answer against silence — is a distinction M7's reliability
score has reason to read. Deleting would also make re-invitation silently
possible where the primary key currently makes it idempotent.

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

**Revisit if.** Users want to change their nomination after a contest ends but
before settling. That is M7's question, and the answer is probably that the
settlement snapshots it.

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

**Revisit if.** A participant needs a genuine medical or bereavement exit. That
is a dispute for M7 to resolve into a void, not a status the participant can
write themselves.

### D30. Quorum is two, and a contest that misses it voids itself

**What.** `app.activate_due_contests()` opens every pending contest whose
`starts_at` has passed, provided at least two participants accepted. One or
fewer and it becomes `cancelled` with reason `insufficient_participants`.
Outstanding invitations lapse either way.

**Why.** A contest is a comparison and there is nothing to compare one person
against, so a lone author running a contest against themselves is not a degraded
outcome to be tolerated — it is a state with no meaning that would still produce
standings, a winner, and no settlement. Voiding says so explicitly, and the
distinct cancellation reason keeps it from looking like the author called it off,
which matters because M7's reliability score will read these rows.

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

**What.** `app.activate_due_contests()` revokes EXECUTE from `public`, `anon`,
and `authenticated`, and grants it to `service_role` alone. M1's predicates in
`app` do not, and must not.

**Why.** Two defaults combine into a live privilege-escalation path. Postgres
grants EXECUTE on every new function to `PUBLIC`, and the baseline migration
grants `authenticated` USAGE on the `app` schema so that RLS policies can call
the predicates living there. Together they mean a SECURITY DEFINER function in
`app` is callable by any signed-in user unless it is explicitly revoked — and
this one opens contest windows and voids contests for want of a quorum. Left as
created, a client could activate a contest early or void one out from under its
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

## Decisions deferred, with a current default

Recorded so they are not silently made later. Each has a working default;
each gets its own entry above when it is actually implemented.

Five entries were resolved by M2 and now have their own decisions above: the
tie-break menu (D22's enum, declared at creation, defaulting to integrity
score — how each option is *computed* is M4's scoring), charity reference data
(D26), contest co-participants seeing each other's profiles (D33), the group size
cap (D28, resolved as a contest-level ceiling of 20), and whether a block ejects
either party from something shared (D29, resolved harder for contests than for
groups).

- **Quarantine approval in group contests (M5).** A retroactively-written sample
  counts only if approved. In a duel that means the opponent. In a group,
  proposed rule: a majority of other active participants, failing closed —
  no response inside the review window means the sample stays excluded.
- **Reliability score formula (M7).** Proposed: a decayed ratio of confirmed
  settlements to total obligations, so one old default does not brand someone
  permanently.
- **Integrity score scale (M5).** Proposed: start at 100, subtract per-flag
  severity weights, floor at 0. Never auto-disqualifies; it is displayed and it
  strengthens a dispute.
- **Handle change throttling (M8).** Handles are freely editable today. Swapping
  to a friend's handle shortly before settlement is a plausible impersonation
  play. Proposed: one change per 30 days, enforced by a `handle_changed_at`
  column, plus showing the change to anyone in an active contest with them.
- **Avatar storage bucket and its policies (M8).** `profiles.avatar_path` holds
  an object path, but no bucket exists yet and nothing writes it. The bucket
  and its RLS arrive with the client that uploads to it.
- **Account deletion versus contest history (M7).** D34 fixed the half that was
  broken — a departing account now clears the references that point at it, and
  the contest survives. The half that remains open is `contest_participants`,
  whose `user_id` cascades from `profiles`: deleting an account still erases that
  person's roster rows, including the record of a settlement obligation.
  `restrict` would preserve the evidence and make account deletion impossible for
  anyone who has ever entered a contest, which is worse. Cascade is the current
  default, consistent with `group_members` in M1. The real answer is probably to
  anonymise the profile rather than delete the row, and it belongs with
  settlement, where the obligation it would erase actually exists.
- **Timezone change mid-contest (M5).** D5 allows a genuine relocation with
  opponent consent plus an integrity flag. M2 makes
  `contest_participants.timezone` strictly immutable instead, because there is no
  flag to raise until M5 and a consent flow with nothing to record is worse than
  no flow. Default: immutable, and a relocating participant lives with their
  frozen zone for the rest of the contest.
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
