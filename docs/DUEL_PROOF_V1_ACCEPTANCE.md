# Phase 2(b) — private fictional proof and independent operator review

September 5, 2026. Phase 2(b) is implemented and verified locally. Phase 2 as a
whole remains in progress; the next slice is **2(c), operational result processing**.
This builds on the [pure evaluator](DUEL_SCORING_V1_ACCEPTANCE.md) without changing
its contract or any Phase 1 agreement, consent, Personal/Solo/charity record, or
native source. Hosted state, Release routing and live money remain unchanged.

## Delivered

- [Forward migration](../supabase/migrations/20260905041315_duel_proof_review_v1.sql):
  a separate default-off proof gate, append-only per-duel reviewer grants and
  revocations, private captured sources, full-pair proof revisions, and raw-read
  and gate-control audit records. No operator or source is seeded.
- [Database tests](../supabase/tests/462_duel_proof.test.sql): access/grant matrix,
  active sessions, immutable source/request identity, bib validation, complete
  pairs, correction history, exact deadlines, blocks and deleted actors.
- [Concurrency tests](../supabase/tests/463_duel_proof_concurrency.test.sql): real
  independent PostgreSQL transactions, with actual lock waits observed through
  `pg_blocking_pids`; no timing-only guess that the competing call was blocked.
- [SQL-to-Deno smoke](../scripts/duel-proof-local-smoke.ts), using the
  [rollback-only example](../scripts/examples/duel-proof.sql), passes persisted
  proof through the existing pure evaluator. An official correction changes the
  provisional winner while retaining the original proof. Nothing publishes a result.

## Authorization and storage contract

All five new tables live in private `app`, have RLS enabled with no client
policies, and revoke every table privilege from `PUBLIC`, `anon`, `authenticated`
and `service_role`. Explicit RPC grants provide the only API paths. Helpers and
clock seams have no API grants. Definers use an empty search path and perform
authorization inside the boundary. Owner-checked write triggers prohibit direct
API writes even if a custom write setting is spoofed; update, delete and truncate
of retained proof/audit history are also forbidden to ordinary owner operations.

| Boundary | Caller and behavior |
| --- | --- |
| `set_duel_proof_enabled_v1` | Service control; default false; every enable/disable is audited |
| `set_duel_proof_reviewer_v1` | Service assigns/revokes one reviewer for one accepted duel; each exact request is retained; neither runner may be assigned |
| `capture_duel_proof_fixture_v1` | Service captures an immutable, bounded fictional document for one agreed event and both named runners |
| `get_duel_proof_source_v1` | Active assigned reviewer reads one source under that duel; access is audited against the effective grant |
| `submit_duel_proof_v1` | Active assigned reviewer submits a request ID, source ID, expected predecessor, and exactly two identity verdicts; database appends the full pair |
| `get_duel_proof_status_v1` | Active named participant gets only `challengeId`, `termsDigest`, `proofRevision`, `recordedAt` |

Review authorization comes from the latest server-owned grant event, not JWT
metadata. Operator identity comes from `auth.uid()`. New reviewer and participant
RPCs also require a matching extant `auth.sessions` record whose `not_after` has
not passed. Existing Phase 1 session behavior is unchanged. Grant revocation
denies subsequent reads and writes, including exact receipt recovery. Replaying
the old grant request returns its old audit ID without granting access again.

Both runners must remain active and unblocked for new proof access. A reviewer
blocked by either runner is also refused. Participant deletion or reviewer
deletion prevents new private access while retaining already committed proof
and grants against durable profile identities. Service revocation remains
available after deletion, blocking and gate-off. Blocking does not itself create
an outcome. Phase 1 agreement receipts retain their existing historical access
contract; this slice adds no raw data to those reads.

The source document has fixed keys for event/course/wave, distance, timing basis,
precision, and two rows containing actor, mapped/published fictional bib, status
and chip seconds. Extra fields are rejected; payload size is capped at 8 KiB.
The event and named actors must match the agreement. Expected bibs cannot be
duplicated. Missing/ambiguous states and incompatible source facts can remain
unresolved; neither missing data nor an identity verdict declares a loss.

A reviewer cannot confirm a missing/ambiguous identity, mismatched bib, or
duplicated published bib. They cannot replace source times or bib mappings,
choose a different reviewer, backdate receipt/retrieval, or submit a source URL.
The database derives the normalized evaluator records, synthetic `fixture://`
reference, canonical JSONB SHA-256 content digest, receipt time and authority.
The digest identifies captured canonical JSON, not original bytes or an
authenticated organizer. There is no network retrieval or human-source adapter.

Source capture by a privileged fixture curator is not independent verification
of a real runner. Only fictional local actors/events are supported here. A human
pilot still requires organizer permission, an independently operated identity
review process, support staffing and a reviewed retention policy. These new
private tables are not attached to old metric/route purge jobs; no production
retention duration is implied by retaining fictional audit history.

## Ordering, identity and deadlines

All proof operations lock the union of the pair and reviewer profiles in UUID
order before locking the challenge and, for new ingestion, the proof gate.
Role changes use the same order. Account deletion retains its existing
actor-then-challenge order and never acquires the opponent after the challenge.
This serializes proof selection, role revocation and participant/reviewer
deletion without introducing a challenge-first lock path.

The expected predecessor must match the latest committed revision. Revision
one has no predecessor; subsequent revisions increment exactly once and carry
the entire pair. Unique and foreign-key constraints retain the chain and its
source/grant binding. Receipt timestamps preserve PostgreSQL microseconds and
cannot go backward. Reusing a reviewer request with changed source, duel,
predecessor or verdicts fails. An exact retry returns its original revision,
even after later corrections, cutoff or gate-off, while authorization remains
valid. Verdict array ordering is part of exact JSON request identity.

Initial reviewed proof must arrive strictly before event end + 72 hours;
corrections require an admitted first revision and arrive strictly before
event end + 720 hours. Receipt is sampled after potentially blocking locks.
Capturing a source earlier does not backdate a later review. The public wrappers
expose no clock argument. Private test seams prove the last microsecond and
equality boundaries; public calls prove waits across both cutoff and hard cap.

This slice refuses new proof at/after the hard cap. It does not yet offer a
post-final support intake or decide finality. The next worker slice must add
those deliberately and prevent post-final corrections from changing results.

## Verification

Run from the repository root with the local stack running:

```sh
supabase test db --local supabase/tests/462_duel_proof.test.sql supabase/tests/463_duel_proof_concurrency.test.sql
deno run --allow-run=psql scripts/duel-proof-local-smoke.ts
./scripts/test-all.sh
supabase db lint --local --schema public,app --level warning
supabase db advisors --local --type all --level warn
supabase migration list --local
```

| Check | Result |
| --- | --- |
| Focused proof SQL suites | 254 assertions passed: 210 boundary checks and 44 concurrency checks |
| Full portable integration gate | Passed from a clean local migration reset |
| Full pgTAP regression suite | 54 files / 2,340 assertions passed |
| Functions format, lint, type check and full Deno suite | Passed; 563 tests |
| Portable Swift build/tests | Passed; 103 tests / 9 suites |
| SQL-to-evaluator smoke | Initial and corrected persisted snapshots passed; participant projection checked; all fixture rows and gate changes rolled back |
| Smoke script format/lint/type check | Passed |
| Local database function lint | No schema errors |
| Local security/performance advisors, warning/error level | No issues |

The CLI-created migration was iterated locally through SQL without recording
intermediate migration history, then replayed by the clean reset. Supabase CLI
2.109.1 help, changelog and current
[RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security),
[function guidance](https://supabase.com/docs/guides/database/functions) and
[explicit API grants change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
were checked. No platform upgrade, exposed schema, dependency or lockfile change
was necessary. Concurrency fixtures clean up their scoped fictional records;
actual service gate-change audit events remain retained and both gates finish off.

SQL role/session fixtures exercise the database authorization boundary; this is
not an authenticated HTTP/operator-console or human-review acceptance claim.
No Xcode run was needed because no native source changed. Hosted, physical-device,
real-race, notification and monetary behavior were not exercised or enabled.

## Next slice: Phase 2(c)

Follow-up, September 5: [Phase 2(c) is now accepted locally](DUEL_LIFECYCLE_V1_ACCEPTANCE.md).
The original handoff below is retained; native slice (d) is next.

Implement a clock-injected operational service for accepted-duel activation,
unaccepted-invitation expiry, cutoff/provisional evaluation, durable in-app
notices, participant review cases and independent resolutions, safe exits,
finality, and separate nonredeemable simulated settlement events. Add new
forward migrations and isolated functions; preserve the existing agreements
and scorer version.

Use `app.duel_proof_history_v1` only inside a private, complete snapshot loader.
It projects proof alone and intentionally does not manufacture empty notices,
reviews, closure or final-result ledgers. Lock actors in the same UUID order,
then challenge, and verify the evaluated snapshot is still current before
commit. A revision alone is insufficient: concurrent notices, case resolutions,
deletion, closure and an existing final result must also be checked. Do not
hold a database transaction open across arbitrary external work.

Durable notices must bind to the exact provisional revision for both runners;
corrections require new notices and seven full elapsed days. Add participant
case filing and independent case decisions as separate append-only records,
with exact request recovery and fresh role checks. Use account-deletion facts
and safe-exit events explicitly without turning blocking into a loss. Resolve
timeouts and the hard cap with the evaluator's current rules.

Final result and simulated settlement must be separate immutable appends. Never
release a participation slot on a proof receipt or pure evaluator decision.
Add a separate audited post-final correction/support path that cannot change
the persisted outcome automatically, and make proof admission aware of persisted
finality before exposing any worker. Test worker reruns, correction/notice/case/
finalization races, deleted/blocked access, full windows and simulated-value
conservation. No hosted schedule or notification deployment is authorized.
Native progress/results and new-consent rematches remain slices (d/e).
