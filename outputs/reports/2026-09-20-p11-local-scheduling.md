# P11 local scheduling and monitoring boundary

Completed September 20, 2026 UTC on `codex/p11-local-scheduling` in
`/Users/user/Documents/GitHub/GameTime`. Implementation source:
**`ddf70245111b6aca69f3960392b3cbf8db7c441d`**, directly from reviewed P9
`fa97cb26b5e13e6ebf86e9acebd02f255c3b50e8`. P9 application source
`b0ce67e64ae1a47dd222d5e56e8ea0ef4c63dfae` and P8 `8a9d1f0` remain in its ancestry.
Later changes in this task are documentation and review artifacts only.
No merge or push was performed.

The owner-selected Supabase Cron + Edge connection is implemented and passed
focused local acceptance. Three fixed machine interfaces use separate worker
and monitor secrets; private Cron preparation and database leases preserve
durable invocations and exact receipts. New jobs are registered inactive in the
forward migration transaction. Configuration has no destination, secrets or
community by default. The existing local operator CLI is unchanged.

The [hosting worksheet](../../docs/BETA_HOSTED_PREPARATION.md#september-20-local-cron-and-edge-continuation)
describes the contracts, defaults and remaining operating dependencies. This
report establishes local software behavior with synthetic data, not hosted,
physical source, human or release acceptance.

## Performed checks

| Check | Final result |
| --- | --- |
| Focused SQL | **325 assertions passed**: 509=43, 515=70, 518=59, 521=20, 522=44, 524=67, 525=22. |
| Edge | **12 tests passed**; type check, lint and format checks passed. |
| Existing Python worker | **4 tests passed**. Both new verifier scripts passed syntax checks. |
| Actual Cron → pg_net → Edge Runtime → PostgREST → SQL | All **three routes returned HTTP 200** at 08:09 UTC; worker completed one synthetic real-contract item and the selected community captured once. |
| Credential and operation boundary | **27 HTTP denials passed**: missing, wrong, cross-role, public/user/service-key-only credentials, plus caller-selected RPC/cohort/scope fields. |
| Actual independent-session races | **Six checks passed**; actual PostgREST lock timeout measured **4.03 seconds**. |
| Fresh and populated upgrade | Exact final forward migration applied to both owned databases; historical agreement digest unchanged; historical Cron execution prevented. |
| Security advisor | Final owned loopback database: **No issues found**. |
| Final closure | Zero task-owned containers, networks or temporary images; private manifests and source stage removed. |

The [portable evidence index](p11-evidence/README.md) links sanitized results,
exact source-check commands, migration/source hashes and cleanup receipts.

The actual runtime test used cached Supabase Edge Runtime `v1.74.2`, PostgREST
`v14.14`, Postgres `17.6.1.143`, and Supabase CLI `2.109.1`. Deno source checks used
`2.9.4`. Only seven byte-verified production handler/adapter files were staged,
along with a local router and erased type shim. The router maps the three fixed
paths and the owned raw PostgREST prefix. It does not replace lifecycle logic.
The Edge container had an internal network with no Internet access, no published
port, dropped capabilities and no new privileges. Only the owned database and
PostgREST joined that network. Dedicated secrets were ephemeral; the internal
service JWT lasted five minutes and authorized only the fictional local stack.
Hosted gateway deployment and credential custody were not tested.

Cron was globally off from database startup through every historical and new
migration. All legacy jobs were then disabled using `cron.alter_job`; only the
three new jobs were temporarily enabled. Worker and monitor used the one-minute
default. The disposable snapshot job was accelerated to one minute for one
bounded test; its SQL 900-second throttle remained intact and its registered
15-minute schedule was restored before closure.

The operating proof required a real-contract notice from synthetic normalized
facts while legacy fixture, discovery, actor and fictional-clock gates stayed
off. The unselected cohort had neither a snapshot nor an invocation. Internal
verification checked the five-person threshold without disclosing member counts
through machine responses. The unchanged snapshot suite also verified delayed
disclosure and the exact 15-minute boundary.

Recovery checks covered duplicate ticks, competing dispatches, exact saved
claims and completion receipts, missing unlogged queue entries, expired claims,
five-attempt failures, stale-run fencing and finish waiting behind five shared
completion locks. The actual Edge process restarted and replayed the exact
completed worker/snapshot results. Unfinished-run and claim-expiry recovery were
exercised in SQL; adapter tests discarded dispatch/completion replies and retried
the same argument bytes. The race harness used temporary timing instrumentation
and a synthetic saved receipt; original functions were restored and independently
read back before cleanup. This was not a hosted process-failure or load test.

Paused processing preserved committed receipts, full notice-relative 48-hour
and filing-relative 72-hour windows, and safe participant review actions. Monitor
HTTP calls reported unavailable transport, paused processing and inactive jobs
accurately. Two sanitized responses went to a local file sink; application-table
fingerprints before and after the reads matched. Capture time remained separate
from successful invocation time.

## Commands and preservation

The final owned stack used the following commands from the repository root.
The manifest paths no longer exist because cleanup removed the credentials.

```sh
python3 -B scripts/p11-local-scheduling-verify.py prepare \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json
python3 -B scripts/p11-local-scheduling-verify.py apply-forward \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json \
  --forward-migration supabase/migrations/20260920071900_challenge_machine_scheduling_v1.sql
python3 -B scripts/p11-local-scheduling-verify.py check \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json \
  --tap 509_challenge_local_worker_recovery \
  --tap 515_challenge_local_review_status \
  --tap 518_challenge_community_snapshot_status \
  --tap 521_challenge_real_health_privacy \
  --tap 522_challenge_real_health_worker \
  --tap 524_challenge_machine_scheduling \
  --tap 525_challenge_machine_real_processing
python3 -B scripts/p11-local-scheduling-verify.py bounded-acceptance \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json
python3 -B scripts/p11-machine-concurrency.py \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json
python3 -B scripts/p11-local-scheduling-verify.py check \
  --manifest /tmp/gametime-p11-scheduling-acceptance-manifest.json
python3 scripts/tests/challenge-worker.test.py
```

The operating seed was applied once through the verifier's
`prepare_operating_fixture` helper before the bounded run; the private manifest
recorded its hash so subsequent attempts did not reseed. The normal bounded
command performs this step itself when absent. Final cleanup called the same
`cleanup` helper used by the verifier's `cleanup --manifest …` mode and then
checked Docker inventories by the exact owner label. The final advisor command
was `supabase db advisors --db-url <private-loopback-DSN> --type security
--fail-on none --output json`, with `DO_NOT_TRACK=1`. The CLI prints “remote
database” for an explicit DSN; the actual destination was the owned loopback port.
No DSN or credential is included in portable evidence.

Final migration SHA-256:
`b4f88fa3ef0979a90c57fa3a1dfddda776b225f3f198d311b4acce04a430d122`.
The populated final run's historical agreement digest stayed
`23334fd1372ea787a999b29c6898da9ee487c12593864f8a5b81beb9550f15cb`
across the upgrade and operating checks. Each disposable baseline has its own
fixture timestamps; this compares records within that run. Historical migration
files, consent strings, native code, source rules and `readiness.json` were not
changed. All 18 readiness values remain false.

## Failures retained

- Two SQL syntax errors in the new, unapplied migration were corrected after
  failed initial applications. Final acceptance rebuilt both databases from the
  final bytes; it did not rely on an overlay.
- Final review found that changing community selection could strand pending
  snapshots, including when returning to the original selection. It also found
  that monitor state omitted its own inactive job. Both were fixed and covered
  by focused assertions. The first added test setup hit `challenge_one_community`;
  a rollback-owned second-cohort fixture corrected the setup. The final 67-assertion
  scheduling suite passed.
- Automatic approval review rejected the first full-repository container mount
  with local service credentials. A materially safer seven-file stage, short-lived
  fictional credentials and internal network were approved and used instead.
- Runtime setup initially exhausted Docker's default network pools. Selecting a
  disjoint explicit private subnet fixed this; null Docker network metadata also
  needed handling. Host-port health probes then failed three times. A socket
  inspection proved Edge was listening internally, so ingress moved inside the
  isolated network. No existing networks were deleted and isolation was retained.
- The initial advisor connection omitted the password from the explicit local
  DSN and failed. The corrected local connection passed; final advisor passed
  again. A later CLI help call hit a sandboxed telemetry-file write; final
  advisor execution used `DO_NOT_TRACK=1`.
- Final Deno type-check invocation used unsupported `check --cached-only`.
  `check --deny-import` passed. The failing command and passing correction are
  both retained in source-check evidence.

## Remaining P11B inputs and limits

P11B still needs the exact approved candidate, organization/project, region,
plan/budget and permitted actions; credential custody and rotation; named
primary/backup operators, independent reviewers, support and alert destinations;
approved operating limits, backup/RPO/RTO, retention and provider-log treatment;
community target, amount, dates, timezone, capacity and outcome minimum; and
Apple/domain/client identities when connecting the app. The hosting worksheet's
owner values remain unselected and its configuration remains non-executable.
Local account-deletion approval does not approve broader hosted retention.

No hosted project inspection with credentials, provisioning, deployment, real
schedule activation, external alert delivery, capacity acceptance, physical
Health access, P7 restart, human acceptance, publication, distribution,
recruitment, money, historical cleanup or replacement retirement occurred.
The full P9/P12 matrix was not rerun. Nine available goals and four unavailable
leaderboards remain the current capability. Incomplete observations still
cannot establish confirmed misses or complete rankings; the four-metric/all-13
release requirement is unchanged.
