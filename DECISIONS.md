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

### D22. Contest creation and every participant transition is a function

**What.** `contests` and `contest_participants` grant clients `SELECT` and almost
nothing else. Creation, invitation, acceptance, declining, withdrawal, and
cancellation are all `SECURITY DEFINER` functions. The only direct write a client
holds is a column-level `UPDATE` on the creator-editable terms.

**Why.** M1 met this once with `join_group_by_code()` and concluded that RLS
answers "may this caller read or write this row", not "does this caller already
know a secret". M2 meets it repeatedly, and the reasons are worth separating
because they are three different problems:

- **Multi-row atomicity.** Creating a contest also enrols the creator. A contest
  with an empty roster has no owner and nothing that could clean it up, which is
  the same reasoning that made a group seed its creator as its first member
  (D17). It must not be observable.
- **Cross-row eligibility.** "Is this invitee a friend, a co-member, or blocked
  by anyone already on the roster" reads rows other than the one being written.
  A `WITH CHECK` cannot express it, and a policy permissive enough to let a
  client evaluate it themselves would leak the answer.
- **Serialization.** `max_participants` bounds a `COUNT`. Two people accepting
  the last slot concurrently both pass a naive check, so the cap is only real if
  acceptance takes `FOR UPDATE` on the contest row first — which requires a
  function body.

**Rejected.** Direct inserts with a trigger seeding the roster, as groups do
(works for the atomicity problem alone, and the creator's timezone and charity
nomination are not columns on the contest, so they would have nowhere to arrive
from). Doing the eligibility checks client-side (the client is the adversary
here).

**Revisit if.** Nothing foreseeable. The shape follows from the checks.

### D23. Both state machines are allow-lists, declared whole in M2

**What.** `contest_status` and `participant_status` declare every state either
will ever hold, M7's included. `app.assert_contest_transition()` and
`app.assert_participant_transition()` reject any pair not on an explicit list.
M2 implements `open → active` and `open → cancelled`; the edges out of `active`
are listed as legal and M7 adds the code that walks them.

**Why.** A machine grown one state per milestone is a machine nobody ever reads
whole, and the failure mode is silent: an enum value added later is reachable
from every existing state unless somebody remembers to constrain it. Declaring
the states now costs one migration line each and makes the lifecycle reviewable
in one place. The allow-list direction matters for the same reason — a deny-list
of illegal transitions is wrong by default when a state is added.

Two things fall out of writing it down. `active → cancelled` is illegal, because
once a contest is running there are pledges on the table and cancellation would
be a losing creator's escape hatch; an active contest ends by being scored.
And nothing leaves `declined`, `lapsed`, `withdrawn`, or `forfeited` at all.

**Rejected.** Enum values added per milestone (smaller diffs now, and no single
place where the lifecycle can be checked). A status column with no trigger,
relying on the functions to be correct (the functions are the only writers today,
which is exactly the assumption that stops being true the first time a script
touches the table).

**Revisit if.** A contest needs a pause, or a dispute needs to reopen a settled
result. Both are new edges, and the point of the allow-list is that they have to
be written down.

### D24. Terms freeze on the first acceptance by somebody else

**What.** A creator may revise the terms while the contest is `open` and no
participant other than themselves has accepted. After that the whole terms block
is immutable. Enforced twice: a narrow `UPDATE` policy plus column grants for
clients, and `app.forbid_locked_terms_change()` for everybody else.

**Why.** Every column in the terms block is something a participant agreed to.
Editing the target after somebody accepted is changing a deal they already
shook on, and in this product the deal ends in one of them donating money. The
condition is precisely "has anyone else agreed yet" rather than "has anyone been
invited", because an outstanding invitation is an offer nobody has taken up — a
creator fixing a typo before anyone answers is not doing anything to anybody.

The second layer is D21's pattern, and it earns itself the same way: the policy
constrains clients only, so without the trigger a service-role query or a future
Edge Function could rewrite the target of a running contest. `kind` is frozen
harder than the rest — unconditionally, from the first instant — because turning
a duel into a group contest changes how many settlements a result can produce.

**Rejected.** Freezing at creation (simplest, and it makes an unavoidable typo a
reason to cancel and re-invite everybody). Freezing at first invitation (nearly
right, but punishes the creator for a state change nobody else has acted on).
Versioned terms with re-acceptance (honest, and it multiplies the state space of
every scoring question M4 has to answer).

**Revisit if.** Creators turn out to need one specific late edit — extending
`ends_at` by mutual consent is the plausible one. That is a consent flow, not a
loosening of this rule.

### D25. Declining is terminal, and there is no re-invitation

**What.** `invited → declined` is a one-way edge. Re-inviting somebody who
declined returns their existing status rather than resetting the row.

**Why.** The same reasoning that removed the `declined` friendship status in D16,
applied to a place where it would have been easier to leave a nag path open. A
resettable invitation is an unlimited "are you sure?" from somebody who is,
by construction, a friend — and the mechanism for not being asked again should be
a block, which the person makes deliberately and knows they made, rather than a
quirk of how many times a creator is willing to retry.

Idempotency is what makes this practical: `invite_to_contest()` returns the
status it found, so a client retrying on a flaky connection cannot accidentally
re-ask, and a creator can tell "already invited" from "they said no" without a
second read.

**Rejected.** Re-invitation with a cooldown (throttles the nag without removing
it, and adds a timestamp to reason about in every policy). Deleting the row on
decline, mirroring D16 exactly (tempting for symmetry, but a friendship has two
parties and a contest has a creator who would then be able to re-invite freely —
deletion here *creates* the nag path rather than closing it).

**Revisit if.** Creators legitimately need to re-offer after changing the terms.
That is a new contest, and it costs nothing to make one.

### D26. A block refuses co-participation but ejects nobody, and co-participation outlives it

**What.** Three parts, and they resolve two things M1 left open:

- Nobody may be invited to a contest if they are blocked, in either direction, by
  anybody already on the roster. Checked against the whole roster, not just the
  creator.
- A block still removes nobody from any group or any running contest.
- `app.shares_contest()` is a route to reading a profile, and unlike the friend
  and group routes it sits **outside** the block check.

**Why.** M1 recorded the tension and deferred it: blocking does not eject either
party from a shared group, because that power is exactly what flat membership
withholds from everyone (D17). Without a check at invitation time, a group
contest would therefore be a way to put two people who have blocked each other
into a mutual donation obligation. Refusing the pairing fixes that without giving
anybody the removal power D17 denies them.

The third part is the one that looks inconsistent and is not. A block cannot
create the situation — nobody blocked can be invited, and nobody blocked can
already be on the roster — so the only way to reach it is a block placed *after*
an invitation. At that point hiding the profile would replace a live opponent
with an unknown user in the blocked party's app, which announces the block to
precisely the person D19 went out of its way not to tell. The contest keeps
running either way; a pledge does not care how the two of them feel about each
other. So the block goes on doing everything it can do without leaking —
severing the friendship, ending discovery, refusing new invitations — and stops
short of the one action that would speak.

**Rejected.** Ejecting on block (hands every user a way to remove anyone from a
group by blocking them). Hiding co-participants' profiles behind the block check
(consistent-looking, and it turns a block into a notification). Leaving
invitation unchecked and relying on people not to do it (the roster is where the
money is).

**Revisit if.** Blocking mid-contest becomes a common way to harass an opponent.
The fix is a reporting path and M5's integrity flags, not a change here.

### D27. Each participant nominates their own charity; the winner's nomination is the destination

**What.** `contest_participants.charity_id`, chosen at acceptance, required.
Nobody nominates on anybody else's behalf, and the contest itself has no charity.

**Why.** The product is "the loser donates to a charity the winner picks", and
the winner is not known until scoring. The only way to have a destination ready
for every possible outcome is for every participant to have declared one, which
also makes the winner-takes-all group case work unchanged: `n-1` settlements
(D4), all pointing at the single winner's nomination.

Two smaller choices inside it. The nomination is frozen when the contest starts
rather than at acceptance — before the start, changing your mind harms nobody;
after it, a movable nomination is a bait-and-switch once a result is visible.
And the foreign key is `ON DELETE RESTRICT`, not `CASCADE` or `SET NULL`: a
nomination is part of the agreed terms, so a charity any contest points at cannot
be deleted out from under it. Retiring one is `is_active = false`, which stops
new nominations and leaves historic ones renderable.

**Rejected.** One charity per contest, set by the creator (simpler, and it means
the winner does not pick — which is the product). Picking at settlement time
(no frozen agreement, and it lets a winner shop for a destination after the
fact). Defaulting to a house charity (nobody's choice, and it makes the pledge
feel like a fee).

**Revisit if.** Participants want to split a donation across charities. That is a
join table, and the settlement shape in D4 would have to widen with it.

### D28. Charities are seeded reference data with no client write path

**What.** `charities` grants `SELECT` to `authenticated` and nothing else — no
policy and no grant for insert, update, or delete. The local seed carries three
obvious placeholders whose EINs use a `00-` prefix the IRS does not issue.

**Why.** If a client could add a row here, "donate to charity" would become "pay
an arbitrary payee of the winner's invention", which is the one failure mode a
charitable-pledge product cannot have. Read-only is therefore not a convenience,
it is the control, and it is a withheld grant rather than a missing policy for
D21's reasons.

The placeholder seed is a separate deliberate choice. Attaching plausible-looking
EINs to the names of real organizations would be fabricating official
registration identifiers, and those rows would be indistinguishable from real
reference data the moment they appeared in a screenshot or got copied into an
environment. Unmistakably fake fixtures cost nothing and cannot be mistaken for
anything. Production reference data is loaded out of band, as briefed — no IRS
Pub 78 import in v1.

**Revisit if.** The list needs to be large enough that curating it by hand stops
working. That argues for an import pipeline writing through `service_role`, not
for a client grant.

### D29. Tie-break is declared at creation, and the incoherent pairing is refused

**What.** `contests.tie_break` defaults to `integrity_score`. A CHECK constraint
refuses `earliest_to_target` on a `daily` cadence.

**Why.** Declared up front, never chosen once a result is known, which is the
whole point of putting it in the terms block that D24 freezes — a tie-break
picked afterwards is picked by whoever it favours. `integrity_score` is the
default because it makes clean data the thing that wins a tie, which is the
incentive this product wants to create.

The constraint exists because "first to reach the target" has no meaning when the
target resets every day. Rather than leave M4 to interpret an incoherent
combination, the row cannot be written. Resolution logic is still M4's; M2 only
records the declaration.

**Rejected.** Resolving ties ad hoc (favours whoever argues hardest). Always
splitting (`both_donate` as the only rule; doubles the obligations a tie creates,
and it is available as a choice for people who want it).

### D30. Group size is capped at contest creation, not on the group

**What.** `contests.max_participants`, declared by the creator, constrained to
2–20 by the schema and forced to exactly 2 for a duel. Outstanding invitations
count against it, and acceptance re-checks it under a lock.

**Why.** The group is not the thing being staked. A winner-takes-all contest
among *n* produces *n-1* donation obligations (D4), so the number that needs
bounding is how many people are in the *contest* — the same group can reasonably
run a duel and a twelve-person challenge. Capping the group instead would limit
the wrong thing and would also mean one contest's stakes constraining an
unrelated part of the product.

Two details. Invitations count against the cap rather than only acceptances,
because the alternative is inviting thirty people to a four-person contest and
letting the race decide, which is a worse experience than being told it is full.
And 20 is the schema ceiling rather than the product's answer: at a $1,000 stake
ceiling it bounds one contest at 19 obligations, which is generous for the
friend-group scale D17 describes and still finite.

**Revisit if.** Group contests get used at league scale, which is the same
pressure D4 identifies as the reason to revisit round-robin.

### D31. Stakes are bounded integer cents in a single currency

**What.** `stake_amount_cents` between 100 and 100000. `stake_currency` exists,
defaults to `USD`, and is constrained to exactly that.

**Why.** Integer cents because a pledge amount is money and binary floating point
is the wrong representation for money. The floor stops a contest being a joke
with no stake; the ceiling is a typo guard, and it matters more than it looks
because a group of 20 turns one mistyped stake into 19 obligations.

The currency column is there this early for one reason: a money field with no
currency beside it is a latent bug the moment there is a second market, and
adding it later means backfilling every row and auditing every read. Present and
constrained, widening v1's assumption is a CHECK change.

**Revisit if.** Non-US charities are supported. That is the constraint change,
plus a decision about whether a contest's participants may nominate across
currencies — which they should not, and D27's per-participant nomination is where
that would have to be enforced.

### D32. Activation is a callable sweep; its scheduler arrives in M7

**What.** `app.activate_due_contests()` resolves every `open` contest whose start
has passed: `active` with two or more acceptances, `cancelled` otherwise.
Unanswered invitations become `lapsed`. Granted to `service_role` only.

**Why.** The open → active edge has to exist before M3 has anything to ingest
against, and a state machine whose transitions nothing can perform is
aspirational rather than tested. Writing it as a plain function keeps the cron
question — which belongs with M7's settlement scheduling — separate from the
transition logic, and makes the edge exercisable in pgTAP today.

Two rules inside it. One acceptance is not a contest, so a due contest with only
its creator is cancelled rather than won by default. And an unanswered invitation
becomes `lapsed` rather than `declined`, because they never said no; the
distinction is visible in the data, since a lapsed row never chose a charity or a
timezone and the CHECK constraints will not let it have done.

It is not a client function: it acts on every contest that has come due, not on
one the caller has a claim to, so no client has any business calling it.

**Revisit if.** Nothing foreseeable. M7 adds a scheduler that calls it.

---

## Decisions deferred, with a current default

Recorded so they are not silently made later. Each has a working default;
each gets its own entry above when it is actually implemented.

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
- **A deleted account takes its contest history with it (M7).**
  `contest_participants.user_id` cascades from `profiles`, which cascades from
  `auth.users` — so deleting an account erases the roster rows that a settlement
  would be built from. That is a live escape hatch for a loser in an active
  contest, and it is inherited from M1 rather than introduced here (D21 withholds
  a client `DELETE` on `profiles`, but account deletion itself is out of band).
  Proposed: settlement rows in M7 snapshot the handle and display name they were
  issued against, and hold the participant reference with `ON DELETE SET NULL`,
  so an obligation survives the account that incurred it. Deliberately not fixed
  in M2, because the thing that has to survive is a settlement and settlements do
  not exist yet.
- **Contest visibility stops at the roster (M8).** A group contest is readable by
  its participants, not by the whole group it came from — so members who were not
  invited are not told it happened. That is the more private default and it is
  cheap to widen. Revisit when the client has a group screen and it becomes clear
  whether "3 contests running in this group" is something people expect to see.
- **Extending `ends_at` by mutual consent (M7).** D24 freezes the terms on the
  first outside acceptance, which makes a mid-contest extension impossible. It is
  the one late edit with a plausible honest use. Proposed: a consent flow
  requiring every accepted participant to agree, not a loosening of the freeze —
  and it belongs next to M7's dispute handling, which is the other place
  participants have to agree on something after the fact.
