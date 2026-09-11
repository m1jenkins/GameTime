# Prompt 4 — local completion

Prompt 4 is implemented and locally verified on `codex/lean-beta-preparation`.
This completes the preserved partial implementation; it does not accept the
earlier incomplete report or move the product checkout. Prompt 5 and Prompt 6
were not started. No push, deployment, distribution, real Health access, money
enablement or user-data deletion occurred.

## Source and ownership

| Identity | Exact commit / location |
| --- | --- |
| Unchanged product used for comparison | `affd367ebe5411969fd5b7abd45629e0746a5a7d` |
| Task input, including preserved P4 and runner cleanup | `201d7459bad293c9f942de067c1b6afd99b58479` |
| Completed implementation and tests | `b67776c8b3fc1173f4e7f44bd794db9f81b2b7a0` |
| Preserved original P4 | `d0742eac0fab4d182338dc75d5aacb77658e0c09` |
| Reused P2 harness and historical reports | `e3b6b92c48695abfb6f5ecbc0a60ec84a3f99dc0` |
| Isolated checkout | `/private/tmp/gametime-simplify-20260911-byc27c1u/GameTime` |
| Raw evidence and disposable stacks | `/private/tmp/gametime-p4-final-20260911` |

The follow-up documentation commit contains this report and the compact evidence;
it does not change the tested implementation. Before editing, the accepted
product checkout was still at `affd367`, pool 9 still at `d0742ea`, and the earlier
P4 Codex task was idle. No active P4/Firstmate worker was found. Those source
identities were rechecked before delivery. The original dirty checkout stayed
at `577bc321e72750976e2e8027680387707070b0e3`; its work was not imported.

The retained `20260911143019_challenge_scoped_locks_bounded_claims_v1.sql` is
byte-identical to the task input. The only added migration is
[`20260911224043_challenge_durable_claims_and_read_locks_v1.sql`](../../supabase/migrations/20260911224043_challenge_durable_claims_and_read_locks_v1.sql).
All 74 migration files matched the executed final-stack inputs, recorded in
[migration hashes](p4-20260911/migration-hashes.json). The comparison baseline
used only the 72 unchanged product migrations. No applied migration was rewritten.

## Resulting behavior

Ordinary validation and reads take the authenticated session's shared row lock,
with expiry and active-account checks after waiting. They acquire neither the
global gate nor the actor mutex. Mutations use the documented order: shared
gate, caller actor, session, request/challenge scopes in UUID order, all affected
profiles in UUID order, then challenge-owned rows. Control-plane changes alone
take the gate exclusively. Cross-challenge admissions coordinate on profiles;
invites include the resolved invitee in the initial ordered set. Admission,
revocation and time-sensitive cutoffs are rechecked after waits. Safe reads,
reviews and exits continue during admission/processing pauses.

The private durable claim table has one coordination row per challenge, a unique
token, attempts, scheduling, lease expiry and a SQLSTATE-only last error. Claims
use bounded `FOR UPDATE SKIP LOCKED`, commit without ticking any challenge, and
materialize the inventory once per batch. The existing operator now completes
each item through a separate RPC transaction, using five bounded lanes and a
five-second network timeout. One request failure does not abandon later items.

Leases last 60 wall-clock seconds. Failures roll back the item's lifecycle effects
and retry after 2/4/8/16 seconds, with five consecutive attempts before dead-letter
visibility. Expired leases can be reclaimed with a new token. Completion checks
token/expiry after waiting; immutable receipts make duplicates exact and prevent
stale workers from applying effects. Operations reports overdue work, abandoned
leases, retries and dead letters, retaining historical failure counts. Dead
letters require investigation; there is no automatic endless requeue.

Cancelled/terminal challenges and existing finals are excluded. Completion
rechecks only its own item, and safe ticks no longer keep revising cancelled
drafts. Notice and review deadlines remain 48 hours from actual notice and 72
hours from filing. Existing agreements, privacy and admission limits are retained.
The retained 250-person **fixture** boundary and 249th/250th/251st checks remain;
community product work is still Prompt 6.

The old `challenge_run_batch_v1` returns historical exact receipts but rejects
new runs with `challenge_use_claim_batch`. The shipped operator uses the new
claim/complete protocol. A SQL batch function cannot commit separately per item;
keeping that old execution path would retain the original problem. See
[worker and lock contract](../../docs/CHALLENGE_WORKER.md) for the API/order.

## Final-source validation

All database work used fictional data in two named disposable local Supabase
projects, PostgreSQL 17.6 on arm64, CLI 2.109.1. The explicit task network avoided
the earlier exhausted default address pools. Final P4 used API/DB ports
59421/59422; unchanged baseline used 59521/59522. No existing stack was reset.

| Check | Actual result |
| --- | --- |
| Fresh migration reset | All 74 final migrations applied successfully. |
| Full portable SQL suite after final SQL edits | **87 files, 3,951 assertions passed, zero skips.** Includes new domain and historical tests because the session helper is shared. |
| Expanded final durable-worker file | **40/40 passed.** The full suite above included its earlier 33 assertions; seven test-only assertions were added afterward. No implementation SQL changed. This is not a claim that a 3,958-assertion full suite was rerun. |
| Actual concurrent SQL sessions | **48 assertions passed twice** on final source. |
| Session expiry/revocation regression | **12/12 passed**, including unchanged-row expiry during a wait and deletion winning the lock. |
| Old-data baseline-to-P4 upgrade | **193/193 passed**: all 187 existing app/public table digests unchanged, old weekly/Beta agreements present, every existing challenge seeded, old receipts/failures preserved, cancelled work excluded. |
| Existing runner-cleanup unit tests | **5/5 passed.** |
| Worker driver unit tests | **2/2 passed**, including a failed RPC not preventing later completions. |
| Preserved P2 unit tests on their exact P2 source | **27/27 passed.** On P4, 26/27 passed and the fixed-parent guard rejected migration drift; see limitations below. |
| Direct PostgreSQL PL/pgSQL checker | **0 errors, 17 warnings, no checker failures** across non-trigger app/public PL/pgSQL functions. |
| Static/source checks | Changed Python files parsed; diff whitespace checks passed; migration hashes and retained-file identity matched. |

The five previously unreached cases now pass: same-challenge stale revision,
same-link final slot, session revocation winning a wait, skipping an owned claim,
and independent concurrent completion. Additional real races prove unrelated
accounts proceed; same-actor retries store one receipt; conflicting admissions
reserve only three unsettled slots; freeze/join coordinate across different
callers; consent/reopen yields one stale revision; revocation denies a fresh link
below capacity; operator suspension is rechecked by a waiting personal admission;
reciprocal invites avoid lock inversion; issue/join reject after a real cutoff
passes; expired claims get fresh tokens; stale/duplicate completions cannot apply
twice; cancelled polls leave revisions unchanged; reads bypass the exclusive gate.

The durable SQL tests inject failure at review transition, after earlier state
changes and notice insertion, proving those effects roll back. They exercise
backoff, five-attempt exhaustion, abandoned-claim exhaustion, successful recovery,
old exact receipts after recovery, and safe review/exit during pauses or failure.
The rollback SQL adapter is behavioral coverage; separate-session and HTTP runs
are the evidence for transaction boundaries.

Actual commands were run from the isolated checkout (the URLs below are only
the task-owned loopback databases with disposable local credentials):

```sh
supabase db reset --local --workdir /private/tmp/gametime-p4-final-20260911/stack --network-id gametime-p4-final-20260911 --no-seed
python3 /private/tmp/gametime-p4-final-20260911/run-sql.py
psql postgresql://postgres:postgres@127.0.0.1:59422/postgres -XqAt -v ON_ERROR_STOP=1 -c 'set search_path=public,extensions' -f supabase/tests/504_challenge_durable_claims.test.sql
python3 scripts/beta-scoped-locks-p4-concurrency.py --db-url postgresql://postgres:postgres@127.0.0.1:59422/postgres --owned-root /private/tmp/gametime-p4-final-20260911/stack --owned-project gametime-p4-final-20260911
python3 scripts/beta-session-expiry.py --owned-project gametime-p4-final-20260911 --stack /private/tmp/gametime-p4-final-20260911/stack --port 59422 --report /private/tmp/gametime-p4-final-20260911/session-expiry.json
psql postgresql://postgres:postgres@127.0.0.1:59522/postgres -XqAt -v ON_ERROR_STOP=1 -f /private/tmp/gametime-p4-final-20260911/upgrade-before.sql
psql postgresql://postgres:postgres@127.0.0.1:59522/postgres -XqAt -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20260911143019_challenge_scoped_locks_bounded_claims_v1.sql -f supabase/migrations/20260911224043_challenge_durable_claims_and_read_locks_v1.sql
psql postgresql://postgres:postgres@127.0.0.1:59522/postgres -XqAt -v ON_ERROR_STOP=1 -f /private/tmp/gametime-p4-final-20260911/upgrade-after.sql
PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/beta-scoped-locks-p4-runner.test.py -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/challenge-worker.test.py -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/challenge-load -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s /private/tmp/gametime-p4-final-20260911/p2-source/scripts/challenge-load -p 'test_*.py' -v
psql postgresql://postgres:postgres@127.0.0.1:59422/postgres -XqAt -v ON_ERROR_STOP=1 -f /private/tmp/gametime-p4-final-20260911/direct-lint.sql
python3 scripts/challenge-load/p4_compare.py --label final
git diff --check
git diff --cached --check
```

The SQL suite script applies the seed, installs test extensions and runs every
`*.test.sql` with `ON_ERROR_STOP`, a per-file timeout and TAP plan/assertion/skip
accounting. Copies of that script, upgrade SQL, checker SQL and result logs are
in [the evidence directory](p4-20260911). The baseline was reset to its unchanged
72 migrations after upgrade testing, before the final comparison. Both stacks
were freshly reset before that comparison; copied startup logs containing local
API keys are retained only under the task root, not committed.

## Short before/after comparison

The comparison reuses P2's unchanged HTTP client and arrival accounting. The
original harness, fixtures, tests and reports were copied byte-for-byte from P2;
only a small P4 comparison adapter was added. Both sides have the same 100
fictional accounts and 100 expired drafts. Foreground uses 32 independent HTTP
clients making six reads each. The worker mix offers 500 logical operations over
10 seconds at 50/s, concurrency cap 32: one quarter worker, one quarter status,
one quarter action reads, one quarter active reads. The baseline uses its original
batch API; P4 uses the shipped separate-transaction driver.

| Final-source measurement | Product baseline | Completed P4 |
| --- | ---: | ---: |
| Foreground completed / errors | 192 / 0 | 192 / 0 |
| Foreground elapsed | 0.297 s | 0.146 s |
| Foreground completed throughput | 647.18 requests/s | 1,311.43 requests/s |
| Foreground HTTP p95 | 112.99 ms | 55.51 ms |
| Foreground logged lock-wait episodes ≥1 ms | 241 | 0 observed |
| Foreground lock-wait p95 / maximum | 18.388 / 24.912 ms | No qualifying wait |
| Worker-mix offered / completed in window | 500 / 500 | 500 / 500 |
| Worker-mix offered / completed including drain | 50 / 49.968 operations/s | 50 / 49.968 operations/s |
| Worker-mix HTTP/logical operation p95 | 23.950 ms | 6.241 ms |
| Worker-mix failures / dropped offers / deadlocks | 0 / 0 / 0 | 0 / 0 / 0 |
| Worker-mix logged waits ≥1 ms | 0 observed | 0 observed |
| Worker entries for the 100 challenges | 2,500 | 100 |
| Unique completed challenges | 100 | 100 |
| Cancelled rows / remaining due inventory | 100 / **100** | 100 / **0** |

The P2 arrival-deadline `capacity_pass` is true on both runs; it does **not** make
the baseline's repeated cancelled processing correct. Final postflight explicitly
records that failure. The paced 50/s run is not a maximum-throughput test.

Actual waits come from PostgreSQL `log_lock_waits` with `deadlock_timeout=1ms`,
plus live `pg_stat_activity`/`pg_locks` observations. Counts are wait episodes,
not unique requests. Shorter waits are outside the logging threshold. The raw
wait lines and four final summaries are committed in the evidence directory.

`pgrowlocks` tuple ownership and advisory ownership also measured lock residence
for observed transactions. The adjacent sampling times bound duration; they are
not exact per-request timers. Representative lower–upper p95 bounds:

| Observed lock scope | Transactions | p95 duration bounds |
| --- | ---: | ---: |
| Baseline foreground runtime row | 65 | 0–10.352 ms |
| P4 foreground session row | 60 | 4.179–10.258 ms |
| Baseline worker runtime row | 155 | 7.376–14.651 ms |
| P4 worker advisory scopes | 66 | 0–10.043 ms |

Sampler interval p95 was 3.7–5.8 ms. A zero lower bound means only one observation,
not zero hold time; unobserved or boundary-spanning ownership is not an exhaustive
measurement. P4 foreground had no runtime-row ownership. Sparse zero-wait samples
do not prove absence of all contention; the explicit blocking races provide the
correctness evidence independently.

The earlier short comparison is preserved too: foreground 859.17→1,099.10/s,
wait episodes 191→0, worker entries 2,500→100. Cold bursts vary; neither run proves
a stable speedup ratio, hosted throughput, sustained headroom or release capacity.

## One concise review and closed findings

One focused review used the review-and-simplify skill, with three independent
read-only scopes: locks, durable claims and clarity. No second review loop ran.
Concrete findings were fixed and affected checks rerun:

- Personal admission needed a suspension recheck after the profile wait;
  reciprocal invite targets needed inclusion in the original sorted lock set;
  issue/join needed refreshed time after waits. The final real races cover each.
- An early completion transport error could strand the rest of a batch; the
  bounded driver now isolates each error, covered by its two unit tests.
- Operations had dropped old `failed_count` evidence; the upgrade test confirms
  the preserved historical count of three and exact historical response.
- The link-revocation test previously used a full link, obscuring the denial
  cause. It now uses an empty link and proves revocation alone prevents redemption.
- Failure injection was too early to prove rollback. It now fires after state
  changes and notice insertion, and asserts both are absent afterward.

## Preserved failures, limitations and skips

- The first task race invocation failed because Python 3.9 lacks `tomllib`.
  The runner now parses the needed port without it. Earlier raw logs remain;
  the two final 48-assertion runs are the accepted evidence.
- An attempted baseline clone inside the final cluster had 48 restore failures
  involving pg_cron/system extension privileges. That clone was not used for
  acceptance or measurements. A separate fresh baseline stack supplied the
  passing upgrade and comparison instead. The failed dump/log remain retained.
- CLI database advisors and CLI lint could not connect (`LegacyDbConnectError`)
  despite the working loopback PostgreSQL connection. Their checks remain
  **unperformed**, not passed. The direct PostgreSQL checker ran successfully;
  it is not a substitute claim that the CLI advisor ran. Its 17 warnings include
  inherited volatility/literal-cast warnings and one new valid text-to-jsonb
  literal initialization warning in `challenge_claim_batch_v1`. None is an error.
- P2's unmodified unit suite on P4 has one context failure: its occupied-port test
  encounters the intentional fixed-parent migration guard first. The guard was
  not relaxed and the test was not removed. All 27 pass at the exact original
  P2 source. Both logs are retained.
- P2's historical [capacity report](../../docs/load/capacity-report.md) remains
  unchanged: worker contention missed a strict deadline by 4.388542 ms; the
  250-arrival join storm had 14 disconnects at its original 100-member cap; the
  25k attempt had 15 failures and 10,039 unoffered arrivals; it recorded 123,500
  worker entries for 100 cancelled challenges. None is reclassified as a pass.
  Its successful historical two-hour soak was not rerun for P4.
- No shadow schema diff, hosted advisors, full release matrix, two-hour soak,
  25k characterization, native build/Simulator, ASAN/TSAN, physical sources or
  human acceptance was run. There are no native changes; the plan's minimum/current
  iOS lanes therefore did not need task-specific execution. SQL suites had zero
  skipped assertions. No missing required P4 correctness race is called passed.
- Discovery still evaluates the full inventory once per batch/status call.
  Further query/history bounds belong to Prompt 5. Claim rows and immutable
  receipts retain history; retention policy and dead-letter remediation are
  operator concerns, not a new general queue framework in this task.

Only the two task-owned stacks were stopped after verifying every challenge gate
false, with backups preserved. The task network and raw evidence were retained.
Existing `gdluxx`, `supabase_studio_gametime` and `supabase_storage_gametime`
resources were left intact; storage was already restarting before this task's
cleanup. See [shutdown evidence](p4-20260911/shutdown.json).
