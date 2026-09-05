# Phase 2(c) — local simulated duel lifecycle

September 5, 2026. Phase 2(c) is implemented and accepted locally. It adds
operational persistence around the unchanged Phase 2(a) evaluator and Phase 2(b)
private proof boundary. Phase 2 remains open for native results, notices and
review interaction (d), then new-consent rematches and links (e).

No hosted migration, schedule, HTTP handler, push/email delivery, organizer
integration, native change, provider call or live money was enabled.

## Implemented boundary

The forward migration is
[20260905053951_duel_lifecycle_v1.sql](../supabase/migrations/20260905053951_duel_lifecycle_v1.sql).
All new ledgers are private in `app`, with RLS, explicit privilege revocation
and owner-checked append-only guards. The separate lifecycle gate defaults to
false; gate changes retain server authority and timestamps.

| Operation | Boundary |
| --- | --- |
| Activation / expiry | Service loads an explicit duel; records activation once or expires an overdue unaccepted invitation |
| Snapshot / commit | Service-only complete snapshot and optimistic commit; database time sampled after locks |
| Durable notice | One immutable row per runner and proof revision, committed together; no external delivery |
| Participant case | Active session, named runner, own noticed revision and exclusive filing deadline; one case per runner/revision |
| Independent resolution | Active session and current per-duel reviewer grant; append uphold or void before review/cap deadline |
| Safe exit | Named active participant withdraws or reports injury; service can record event cancellation |
| Final result | Immutable scorer version, agreement digest and proof revision; retained input digest |
| Simulated settlement | Separate idempotent append after final result; 4,000 nonredeemable simulated cents conserved, zero fee |
| Post-final correction | Authorized independent reviewer submits a bounded fictional document into separate audited support intake |
| Participant read | Own notices/cases and redacted final result; no bibs, source documents, private proof or reviewer identity |
| Operator case read | Fresh independent per-duel grant; no participant access |

Case filing and safe exits remain available when admission is disabled. Exact
requests retain their original receipt and reject changed payloads. Resolution
and support recovery recheck current reviewer authorization, including revocation
and active sessions. Support intake remains available with gates off, including
after the hard cap, but never appends scoring proof, changes a final result or
creates another settlement.

Blocked pairs cannot read opponent outcomes or notices through the new
projection. An active named actor can recover their own case and simulated
return receipt and exit safely. Deleted callers and unrelated actors are denied.
Blocking alone never creates a result. Participant deletion is an explicit
closure fact. Reviewer deletion removes future access without rewriting
already admitted proof.

## Compatibility and ordering

Phase 1 agreement status remains its historical consent/exit receipt.
Activation, notices and finality are separate records. Consumers must use the
new lifecycle read for operational state; scheduled in the old agreement
receipt does not mean a finalized duel is still awaiting its event.

The migration preserves the Phase 1 aggregate check except that a persisted
final result also permits releasing enrollment. Proof and notices retain both
slots. A committed final releases remaining slots in the same transaction.
Historical pre-start cancellation/expiry preserves its existing slot behavior.
New legacy cancellation requests cannot change an operationally closed/final
duel; exact earlier requests retain recovery. Account deletion remains possible
after early finality.

New operations lock the actor pair, plus reviewer where needed, in UUID order,
then challenge, then the relevant gate. Deletion owns the deleted actor before
challenges and never acquires the opponent afterward. A finality-aware insert
guard blocks new sources and revisions after operational closure/final result;
committed proof retries retain their existing authorization boundary.

The private loader includes both consents, all proof revisions, notice times,
cases and resolutions, the earliest authorized closure/deletion fact and any
persisted final result. Commit compares that complete input under the same
locks. Corrections, notices, cases, resolutions, exits, deletion and another
final result make old input stale. Crossing an event, cutoff, notice/review
deadline or hard-cap boundary outside the database also forces reevaluation.
PostgreSQL microseconds are retained.

The service-only commit trusts the authorized worker to run the versioned
scorer. It validates the binding and bounded outcome shape; it does not duplicate
the scorer in SQL. Participants and reviewers cannot commit worker decisions,
load private snapshots, choose clocks or insert ledger rows. The operational
adapter uses separate RPC transactions around evaluation.

## Worker and local operation

[worker.ts](../supabase/functions/duel-lifecycle/worker.ts) loads, evaluates,
commits and separately settles a final result. Stale input causes a fresh load,
bounded to four attempts. An interruption after final commit is recovered by
rerunning the worker. Notice retries preserve their original timestamps.

The database owns the clock. Private `_at_v1` functions inject test time; public
wrappers expose no timestamp parameter. Corrections get fresh notices and seven
full elapsed days. Missing proof gets notices only at cutoff. The unchanged
scorer handles reviews, timeouts, safe exits and the hard cap, including delayed
workers and insufficient correction windows. Persisted finals remain authoritative.

The adapter in [database.ts](../supabase/functions/duel-lifecycle/database.ts)
refuses non-loopback endpoints. The manual
[local runner](../scripts/duel-lifecycle-local-worker.ts) accepts 1–100 explicit
fictional duel UUIDs, deduplicates them and exits nonzero on a failed/stale run.
With the local service key in `DUEL_LOCAL_SERVICE_ROLE_KEY` and the lifecycle
gate deliberately enabled:

```sh
deno run --config supabase/functions/deno.json \
  --allow-env=DUEL_LOCAL_URL,DUEL_LOCAL_SERVICE_ROLE_KEY \
  --allow-net=127.0.0.1:54321 \
  scripts/duel-lifecycle-local-worker.ts <fictional-duel-uuid>
```

`DUEL_LOCAL_URL` defaults to `http://127.0.0.1:54321`. Agreement admission,
proof ingestion and lifecycle execution have separate controls. Close them
after a local exercise. The runner registers no schedule or automatic scan.

## Verification

Run against the disposable local stack:

```sh
supabase test db --local \
  supabase/tests/464_duel_lifecycle.test.sql \
  supabase/tests/465_duel_lifecycle_concurrency.test.sql
deno run --allow-run=psql --allow-read=scripts/examples \
  scripts/duel-lifecycle-local-smoke.ts
./scripts/test-all.sh
supabase db lint --local --schema public,app --level warning
supabase db advisors --local --type all --level warn
supabase migration list --local
```

| Check | Result |
| --- | --- |
| Focused lifecycle SQL | 220 boundary/access assertions passed |
| Independent-session races | 22 assertions passed; eight races demonstrated blocking with pg_blocking_pids |
| Persisted SQL → real scorer → worker smoke | Passed: full windows, correction, review, timeout, exits, expiry, blocking, deletion and support |
| Final / settlement interruption recovery | Passed: final persists first, rerun appends settlement, both reject edits |
| Full portable gate | Passed from a clean local migration reset |
| Full database regression | 56 files / 2,582 assertions passed |
| Deno format, lint, type check and full tests | Passed; 568 tests |
| Portable Swift | Passed; 103 tests in nine suites |
| Local lint and warning/error advisors | No schema errors or issues |
| Migration history | New migration replayed and recorded locally |
| Runner and smoke scripts | Format, lint and type checks passed |

Persisted fixtures cover wins, ties, one/both nonfinishes, missing results,
wrong bib, winner-changing correction, upheld/void/timed-out cases, injury,
withdrawal, event cancellation and no-notice hard-cap voids. Checks include
microsecond cutoff crossing, the full corrected window, slot release, simulated
value conservation, reruns, post-final proof rejection, redaction and support.

Concurrent tests cover notice/notice, exit/worker, deletion/worker, case/worker,
final/final, correction/worker, resolution/worker and final/correction. The
coordinator does not hold competing actors' locks. Committed fictional records
are scoped and cleaned up; actual gate audit events are retained. The smoke is
one rollback-only test transaction, distinct from the operational adapter's
transaction model. All three gates finish off.

Supabase CLI 2.109.1, the current changelog, official
[function guidance](https://supabase.com/docs/guides/database/functions) and
[RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security)
were checked. No dependency, platform upgrade or exposed-schema change was
needed. This is SQL role/session and local worker acceptance, not authenticated
HTTP operator-console, human race-review or native UI acceptance. No Xcode or
physical-device run was needed because native source did not change.

## Phase 2(d) handoff

Add actor-bound native progress, notices, final results and participant review
interaction using `get_duel_lifecycle_v1`, `file_duel_review_v1` and `exit_duel_v1`.
Preserve explicit simulation language, deadline precision, account-switch
isolation, request recovery and blocked-contact suppression. Each correction
has a new notice; earlier notices and cases remain history.

Independent operator tooling has separate case-read and resolution RPCs.
Database reason codes need plain-language mappings under `docs/COPY.md`, never
raw on-screen identifiers. Push delivery cannot substitute for durable in-app
notice creation. Native rendering and accessibility remain unverified.

Phase 2(e) still requires new consent for rematches and target-bound links.
Real organizer proof, independent human operations, retention policy, hosted
rollout, scheduled execution and live money remain separate future gates.
