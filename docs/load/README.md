# Challenge load harness

This is the unchanged-product local baseline for Prompt 2. Product SQL and configuration are pinned to `7c34d52bc0250053819e35342a2b4fd9ed5d7382`; the harness owns only `scripts/challenge-load/**` and its reports. A local Docker result does not establish hosted, native app, real Auth sign-in, Health, payment, or release capacity.

The [completed capacity report](capacity-report.md) records each measured window and exact source hashes. The two-hour soak passed; worker deadline, join transport and aborted 25k scenarios remain failures. Both local labs are retained with all gates off. A successful HTTP status alone is insufficient for correctness or capacity acceptance.

## Prerequisites and resource ownership

Use Python 3.9+ standard library, a preinstalled Supabase CLI, Docker, `psql`, and a clean isolated checkout descended from the pinned parent. This harness does not install dependencies. Its recorded lab used CLI 2.109.1 and PostgreSQL 17.6. `lab.py` accepts no hosted URL or database target. Every SQL connection removes inherited libpq settings, supplies explicit loopback connection parameters, and verifies the owned container's PostgreSQL system identifier on that same connection. The HTTP client separately validates a namespace-specific actor/session canary.

The source config and exact migration file set must match the pinned commit, including untracked-file and symlink rejection. New stack files are extracted from committed bytes. Product-changing descendants are rejected. A measurement spec records all Python hashes; the mandatory preflight also binds core fixture/oracle/runner hashes, private live metadata, namespace, cluster identity, and historical data hashes.

Port family **41320–41329 is already retained** by the corrected baseline. Family **42320–42329 is retained** by the failed first attempt. The current initializer deliberately fails on either an existing run directory or a collision. Before a later fresh run, obtain a distinct allocation from the resource owner and update only the harness's bounded port declarations/validation as a reviewed harness change. Do not stop a retained stack to make these ports available. Each fresh run gets a new `challenge-load-<12 hex>` project and UUID namespace. All service ports are probed on IPv4 and IPv6 before creation.

Use a create-exclusive task evidence root outside the checkout. `manifest.json` records project, namespace, ports, source/config hashes and container IDs; `cluster-identity.json` binds the database identity. `private/` contains command receipts, source SQL output and synthetic credentials and must not be published. Retain failed start logs and partial directories; do not recycle them as new runs.

## Run sequence

These commands are instructions for a separately authorized fresh allocation, not permission to operate retained resources. `CHALLENGE_LOAD_RUN` must name a nonexistent directory whose parent exists. Init is the only command that starts a new stack; there is no stack stop, reset, teardown or volume-delete command.

```sh
export CHALLENGE_LOAD_RUN=/absolute/task/evidence/unique-run-name
python3 -m unittest discover -s scripts/challenge-load -p 'test_*.py' -v
python3 scripts/challenge-load/lab.py init "$CHALLENGE_LOAD_RUN"
python3 scripts/challenge-load/fixtures.py seed "$CHALLENGE_LOAD_RUN"
python3 scripts/challenge-load/live.py "$CHALLENGE_LOAD_RUN"
python3 scripts/challenge-load/races.py "$CHALLENGE_LOAD_RUN" --name lock-proof-01
python3 scripts/challenge-load/plans.py "$CHALLENGE_LOAD_RUN" --name plans-2000-01
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" smoke --name smoke-2000-01
```

Every output name is create-exclusive. Run isolated lock proofs and rollback plans before the soak. Do not overlap artificial blockers, fixture expansion, or another load scenario with a window described as the steady soak. An observer may run alongside the load using a supervisor-tracked process. Record its process identity, start and exit; never stop an unidentified process.

```sh
python3 scripts/challenge-load/observe.py "$CHALLENGE_LOAD_RUN" --name observe-soak-2000-01 --seconds 7240
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" soak --name soak-2000-01 --max-inflight 100
```

The two commands above are separate concurrent supervisor-tracked jobs. The observer samples about every 30 seconds; the runner checks structural invariants every 60 seconds. Their overhead is part of the local measurement. Run the following scenarios sequentially after the soak, using separately named observer windows when required:

```sh
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" ramp --name ramp-2000-01 --max-inflight 100
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" spike --name spike-2000-01 --max-inflight 100
python3 scripts/challenge-load/bursts.py "$CHALLENGE_LOAD_RUN" foreground --name foreground-2000-01
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" worker-contention --name worker-contention-2000-01 --max-inflight 100
python3 scripts/challenge-load/bursts.py "$CHALLENGE_LOAD_RUN" join --name join-2000-01
python3 scripts/challenge-load/scale.py "$CHALLENGE_LOAD_RUN"
python3 scripts/challenge-load/runner.py "$CHALLENGE_LOAD_RUN" long-term --name long-term-25000-01 --max-inflight 1000
```

`scale.py` requires the bound 2k preflight before batched 25k expansion and compares historical hashes against the retained 2k receipt before publishing a new private live manifest and independent `preflight-25000.json`. A failed comparison writes a failure artifact and leaves no admissible 25k receipt. The lower-level `fixtures.py expand-25000` only inserts accounts; it does not authorize a load run without the new preflight. Do not substitute it for the complete expansion entry point.

The join storm fills the only open community to its real 100-person cap. The `plans.py` join case must therefore be captured before that storm; after capacity is exhausted, its attempted join correctly fails. Do not remove participants or widen capacity to manufacture a second successful join plan. Label unavailable post-storm join plans explicitly. The final baseline closes that gap with a separately authorized, wholly rolled-back fixture and real RPC plan; its exact SQL and pre/post preservation evidence are in `docs/evidence/challenge-load/run-20260909T2230-4132/join-plan-25000-v2-02/`. That artifact is not permission to operate retained resources.

## Fixtures and workload

UUIDv5 identities are deterministic within the recorded namespace. Accounts are inserted in batches of 1000, with synthetic profiles, age/access/readiness and actual local `auth.sessions` rows. JWTs bind each synthetic actor and session and are signed with this new stack's local key. This exercises REST authorization and session checks but bypasses real sign-in issuance and refresh.

History has 4100 challenge snapshots across all 13 policy types and at least one million challenge-related rows. Each historical participant has 120 sequential fact revisions, including downward changes, deleted facts and unresolved facts. Frozen agreements are constructed from the effective policy-specific product contract; an independent Python oracle verifies every agreement and final allocation. The corpus includes scored and void finals, tied leaderboard winners, integer remainders, reopened agreements, reviews/resolutions, blocks, exits, revoked links and request journals. Constraints and immutable guards remain enabled. Bulk historical snapshots do not claim that their entire admission/history timeline was produced through RPCs.

Live state contains 100 personal commitments across four metrics, 50 friend pairs, one pending friend draft with twenty actual link redemptions, an empty published community with real cap 100, scoped independent operator grants, and 100 expired drafts eligible for worker discovery. Real ingestion/source/analytics flags remain false. The actual runtime allowlist stays at 100; service capture calls target that bounded cohort.

| Scenario | Offered shape | Meaning |
|---|---|---|
| Smoke | 10 seconds × 2 logical requests/s | One pass through the 20-part operation mix plus pre/postflight |
| Ramp | 60 seconds × 5, 60 × 10, 120 × 25 | Beta arrival characterization |
| Spike | 30 seconds × 5, 60 × 25, 30 × 5 | Beta burst/recovery window |
| Soak | Actual 7200 seconds × 10 | Sustained local mixed traffic; an early exit is incomplete |
| Foreground | 100 distinct sessions released by a barrier; six sequential calls each | Action, active, upcoming, history, access, catalog; actual release spread and overlap reported |
| Join storm | 250 distinct sessions released by a barrier | Expected 100 admissions and 150 `challenge_capacity`/23505 refusals; exact winning retries |
| Worker contention | 120 seconds × 25; 50% worker status/batch, 50% client section | Different mix from ordinary ramp/soak |
| Long-term | 60 seconds × 25, 60 × 75, 120 × 150; inflight ceiling 1000 | 25k registered accounts; 1000-actor read cohort; mutations/detail hotspots remain at 100 |

The ordinary mix includes sections and cursor continuation, participant detail/history, community catalog, access, exact link/age retries, scoped operator reports/cases, worker status/batch, ingestion-like fixture revisions, and reports. Primary scheduled arrivals are logical operations. Unknown-commit recovery can add two HTTP attempts; those attempts are explicitly attached to the original event and must be reported separately from the primary arrival rate.

A configured inflight ceiling or registered-account count is not measured simultaneous activity or daily usage. Report observed overlap and distinct actors from event timestamps. The requested 250-person Beta and 10,000-person long-term community sizes exceed the implemented cap of 100; the harness characterizes the expected refusal and does not bypass the product contract. Daily active targets are workload-design inputs, not a day-long observation.

## Correctness, failures and retention

The required preflight checks actor ownership, slot bounds, agreement/consent presence and digest equality, contiguous bounded revisions, external gates, final field types/conservation, released final slots, pending/blocked/departed privacy, cross-actor detail/journal denial, actor-bound cursor progression, exact receipt replay, simulated lost-receipt recovery with one database effect, and changed-payload rejection. Historical hashes cover lobbies, members, agreements, consents, facts, notices, reviews, resolutions, exits and finals. They do not cover every historical request journal row.

Timed runs reject a missing/stale preflight. Section/detail responses must have the expected shape and authorized challenge IDs; exact retry bodies must match canonical receipts. A response invariant or periodic structural failure stops new dispatch immediately, drains already dispatched work, saves a failed result and exits nonzero. The operational stop also triggers once at least 100 completions have an error ratio above 50%. SQL and HTTP timeouts are bounded; no mutation is silently retried by the transport layer. SIGINT/SIGTERM stop only that owned runner and drain its tracked work.

Open arrivals use absolute offsets. Inflight saturation and scheduler lag become explicit drops. A capacity pass requires every planned arrival offered and completed inside the window, no drops, no errors, no abort and successful postflight. Drain completions are separate. A correct expected product-capacity refusal may pass the join storm's correctness oracle while demonstrating that a larger admitted community is unsupported. No latency SLO is invented by this harness; the report presents percentiles and their context.

On an invariant failure, foreign identity, changed product source, namespace ambiguity, unknown commit that cannot be reconciled, or a required gate failure, retain all evidence and stop dependent scenarios. Diagnose locally within harness ownership. Do not reset or edit product SQL to make a baseline pass. A required scenario that fails capacity is still measured evidence, not a successful target claim.

`audit.py` captures exact challenge-table counts, account/roster/fact shapes, table/index/database bytes and aggregate worker outcomes with no writes to product data. Run it outside timed windows at each account tier, before disabling fixture gates, using a unique `--name`. It requires the same bound preflight and immutable postflight.

```sh
python3 scripts/challenge-load/audit.py "$CHALLENGE_LOAD_RUN" --name audit-2000-01
```

After every required window and final evidence capture:

```sh
python3 scripts/challenge-load/lab.py gates-off "$CHALLENGE_LOAD_RUN"
```

Optional explicitly scoped session cleanup is available as `lab.py cleanup-sessions`: after validating the exact synthetic registry and handles it disables gates, deletes only owned page snapshots and synthetic sessions, and retains the immutable challenge ledger. It does not delete accounts, histories, stacks or volumes. The unchanged product guards prohibit wholesale ledger cleanup, so full namespace deletion is not offered. Retain run manifests, failures, logs and all stack volumes after reporting. Existing source/release task owners remain responsible for their unresolved decisions.

## Offline evidence summary

`python3 scripts/challenge-load/summarize.py /absolute/run/scenario --out /absolute/run/scenario/analysis.json` reads retained sanitized event files only and writes a create-exclusive summary. It separates HTTP duration from scheduled-arrival-to-finish duration, counts additional recovery attempts, and derives peak dispatched logical overlap. It parses and hashes one captured byte buffer, fixes summary presence at capture start, and imports final disposition only if source/spec, counts and the measured window agree. A later summary publication requires a new uniquely named report. Partial trailing bytes remain included in the hash and are reported without being counted as completed records. Report-generation exit0 is not a capacity pass. Canary/preflight traffic and join-winner verification retries are outside the primary-event traffic totals. Use `--observer` for captured observer samples; those snapshots make no completion claim. No database or application is contacted.
