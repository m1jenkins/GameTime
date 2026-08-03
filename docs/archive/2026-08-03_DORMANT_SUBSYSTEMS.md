# Dormant subsystems (V2 / regression reference)

Archived from README.md on 2026-08-03. These subsystems remain implemented,
tested, and read-compatible, but Personal Accountability V1 does not expose
any of them. Nothing here describes a reachable V1 surface.

The evidence ledger, attested ingest, and account deletion stayed in README.md
because Personal V1 depends on them directly.

## Owner-only Solo contracts (Steps 2A–2B, local and disabled)

Step 2A is an isolated aggregate layered after the Personal V1 migrations. It
does not rename, drop, archive, disable, or reinterpret the existing Personal or
Social implementation.

| Record | Contract |
| --- | --- |
| `solo_contracts` | Frozen owner, policy version/digest, steps goal, $10–$50 USD commitment, `test_only` settlement mode, timezone, and 1–7-local-day window plus a guarded lifecycle projection. |
| `solo_evaluations` | One append-only service-authored preliminary evaluation per contract. A failure freezes its appeal deadline from the contract's policy version. |
| `solo_appeals` | Append-only events: one owner-filed appeal per preliminary failure, then at most one service-authored decision. Decisions are inserted, never updated. |

Step 2B adds two relations in the unexposed `app` schema:

| Private record | Contract |
| --- | --- |
| `app.solo_authorizations` | Exactly one immutable `processor_neutral_fake` / `local-fake-v1` authorization for a v2 contract, bound by composite foreign key to the contract, owner, policy version and digest, amount, `USD`, and `test_only`. |
| `app.solo_authorization_events` | Exactly one initial `authorized` fact followed by at most one matching `cancelled`, `released`, `forfeited`, or `waived` resolution. Every event repeats and digests the immutable binding. |

Authenticated clients have `SELECT` only on the three public Step 2A tables, and
RLS limits that read to the active owner. They cannot directly insert, update,
delete, truncate, settle, evaluate, or decide. The two private Step 2B tables
have RLS enabled as defense in depth and grant no direct privilege to `public`,
`anon`, `authenticated`, or `service_role`. Mutations are limited to:

```text
authenticated
  create_solo_contract_v1
  create_solo_contract_with_fake_authorization_v2
  cancel_solo_contract_v1
  file_solo_appeal_v1

service_role
  set_solo_contract_runtime_v1
  set_solo_beta_eligibility_v1
  advance_solo_contract_v1
  record_solo_evaluation_v1
  decide_solo_appeal_v1
  settle_solo_contract_v1
```

Each listed Solo RPC mutation has an exact-request record. Creation requires an
active profile, an explicit DB beta-eligibility row, an enabled DB runtime
switch, and the caller's exact acknowledgement of the active immutable policy
version. Exact committed retries are resolved before those mutable rollout
gates, so a lost response can still be recovered after a switch or eligibility
change.

`create_solo_contract_v1` remains unchanged and contract-only.
`create_solo_contract_with_fake_authorization_v2` applies the same reviewed
owner, policy, rollout, and one-open-slot boundary, then creates the contract,
one immutable fake authorization, its initial `authorized` event, and the
exact-request result atomically. A request UUID committed through v1 cannot be
upgraded into v2, and reusing a v2 UUID with changed terms fails.

The pure private adapter deterministically supports `authorize`, `refuse`,
`retryable`, and `injected_failure` for local tests; the authenticated public v2
RPC exposes only `authorize`. Refusal and retryable scenarios commit an exact
outcome without leaving a contract or authorization. Injected failure occurs
after the candidate contract is created and proves that the candidate contract
and request record roll back together. The adapter stores and logs no raw
payload.

The lifecycle is forward-only. Cancellation is available only while scheduled
and strictly before `starts_at`; an exact committed cancellation retry remains
recoverable afterward. One unsettled row per owner is enforced by a partial
unique index. Account deletion cancels a genuinely pre-start contract and
retains post-start evaluation/appeal history for service finality while stale
owner tokens lose all access. That write is the only integration exception to
the Solo exact-request ledger: a versioned, transaction-marker-guarded trigger
inherits the existing atomic D81 `delete_account` boundary and audit trail.

For v2 contracts, pre-start owner cancellation and D109 pre-start account
deletion append `cancelled` in the same transaction that cancels the contract.
Appeal filing and decision do not resolve the fake authorization; it remains
open until contract finality. Terminal logical settlement appends exactly one
matching `released`, `forfeited`, or `waived` event in the settlement
transaction. Concurrent or repeated resolution attempts serialize to one event.
Contract-only v1 rows deliberately remain authorization-free.

Every authorization outcome is local and fake. There is no provider SDK,
credential, secret, payment method, card data, customer identifier, mandate,
webhook, external API call, authorization hold, capture, charge, transfer,
payout, log payload, or real-money side effect. The Solo creation switch remains
off, the beta allowlist remains empty, and there is still no iOS route, public
Edge endpoint, scheduler, Personal-to-Solo integration, cross-domain slot rule,
or hosted configuration.

Local fake-adapter tests prove only local schema, transaction, privilege, and
deterministic-adapter behavior. They do not prove a real processor, money
movement, legal or App Review approval, hosted scheduling, physical-device
behavior, or hosted multi-user isolation.

## Dormant legacy social graph (V2/regression)

These pre-pivot M1 tables remain read-compatible for historical challenges and
explicit regression tests. Personal V1 does not load this inventory. All five
have RLS enabled and no `anon` access at all.

| Table           | Shape                                                        |
| --------------- | ------------------------------------------------------------ |
| `profiles`      | One durable actor row per onboarded user. Active rows have a private auth binding; deleted rows become non-discoverable tombstones. |
| `friendships`   | One row per pair, canonically ordered `user_a < user_b`. `requested_by` carries direction. |
| `groups`        | Durable crews. Flat membership: no owner, no roles, no removing others. |
| `group_members` | Roster. Joining needs a code; leaving is a delete.           |
| `blocks`        | Directed. Readable only by the blocker.                      |

Three things are not reachable as table writes, because they cannot be expressed
as a row policy — RLS answers "may this caller read this row", not "does this
caller already know a secret":

```sql
select * from public.find_profile_by_handle('mikej');   -- exact match, never a search
select public.join_group_by_code('DEVCREW2');           -- idempotent, refuses across a block
select public.rotate_group_join_code('<group uuid>');   -- any member; the code is generated
```

Deliberate absences, each enforced by a withheld grant as well as a missing
policy (DECISIONS.md D21 and D81): no DELETE on `profiles` (the service-only
`delete_account()` transaction tombstones the durable actor and then removes
authentication), no DELETE on `groups` (the last member leaving reaps it), no
INSERT on `group_members` (that is `join_group_by_code`), and no UPDATE on
`groups.join_code` (that is `rotate_group_join_code`).

The seed builds a small graph — `@runner`, `@cyclist`, `@Lifter`, one accepted
friendship, one pending request, and a `Dev Crew` group whose join code is
`DEVCREW2` — plus M2's charities and one contest carrying three roster states at
once. To browse it as a particular user rather than as superuser:

```sql
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-1111-1111-111111111111"}', true);
select * from public.profiles;   -- now filtered as @runner sees it
```

## Dormant legacy contests (V2/regression)

M2's tables. All three have RLS enabled and no `anon` access.

| Table                  | Shape                                                        |
| ---------------------- | ------------------------------------------------------------ |
| `charities`            | Curated donation destinations. Read-only to clients; the list is maintained out of band. |
| `contests`             | The terms and the window. Frozen at creation, status forward-only, never deleted. |
| `contest_participants` | The roster and the invitation lifecycle in one table. Rows are never deleted. |

The product calls the invitation flow a **challenge**; the stable database and
RPC vocabulary remains **contest**. A two-person challenge is
`max_participants = 2`, while multi-friend creation closes the roster at the
creator plus the selected invitees, up to the existing 20-person contest cap.
`group_id` is an independent, optional scope that decides who may be invited
(DECISIONS.md D22 and D89).

### The participant state machine

```
                              ┌──► accepted ──► withdrawn
                              │    needs a       pending only,
                              │    timezone      never the author
   (author) ──► accepted      │    and a
                              │    charity
   (invited) ─────────────────┼──► declined
                              │
                              └──► lapsed
                                   system only: activation or cancellation
```

The author is enrolled as `accepted` when the contest is created. Once the
contest leaves `pending` the roster is frozen — no new participants, and no
status, charity, or base-timezone changes at all. That freeze is what makes
blocking an opponent useless as a way out of a contest you are losing (D29),
and it is why `lapsed` is a status no client can write (D31).

A genuine relocation does not loosen that trigger or rewrite the base zone.
M5 records a separate request, one immutable vote from every other accepted
participant, and an applied change only after unanimous approval. The server
chooses the effective instant. Old buckets keep their old zone; future buckets
use the new one; an hour cut by the transition belongs to neither epoch.

### What is not reachable as a table write

Five things, for the same reason M1's join-by-code is a function: they are not
properties of a row.

```sql
-- Creation writes two tables atomically, and the author's roster row needs a
-- timezone and a charity, neither of which is a column on `contests`.
select public.create_contest(
  p_title => 'Step Challenge', p_metric => 'steps', p_cadence => 'daily',
  p_target_value => 10000, p_stake_cents => 2500,
  p_starts_at => now() + interval '1 day',
  p_ends_at   => now() + interval '8 days',
  p_timezone => 'America/New_York', p_charity_id => '<charity uuid>',
  p_max_participants => 2);

-- Author only, pending only. Lapses every outstanding invitation.
select public.cancel_contest('<contest uuid>');

-- Cron's entry point: opens contests that have come due if two people accepted,
-- cancels the rest before opening. Not callable by `authenticated`,
-- deliberately — see D32.
select app.activate_due_contests();

-- Active accepted participants may request a prospective relocation. Every
-- other accepted participant must consent; retries of the same vote are safe.
select public.request_timezone_change('<contest uuid>', 'Asia/Kathmandu');
select public.review_timezone_change('<request uuid>', true);
```

Inviting and answering *are* plain table writes, because both are row
properties and so can be expressed as policies:

```sql
-- Author only, while pending, to a friend or a co-member of the contest's
-- group, and never across a block in either direction.
insert into public.contest_participants (contest_id, user_id, invited_by)
values ('<contest uuid>', '<invitee uuid>', '<author uuid>');

-- Answering. The charity is required to accept and the timezone freezes here.
update public.contest_participants
set status = 'accepted', timezone = 'Europe/London', charity_id = '<charity uuid>'
where contest_id = '<contest uuid>';
```

Deliberate absences, each enforced by a withheld grant as well as a missing
policy (D21, D24): no INSERT, UPDATE, or DELETE on `charities`; no INSERT on
`contests` (that is `create_contest()`); no UPDATE on `contests` at all, because
the terms are frozen and the status is not the client's to move; and no DELETE on
either `contests` or `contest_participants`, because a contest that happened is
evidence and withdrawal is a status rather than an erasure.

One rule worth knowing before you write a fixture: a participant other than the
author cannot be inserted already `accepted`. They arrive as `invited` and
answer, which is what the seed does — see the two-step insert in `seed.sql`.

### Charities are empty in production, on purpose

`seed.sql` populates three openly fictional charities for local development:
invented names, `00-000000N` EINs, and `.test` hosts, which RFC 2606 reserves so
they cannot resolve. The production list is an owner action against verified EINs
and is deliberately *not* shipped as a data migration — a plausible but wrong EIN
routes a real donation to the wrong organisation and looks correct doing it. See
DECISIONS.md D26, which also records why an empty table is the right failure mode
until then.

## Legacy notification outbox and model-aware activation

M7.2a adds `notification_intents`, an append-only ledger written by the same
transaction as its business transition. It stores only recipient, event type,
opaque entity ID, reminder stage, and server timestamps—never health totals,
location, receipts, integrity allegations, or dispute notes. Authenticated
users can read only their own intents while their profile is active;
`service_role` has read-only delivery access, and neither role can call the
trusted emitter. Delivery attempts, read state, APNs tokens, and presentation
remain M8 ledgers.

Invitations, contest activation/cancellation, account-deletion participation
changes, timezone-consent request/resolution, quarantine-review
request/approval, D76 escalation, and D76 terminal resolution emit semantic,
idempotent intents. Rejection is never mislabeled as resolution, and no intent
contains evidence values, integrity allegations, or an operator note.

The shared `pg_cron` registry contains named activation, raw-retention, and D76
deadline jobs. `gametime-activate-due-contests` and
`gametime-process-quarantine-review-deadlines` run every minute; raw retention
runs hourly. Application roles cannot use the `cron` schema. pgTAP proves each
registry entry and manually driven worker semantics. Only activation and
retention have the separately recorded hosted observations; this D76
implementation has not been deployed or observed against committed hosted rows.

## Dormant legacy standings, results, and obligations

M8.3c adds one service-only `publish_contest_standings_v1` boundary and one
accepted-participant `get_contest_standings_v1` read surface. The publisher
stores complete versioned snapshots. Final publication also freezes one
explicit `winner`, `all_donate`, `void`, or `inconclusive` result and creates
exactly one obligation per debtor in the same transaction: each loser points to
the winner's frozen charity, while every accepted participant in an
`all_donate` result points to their own nomination.

The read RPC never exposes the base ledgers directly. Provisional ordering is
live progress, not a predicted winner: the caller sees their own exact
integrity score, flags, and bounded rationale while rivals remain redacted.
Final rankings reveal the frozen inputs and attach an obligation only to the
row that owes it. Results, snapshots, entries, and obligations are append-only;
final publication waits for ingest grace, rejects unresolved quarantine, and
serializes against both metric and geofence writes. The product renders these
states in challenge detail with separate loading/error caches that clear on an
account transition.

This is still a dormant normal first-result foundation, not an enabled
winner/obligation finalizer. The local D76 timer can write only the fail-closed
`inconclusive:review_timeout` result from a matching frozen assessment and
creates no obligation. No hosted caller invokes the trusted publisher.
Operated adjudicator authorization/queues, disputes, actionability, settlement,
M6.5, deployment, and staging gates still apply.


## Geofence check-ins

`POST /functions/v1/ingest-checkin` is the M6 sidecar ingestion path. It uses the
same JWT ownership, App Attest key, exact-body signature, monotonic counter, and
stable client-id retry contract as metric ingest. The signed JSON contains an
explicit contest and geofence id, 2–256 raw Core Location observations, and one
workout interval:

- Every location carries an absolute RFC 3339 instant, latitude, longitude,
  horizontal accuracy, and Core Location's simulation/accessory signals.
- The workout carries an absolute half-open interval, activity type, HealthKit
  provenance, and optional source bundle id.
- `clientCheckInId` and the exact signed body bytes stay unchanged across a
  retry. An identical replay returns the first result; the same id with different
  bytes is refused.

The portable queue exposes a codable pending-request value and a validating
restore initializer, so an app relaunch preserves the exact bytes and retry id.
At capacity it refuses the new request visibly; it never evicts an older
Core Location claim that cannot be reconstructed later.

The client never declares that it was inside. `contest_geofences` is a
service-provisioned definition that must be inserted before activation and is
immutable thereafter. It contains the center, radius, accuracy ceiling, minimum
dwell, maximum sample gap, and minimum workout overlap.
`record_geofence_checkin()` orders the absolute instants, computes a Haversine
distance for each raw observation, and records one explicit sample
classification: `inside`, `outside`, `low_accuracy`, or `simulated`.

Credited dwell is the sum of adjacent `inside -> inside` intervals no longer
than the configured sample gap. Workout overlap is the intersection of the
workout with those credited intervals—not with the first-to-last visit envelope.
Both calculations are timezone-independent and use half-open ranges, so touching
endpoints do not overlap.

Every well-formed attempt that reaches Postgres is append-only, including failed
validation. Its primary outcome records whether it was accepted, outside the
contest window, future-dated, simulated, inaccurate, outside the fence, short on
dwell or workout overlap, backed by an untrusted workout, or conflicting with
already accepted visit/workout evidence. Only accepted attempts reserve time:
partial GiST exclusions prevent one user from accepting overlapping check-in or
workout ranges, and a partial unique index prevents accepting the same workout
id twice. A failed attempt therefore remains auditable without blocking a
corrected retry.

Check-ins never mutate `metric_snapshots`, `contest_evidence`, qualification, or
totals. `contest_checkin_integrity` feeds the versioned M6 integrity flags, while
`contest_location_observations` exposes only inside samples from accepted,
attested attempts to the existing impossible-travel rule. Neither timezone nor
HealthKit totals is treated as a location.

Exact coordinates are owner-only under RLS and remain available to the
service-role integrity assessor. Accepted active or finalized rivals can audit
the immutable geofence terms and derived check-in outcomes, but cannot inspect
another participant's raw, failed, or trusted coordinate rows.

## Legacy social scoring

`supabase/functions/_shared/scoring.ts` is the only implementation of who won
(DECISIONS.md D3). It is a pure function — contest terms, the accepted roster,
and the rows of `contest_evidence` in; standings and an outcome out. No I/O, no
clock, no randomness, so the same frozen input always gives the same answer. M7
persists the result and configuration versions before later retention may prune
raw evidence.

**A contest is pass/fail against its own terms, and the comparison is among those
who passed.** Highest score does not win. This is what the cadence enum already
says: `cumulative` means reach the target once across the window, `daily` means
reach it on every day. So:

| Qualifiers | Outcome |
| --- | --- |
| exactly one | that participant wins |
| several | a tie, resolved by `contests.tie_break` |
| none | void — nobody donates |

The case that settles it: two friends each pledge $25 against a 100,000-step
month and walk 40,000 and 12,000. Under "highest total wins" somebody who missed
their goal by 60% collects a donation for a month in which neither of them did
the thing they staked money on. See D51.

That makes **ties the ordinary result**, not an edge case — which is why
`tie_break` is declared at creation and defaults to `integrity_score`.

### Daily cadence rates days, it does not count them

A daily contest asks about the local days each timezone epoch *wholly* covers,
starting with the participant's frozen base zone, and ranks on
`qualifyingDays / scoreableDays`.

A window that is seven whole days in New York is six whole days plus two
part-days in Kathmandu (+05:45). Ranking on the raw count would cap the Kathmandu
participant at 6 against the New Yorker's 7 and make them unable to win a contest
they played perfectly. Rating makes them comparable: 6/6 and 7/7 are both 1.0.

Part-days are dropped from the numerator *and* the denominator — an 18-hour day
cannot be judged against a whole-day target. That also closes an attack the
ledger cannot: evidence in a part-day is legitimately writable, so otherwise
somebody who missed a Wednesday could stuff the edge day and manufacture a
qualifying day out of an hour that was never a day. See D52.

Every scoring call must supply the complete applied timezone-change ledger,
including an explicit empty array when there are no changes. Omitting it raises
instead of silently reverting a relocated participant to the base zone.

### Totals are integers underneath

Every value is `numeric(12, 2)`, so scoring converts to whole hundredths and sums
as integers. `28.45 + 1.24 + 0.20 + 0.11` is `29.999999999999996` in doubles, so
a participant logging exactly 30.00 minutes against a 30-minute target fails a
float comparison — and that comparison is the qualification test. See D53.

### An unresolvable tie is reported, not guessed

The bare M4 engine still reports `integrity_score_unavailable` when it is called
without scores. M5's `scoreContestWithIntegrity()` computes a complete score map
for every accepted participant and supplies it through the engine's existing
optional input. A unique highest score wins; equal scores remain explicitly
`tie_break_inconclusive`.

Every alternative is worse: falling back to the higher total substitutes a
tie-break the participants did not agree to, voiding cancels a contest somebody
won, and ordering by user id settles a donation by whose UUID sorts lower.
Standings *are* fully ordered — a leaderboard has to render — but ordering never
decides the outcome. See D54.

### The engine scores; it does not flag

90,000 steps in one hour scores as 90,000, and a bucket first reported eleven days
late scores too. Plausibility needs a tuning parameter, which makes it a heuristic,
which puts it in M5 (D6). The engine carries the aggregates M5 reads — bucket and
sample counts, the largest single hour, the worst reporting lag — rather than
acting on them. Both cases are fixtures that must *pass*, so nobody mistakes the
engine's silence for a verdict. See D55.

The one thing it refuses is a ledger that contradicts itself: a bucket carrying
two different `local_day` values raises rather than picking one.

### The corpus is the specification

`supabase/functions/_test/scoring_fixtures.ts` holds every case as plain data —
no functions, no classes. If optimistic offline standings ever force a second
engine in Swift, the two have to be held to one corpus, and a test asserts the
fixtures survive a JSON round trip so they cannot quietly stop being portable
(D3's escape hatch).

Each fixture carries a `why` explaining what it pins, so changing an expectation
means saying which property is being given up. The fraudulent cases come in two
kinds, and the split is the point: cross-metric padding, out-of-window backfill
and part-day stuffing must **not** work; an implausible hour and an eleven-day-late
report must work, and be visible in the summary.

The corpus also crosses the date line: the same civil date can be one whole day
in each of two timezone epochs, and those days must never be merged.

## Integrity assessment

`supabase/functions/_shared/integrity.ts` is a pure sidecar to the M4 engine. Its
configuration has a version, per-metric hourly ceilings, corroboration rules,
reviewed third-party bundle identifiers and reputation tiers, timezone-change
penalties, geofence/workout validation penalties, travel distance/speed limits,
lag and quarantine thresholds, severity, points per flag, and per-rule penalty
caps. The current configuration is `m6-v1`; the exact `m5-v2` and `m5-v3`
configurations remain loadable for reproducible historical assessment. The
default score starts at 100 and floors at 0, but those are configuration too.

The assessor emits explicit flags:

| Flag | Signal |
| --- | --- |
| `plausibility_ceiling` | One hourly metric exceeds its configured ceiling. |
| `cross_metric_corroboration` | A large contest-metric hour has none of its configured companion signals. |
| `third_party_source_reputation` | An admissible third-party contribution has an unrecognized, missing, or malformed bundle identifier. |
| `timezone_change` | An opponent-approved prospective timezone epoch was applied. |
| `geofence_checkin_failure` | An attested check-in failed a location, contest-window, dwell, or visit-overlap validation. |
| `workout_overlap_validation` | A check-in failed workout trust, temporal overlap, reuse, or workout-range overlap validation. |
| `impossible_travel` | Two trusted location observations require travel above the configured speed after subtracting both accuracy radii. |
| `reporting_lag` | An hour arrived materially after it closed. |
| `retroactive_evidence_quarantine` | The lag crosses the review-required threshold. |

Impossible travel takes explicit location observations; hourly HealthKit totals
and timezone changes do not contain a location, and the code does not pretend
otherwise. M6's accepted, attested geofence locations are the concrete producer.

Flags never alter totals or qualification. A retroactive quarantine is durable
review state beside the snapshot: the generated `is_admissible` value stays the
same and `contest_evidence` still returns the value. In a duel, the opponent must
approve; in a group, a strict majority of the other accepted participants must.
Silence stays `pending`. M7 must block a settlement-bearing result until a
complete integrity assessment exists and every quarantine is approved or
explicitly cleared. Pending review and rejection without clearance follow D76's
bounded escalation path to `inconclusive`; neither quietly applies a second
evidence filter.

D76 stores one immutable 72-hour peer-review deadline no earlier than
ingest-grace close. A rejection escalates immediately; unanswered peer review
escalates at the inclusive boundary. Adjudication gets one bounded seven-day
deadline anchored no earlier than grace close. Only the service mutation
boundary can record explicit clearance, using an idempotency key. If no
clearance wins before the deadline, the named worker appends `review_timeout`,
reuses the frozen assessment standings, finalizes only as `inconclusive`, and
creates no donation obligation. The peer vote, escalation, terminal event, and
payload-free intents remain append-only through participant tombstoning.

Raw `ingest_batches`, `metric_snapshots`, and `evidence_quarantines` are readable
only by their subject; quarantine vote rows are readable only by the reviewer
who cast them. Accepted rivals use `list_contest_quarantine_reviews(contest_id)`
and `get_quarantine_revision_history(quarantine_id)`, which bind authorization
to the evidence row's own contest, disclose only a pending claim that caller
still must judge, and omit device/source identifiers, attestation material,
arbitrary details, signal keys, and reviewer identities. The subject gets
aggregate review state through `list_my_evidence_quarantines(contest_id)`.

Timezone consent is deliberately stricter than quarantine review because it
changes the scoring contract rather than judging one claim: every other accepted
participant must approve. Scoring computes whole days separately inside each
approved epoch, and both the server and client drop transition-cut hours.

