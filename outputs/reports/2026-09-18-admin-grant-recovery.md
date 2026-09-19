# Administrator grant/revoke response recovery — September 18, 2026

Review branch: **`codex/admin-grant-response-recovery`**, based on current committed
local main **`70584f16959885b4610cd635d3e8b81e70f85f4f`**. Work used the isolated
`/private/tmp/gametime-admin-grant-recovery-20260918` checkout. The primary
checkout's unrelated uncommitted iOS changes were preserved. No push, merge,
deployment, hosted credentials, source-policy change or readiness change occurred.

## Implemented contract

Forward migration `20260919023548_challenge_admin_request_v2.sql` adds the
service-only `challenge_admin_request_v2(uuid,jsonb)` RPC, a strict versioned
payload and `challenge_admin_receipt_v2` response. A private RLS-protected,
append-only request table binds one UUID to the entire payload across all four
administrator operations. Service authorization precedes receipt lookup. A
transaction-scoped advisory lock serializes duplicate UUIDs; a new request invokes
the existing v1 mutation and stores its receipt in that same transaction.

Exact replay returns the original saved response without repeating the grant,
revoke or audit action. An old grant cannot restore subsequently revoked access;
an old revoke cannot remove a newer grant. Recovery also works after expiry and
runtime pause. Changed parameters conflict with `22023`. Fresh requests retain
v1 scope, independence, account and seven-day expiry rules. Revoking an absent
grant keeps its audited no-op behavior. No named administrator attribution is
invented: the existing grant audit identity denotes the subject account.

The CLI now requires an explicit request UUID and private journal for all four
grant/revoke commands. Before dispatch it atomically writes and syncs the exact
project/loopback port, administrator authority, RPC and request bytes. Human
version-1 journals remain compatible. Administrator version-2 records contain
no credentials, tokens or response data. Conflicting local environment, authority,
operation or payload fails before HTTP. There is no automatic retry.

The original four v1 administrator RPCs and their privileges are unchanged.
Historical calls are not backfilled and retain manual reconciliation; issuing a
new UUID cannot recover their missing response. See the updated
[recovery instructions](../../docs/BETA_OPERATIONS_LOCAL.md).

## Actual verification

| Check | Actual result |
| --- | --- |
| Journal/parser unit suite | **11/11 passed** |
| Final focused CLI/Auth/PostgREST smoke, run 3 | **100/100 passed**, exit 0 |
| New SQL 516 request/receipt suite | **58/58 passed**, complete TAP plan, exit 0 |
| Historical SQL 493 entry suite | **42/42 passed**, complete TAP plan, exit 0 |
| Historical SQL 497 operations suite | **19/19 passed**, complete TAP plan, exit 0 |
| Upgrade with existing fictional v1 records | **414 existing app/public table snapshots identical**; four v1 function definitions and ACLs identical; zero backfilled administrator receipts |
| Supabase CLI 2.109.1 security advisors, warning/error level | Exit 0; no issues reported on the owned loopback DB |
| Focused independent Sol review | No actionable product defect found; read-only review of RPC, locks, journal and v1 compatibility |
| Python syntax and diff whitespace | Passed |

The 100-check HTTP run deliberately loses all six committed grant/revoke
responses: reviewer grant/revoke, moderator grant/revoke, support grant/revoke.
The proxy receives the successful real PostgREST response, then closes the client
connection. The server receipt exists before retry. A separate CLI process sends
identical request bytes and gets the original receipt, even after an intervening
opposite action, with no additional audit or authority change.

Duplicate CLI processes and conflicting service HTTP requests are held behind
the actual per-request database lock. The harness observes **two waiting database
transactions** before releasing it. Exact duplicates return one receipt and one
audit event; conflicting bodies produce one winner and one conflict. Checks also
cover human/anonymous denials, credential-role mixing, scope, independence,
expiry equality, unchanged historical void RPC behavior, session cleanup and
credential scans of every journal, CLI output and HTTP trace. SQL 516 adds strict
shape/type/version validation, expired/pause recovery, unavailable accounts,
upper expiry boundary, private table privileges and update/delete/truncate guards.

## Historical failures remain failures

The exact committed baseline operator CLI/smoke was run **before the new migration**.
It stopped after **79 passing assertions** when `challenge_appeal_v1` returned
HTTP 403 instead of producing the response-loss fixture. After the upgrade,
historical SQL 494 stopped after 13 passing assertions, SQL 506 after 50 and SQL
507 after 13; each exited 3 without finishing its TAP plan. Their error was
`challenge_session_required` for a suspended account, through access status or
appeal. They are not reported as passing regression suites.

Inspection links the failure path to the existing account-deletion migration's
session guard using `challenge_actor_unavailable_v1`, which includes suspension.
This slice does not change that behavior. The new explicit `--administration-only`
smoke mode exercises this task's administrator contract; the default complete
human/operator matrix retains its existing assertions and remains affected by
the historical failure. No broader operator acceptance is claimed.

## Runs, reproducibility and retained failures

Private local evidence is retained at
`/private/tmp/gametime-admin-recovery-lab-20260918` (mode 0700). It includes
`baseline-run.log`, `baseline-evidence/`, all three `admin-run-*.log` and
`admin-evidence-*/` directories, timestamped SQL TAP logs/results,
`upgrade-before.txt`, `upgrade-after.txt`, `upgrade-results.json`,
`tested-source.json` and `cleanup-results.json`. Journals are mode 0600 and
credential-free. Generated administrator/human credential and environment files
were removed after disposal. Setup stdout was minimized to exclude credentials.

Commands actually used, from the isolated checkout:

```sh
python3 scripts/tests/beta-operator.test.py
python3 scripts/beta-operator-smoke.py --administration-only \
  --connection-file /private/tmp/gametime-admin-recovery-lab-20260918/connection.json \
  --work-dir /private/tmp/gametime-admin-recovery-lab-20260918/admin-work-3 \
  --evidence-dir /private/tmp/gametime-admin-recovery-lab-20260918/admin-evidence-3
python3 /private/tmp/gametime-admin-recovery-lab-20260918/sql-tests.py 516
```

`setup.py` bootstrapped only the task-owned stack from cached images and all 81
baseline migrations. `upgrade.py` compared old data/functions/ACLs around the
atomic forward migration. `sql-tests.py` expands existing fixture includes and
runs pgTAP through container-local `psql`; every suite rolls back. These local
helper sources remain with evidence. To reproduce, allocate a fresh owner,
unused loopback ports, new private credentials and empty work/evidence directories
using the smoke connection-file contract; the recorded stack no longer exists.
Run SQL and HTTP suites sequentially on a single stack. Do not use another
checkout's stack or run its reset scripts.

Failures/corrections retained separately from final passing checks:

- Initial setup stopped on a null Docker IPAM entry, before resource creation.
  Then reserved-role bootstrap required the owned database's `supabase_admin`;
  corrected locally without changing application SQL.
- Initial SQL invocation lacked pgTAP/search path; added the repository test
  runner's extension setup. The first advisor connection omitted the generated
  local password; the environment-supplied retry passed.
- Focused HTTP run 1 passed 80 checks. Added both remaining scoped cases and
  deterministic overlap checks. Run 2 stopped after 24 checks because SQL 516's
  deliberate `TRUNCATE` denial test was running concurrently: its exclusive
  table lock and the fixture gate created a confirmed test-only deadlock with
  HTTP. SQL 516 passed 58/58. HTTP run 3 ran alone and passed 100/100; no product
  change or assertion waiver was used to obtain that result.
- Cleanup's first comparison formatter assumed every old container had an owner
  label. The task resources had already been removed. Read-only comparison was
  corrected and recorded concurrent changes separately below.

Tested migration SHA-256:
`984312a676541b1c58c1090793aa356a9a4112ab431bc6b6994155d3e0917f31`.
The exact tested CLI, smoke and SQL/unit source hashes are in `tested-source.json`.

## Resource disposition and limits

Owner: `gametime-p11a-operator-admin-recovery-20260918`. New network
`10.252.200.0/24`, one new data volume, PostgreSQL `17.6.1.143`, GoTrue `v2.192.0`
and PostgREST `v14.14`. First-start bindings were DB `127.0.0.1:65412`, Auth
`:65413`, REST `:65414`; the response-loss proxy used `:65411`. Ownership and
loopback bindings were checked before fictional actors. Nonloopback probes were
refused. No retained stack or credential file supplied fixtures.

All three owned containers, their volume and network were stopped/removed after
verification. All four ports refuse connections. Before teardown, fixture gates
were closed, sessions were zero and `cron.launch_active_jobs=off`; zero cron jobs
executed. Existing migrations defined four active cron rows, but job launching
was disabled from the first database start. No schedule was activated by this task.

The final inventory found 206 pre-existing containers identical. Three
`gametime-review-monitor-86b5087001-*` containers disappeared and three retained
account-deletion containers had metadata changes during the session; this task
did not start/stop/remove them. Thus no machine-wide unchanged-state claim is
made. Only the verified owner-prefixed resources were cleanup targets.

No native/physical/human/hosted/load/full-release acceptance was performed.
Historical Personal/Solo/charity agreements, existing dated reports, source
policies and readiness values are unchanged. This is local administrator recovery
implementation with explicit historical regression failures, not a readiness
or deployment decision.
