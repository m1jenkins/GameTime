# Prompt 5 — bounded queries, local completion

P5 is implemented and locally verified. This is a local result, not a product-main
merge or release/capacity acceptance. P6 was not started. No native source changed.
No push, deployment, distribution, real Health access, money enablement or
user-data deletion occurred.

## Exact source and ownership

| Identity | Commit / location |
| --- | --- |
| Requested completed P4 base | `369e7b90dfeb74314244a923a87864e368348412` |
| Tested P5 implementation, SQL tests and race runner | `e0a94bd793e4720ae04795760d614b049005618b` |
| Dedicated branch | `codex/bounded-queries-p5` |
| Dedicated clone | `/private/tmp/gametime-p5-20260911/GameTime` |
| Raw evidence / disposable stack | `/private/tmp/gametime-p5-20260911` / `stack` |
| Preserved P4 checkout | `/private/tmp/gametime-simplify-20260911-byc27c1u/GameTime`, still `369e7b9` and clean |
| Unchanged accepted product main | `affd367ebe5411969fd5b7abd45629e0746a5a7d` |
| Preserved original dirty checkout | `/Users/user/Documents/GitHub/GameTime`, still `577bc321e72750976e2e8027680387707070b0e3` |

Before starting, the P4 checkout matched the requested clean branch/HEAD, product
main had no newer accepted work, and the app task inventory showed no other active
P5 task. Existing retained branches were inspected and left intact. The dedicated
clone preserves the original P4 branch, dirty original, and other resources.
The following documentation/evidence commit changes no tested implementation.

There is one forward migration:
`20260911235041_challenge_bounded_queries_v1.sql`. All original 74 migration files
are byte-identical to the P4 input. All 75 final migration hashes matched the
executed disposable-stack files: [hashes](p5-20260911/migration-hashes.json).
The P2 [capacity report](../../docs/load/capacity-report.md) and P4
[completion report](2026-09-11-p4-completion.md) are unchanged.

## Changed behavior

History has a private ordering projection with the same existing sort:
`coalesce(final.recorded_at, ends_at) DESC, starts_at, id`. New pages use indexed
keyset ranges and read at most 50 rows plus one lookahead. Cursor storage holds
zero history IDs. Ordering metadata contains no copied social/Health payload.

New cursors remain actor/section-bound and expire after two minutes. **If an entry,
exit or late final changes that actor's history membership/order, continuing the
cursor returns `challenge_page_expired` and requires a fresh first page.** This
explicit stale-cursor behavior prevents silent duplicates or omissions. Old offset
snapshots remain usable through their original lifetime. Other sections retain
existing ordering snapshots. Each projected row rechecks current ownership and
privacy; sessions are validated before the page and immediately before response,
including wall-clock expiry during slow generation. The native client already
passes opaque JSON cursors and needs no change.

Discovery now filters terminal history through a partial live-lobby index,
materializes distinct live actors before availability checks, and joins directed
block edges instead of calling safety helpers for every roster pair. Completion
still uses the original single-item oracle. Claims, leases, retries, revocation,
consent, review deadlines, safe exits and immutable receipts keep their P4 behavior.
Status captures one time bound and indexes the recent receipt range, retaining
historical failure counts. No scheduled-work cache or new queue was introduced.

**Discovery still examines the eligible live inventory once per batch/status
call.** Exact global counts and immediate account/block safety remain linear in
live challenges and selected members. This removes measured repeated projections
and historical scans; it does not promise constant-time discovery at arbitrary
scale. Unbounded IDs in other section snapshots were not changed without a
comparable dense-workload finding. Standalone detail already uses indexed lookups
and showed no meaningful regression or need for broader changes.

## Identical before/after measurements

PostgreSQL 17.6, arm64, local Docker, Supabase CLI 2.109.1; shared host. The owned
project is `gametime-p5-20260911`, ports 5962x, network `10.253.215.0/24`.
Existing projects, networks and volumes were not reused/reset. The fixture uses
2,000 deterministic fictional accounts, 400 P2 histories across all 13 policies
with 120 fact revisions, 10,000 additional cancelled histories for one actor,
1,000 six-member live drafts (20 due), and 100,001 worker receipts (100,000 old).
These are constrained fictional snapshots, not a completed public lifecycle or
hosted acceptance. P2's fixture constructor/terms were reused; its original
harness and fixed-parent guard were not modified.

Each query has one first capture and six subsequent cache-warm captures in fresh
SQL connections, using `EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)` inside
rollback transactions. Reported latency is server execution, excluding connection
and network time. Small-sample p95 is the largest of six samples; neither it nor
the median is an SLO or maximum-throughput claim.

| Query | P4 median / p95 ms | P5 median / p95 ms | P4 → P5 last-capture shared hits |
| --- | ---: | ---: | ---: |
| History first page, 50 rows | 21.698 / 22.078 | 11.396 / 11.986 | 27,312 → 5,093 |
| Home active | 3.158 / 7.407 | 2.873 / 2.989 | 2,555 → 2,035 |
| Home upcoming | 10.403 / 10.715 | 9.365 / 10.587 | 5,164 → 4,408 |
| Home action | 3.433 / 3.721 | 2.672 / 2.720 | 2,561 → 2,044 |
| Standalone detail | 3.218 / 3.335 | 3.094 / 3.408 | 2,266 → 2,310 |
| Discovery inventory | 301.434 / 309.585 | 10.116 / 10.422 | 115,163 → 13,280 |
| Operations status | 420.737 / 439.341 | 11.839 / 12.123 | 218,764 → 14,091 |
| Claim batch, 20 rows | 335.444 / 339.722 | 13.733 / 13.895 | 117,155 → 15,287 |
| Recent failure receipt fragment | 3.378 / 3.549 | 0.028 / 0.030 | 1,820 → 3 |

All listed last captures had zero shared reads; this is not cold-cache evidence.
History median fell 47.5%, discovery 96.6%, status 97.2%, and claim batch 95.9%.
The old full-ID aggregate remains about 9 ms when deliberately queried directly;
it is no longer used for new history pages. This distinguishes changed query
shape from a hardware/cache-only speedup.

[Before](p5-20260911/before-final/summary.json) and
[after](p5-20260911/after-final/summary.json) summaries have raw plans alongside
them. Exact [result comparisons](p5-20260911/equivalence.json) matched all 1,000
work items, all 10,025 ordered history IDs, and 50 complete detail projections.
The [full dense chain](p5-20260911/deep-final/dense-chain.json) returned all 10,025
histories exactly once, in the original order, with zero stored cursor IDs.

The original plan sorted/joined the complete 10,025-row history before projecting
50 rows. Final [generic first-page](p5-20260911/deep-final/first-generic.json) and
[deep-page](p5-20260911/deep-final/deep-generic.json) inner plans use index ranges,
including at offset 9,950's equivalent key: 0.133/0.171 ms, 4/8 shared hits. The
production cursor uses no OFFSET; that offset only selects a benchmark boundary.
The [final discovery inner plan](p5-20260911/deep-final/work-inner-final.json)
shows the materialized actor set and set joins. An early rewrite let PostgreSQL
push the availability predicate below DISTINCT (still 216 ms); explicitly
materializing distinct actors reduced it to about 12 ms before indexes.

## Measured index and write cost

Only three secondary indexes were added. The index-free candidate versus indexed
candidate reduced history-page median 13.69→11.56 ms, discovery 10.58→9.87 ms,
and the isolated recent-receipt fragment 3.22→0.029 ms. Those exploratory query
runs preceded the final session/trigger corrections; the final table above is
the final-source result. Existing latest-fact/request/session indexes were kept.

| New index | Observed bytes after measurement writes |
| --- | ---: |
| History actor/order | 770,048 |
| Partial live creator/lobby | 180,224 |
| Worker receipt timestamp | 753,664 |
| **Secondary-index total** | **1,703,936** |

The two new ordering-metadata primary indexes add 786,432 bytes; their table main
forks add 901,120 bytes. All listed new relation main forks total 3,391,488 bytes.
These are actual [post-measurement sizes](p5-20260911/deep-final/storage.json),
including rolled-back benchmark allocation/bloat, not a compact steady-state or
retention forecast. Old data and receipts were not deleted.

Write comparisons remove only P5 indexes/history triggers **within a rolled-back
transaction**, then compare the same inserts with final P5 maintenance enabled.
Existing guards stay active. Five measured samples follow a first sample. Total
WAL uses same-transaction LSN differences and includes trigger writes; EXPLAIN
node WAL alone omitted those effects and was not used as total write cost.

| Fixture write | Without → with P5 median ms | Without → with P5 median WAL bytes |
| --- | ---: | ---: |
| 1,000 worker receipts | 7.153 → 7.937 | 249,144 → 314,624 |
| 100 live lobbies, including durable claim seeding | 4.176 → 4.541 | 57,432 → 74,160 |
| 100 new history memberships | 1.520 → 5.384 | 25,056 → 76,264 |

[Full write plans and transaction WAL](p5-20260911/write-total-final/) retain all
samples. A review caught a quadratic whole-roster member trigger. Restricting it
to the changed member reduced a 250-member exit update from 242–264 ms to 19–20 ms,
retaining all 250 history rows. This is a fixture maintenance check, not P6 product
work. Lobby/final ordering changes still update their affected roster.

## Final-source checks and review

| Check | Actual result |
| --- | --- |
| Fresh migrations | All 75 applied successfully; same source used for clean SQL suite. |
| Full portable SQL suite | **88 files, 3,998 assertions passed, zero skips.** Shared projection helper justified one full pass. |
| New P5 SQL file | **40 assertions**, included in the full pass: boundaries, ties, changed limits, retry, stale/malformed/expired/cross-account cursors, private helpers, block redaction, session revocation, and safety-discovery equivalence. |
| Actual P4 concurrent sessions | **48 checks passed twice** on final P5 source, including scoped admission/revocation, exact retries, claims, recovery, cancellation and fixture 249/250/251 capacity. |
| Actual P5 concurrent sessions | **5 checks passed twice**: expiry during both page paths, cancellation proceeding during a waiting read, stale in-flight page rejection, and fresh-page recovery. |
| Final P4-data → P5 upgrade | **194 assertions passed**: all 188 preexisting app/public table digests unchanged (excluding the new nullable cursor metadata field), historical weekly/Beta agreements, exact old receipt/failures, complete history backfill and an actual pre-upgrade offset cursor. |
| Direct PostgreSQL PL/pgSQL checker | **0 errors, 18 warnings, zero checker failures** across non-trigger app/public PL/pgSQL functions. |
| Static/source | Python parse, diff whitespace, original migration identities and executed final hashes passed. |
| Native | Not run: no native changes. |

One [concise read-only review](p5-20260911/review.md) covered correctness, efficiency,
reuse and clarity. Main-agent fixes closed the member-trigger and page-expiry
findings; final-source SQL/races and write measurements include them. Valid JSONB
literal-initialization warnings remain among the checker warnings; no checker
error was hidden or marked passed.

The [evidence README](p5-20260911/README.md) lists scripts and command receipts.
All correctness checks above ran after the final implementation edits. The
original P2 unit suite and its fixed-parent migration-guard context failure were
not changed or reclassified; P4 retains their historical dispositions.

## Preserved failures and remaining limitations

- **CLI advisors and CLI lint remain blocked** by `LegacyDbConnectError` using the
  explicit `127.0.0.1:59622` URL. Each was attempted once here; the generic CLI
  message says “remote” despite that loopback argument. The direct checker
  succeeded, but is not evidence that advisors/CLI lint ran. No hosted call ran.
- Early owned attempts are retained: a measurement started before fixture commit
  and hit the closed fixture gate; an output-comparison query correctly hit table
  permissions; the first member-trigger dispatch failed on a table-specific
  record field; the first race harness buffered its completion marker and timed
  out. Product/harness fixes and corrected final runs are separately identified.
  Initial port-probe sandbox and overlapping-network setup errors were resolved
  using authorized local access and an inspected unused subnet.
- P2's strict worker deadline miss by **4.388542 ms**, **14** join-storm disconnects
  at its original 100-member cap, and **15** failures / **10,039** unoffered arrivals
  in the 25k attempt remain failures. Its **123,500** cancelled-work entries and
  P4's historical limitations remain recorded. No short result erases them.
- No two-hour soak, new HTTP/gateway saturation or throughput/lock-residence
  characterization, 25k run, shadow-schema diff, hosted advisors, native build,
  release matrix, physical Health or human acceptance ran. P4's measured lock
  results remain historical. The actual-session tests here prove specific locking
  behavior, not general absence of contention. Hosted capacity remains unaccepted.
- Live discovery, non-history snapshots, receipt/ordering retention and community
  disclosure/moderation work retain the limits described above or in P4/P2.
  No history was deleted or partitioned; P6 remains separate and unstarted.

All challenge gates were false before stopping only the task-owned P5 stack with
backups retained. Other containers/networks/volumes were left intact. The shutdown
and exact database identity are recorded alongside this report. Continue only
with the next explicitly requested prompt from this committed P5 result.
