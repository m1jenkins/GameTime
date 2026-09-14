# P11A local recovery handoff — 2026-09-14

## Outcome and source identity

This is a bounded local-only P11A implementation. It is **NOT LANDED**: no
push, pull request, deployment, hosted mutation, signing, device installation
or merge into `main` was performed.

- Worktree: `/Users/user/.treehouse/GameTime-54367f/3/GameTime`
- Branch: `fm/gametime-p11a-local-recovery-20260913`
- Main/base at intake and handoff: `885e8ad3286b14b98650299659a658fdb68db94b`
- S2 imported completed tip: `ddc4d805d0793613059d4fe3cf4df23a573c6ac6`
- P8 imported completed tip: `8674e071e1811fba1f57ba0d275e55310388f52a`
- S2 integration merge: `fa1b4d9fab24858e318250fe10bc621890aa2f91`
- P8 integration merge: `07fd61b693d3f7545beba3cd31f8ffaba431cf9a`
- Exact pre-P11A combined candidate: `07fd61b693d3f7545beba3cd31f8ffaba431cf9a`
- Final P11A code before this handoff report: `27b18793c04b9f7ab8683c79f0931f37cd4a8270`
- Scoped fresh-session guard fix: `2640b4d1412782a63304daca35024df7f0b7e3c8`
- Report commit: recorded in the private evidence index after this report is
  committed.

The pre-P11A candidate has parents
`fa1b4d9fab24858e318250fe10bc621890aa2f91` and
`8674e071e1811fba1f57ba0d275e55310388f52a`; the S2 merge has parents
`885e8ad3286b14b98650299659a658fdb68db94b` and the S2 tip. The consolidation
had no conflicts, no manual hunk selection, and passed `git diff --check`.
Main's newer documentation and evidence, both dated completion reports, and
the original S2/P8 ancestry were retained. Historical reports and failures
were not rewritten.

## Implemented local slice

Migration `supabase/migrations/20260914041524_challenge_local_worker_recovery_v1.sql`
adds private, service-only journals for worker invocations, snapshot
invocations, individual recovery requests, worker audit entries and heartbeats.
The new public boundaries are:

- `challenge_prepare_worker_invocation_v1`
- `challenge_dispatch_worker_invocation_v1`
- `challenge_recover_failed_item_v1`
- `challenge_prepare_community_snapshot_invocation_v1`
- `challenge_dispatch_community_snapshot_invocation_v1`
- `challenge_local_worker_status_v1`

The existing claim/complete RPCs and completion receipts remain the lifecycle
boundary. A worker invocation stores its immutable UUID, exact scope, SHA-256
scope digest and limit before dispatch. The server accepts only the versioned
`due` scope or an explicit list of at most 50 existing UUIDs, with exact replay
required and scope/limit conflicts rejected. Defaults are limit 20, three
bounded transport attempts, a five-second caller timeout, five completion
lanes, 60-second leases, five consecutive attempts and exponential 2/4/8/16
second backoff capped at 300 seconds. A stale or expired token cannot complete
work; a fresh invocation identity is required to reclaim an abandoned lease.

Completion failures are isolated per item. After five failed attempts the item
is dead-lettered. `challenge_recover_failed_item_v1` selects exactly one dead
item through the privileged boundary, records the prior state/attempts/total
attempts/error and authorized principal, audits the recovery, and resets only
that item for one exact retry. It does not rewrite results, reviews, consent,
other claims or historical receipts.

Snapshot invocation wrappers use server time and the existing capture RPC. They
retain at-most-one capture per 15 minutes and at-least-15-minute disclosure,
including under-five suppression and delayed/failed invocation behavior. The
existing restricted `challenge_operations_status_v1` remains the source for
authorized failed-item selection. The new generic status projection contains
only bounded status, counts, timestamps and SQLSTATE codes; it omits actors,
challenge/member IDs, invite/claim tokens, request bodies, Health facts and raw
server errors. Paused, disabled, healthy-empty, backlog and failure states stay
distinct; an empty pass writes a heartbeat.

`scripts/challenge_worker.py` implements the prepare/dispatch/complete and
snapshot wrappers while preserving its historical claim-batch compatibility.
The existing CLI's local `run-once` path supplies the fixed due scope and limit
20. No scheduler registration, alert recipient, credential, operator-platform
expansion, account deletion or retention-policy-dependent behavior was added.

During final-source validation, a fresh privileged session defect was found:
the scoped claim helper did not set its write guard after a separate dispatch
transaction. The one-line fix is in `2640b4d...`. The permanent SQL regression
in `supabase/tests/509_challenge_local_worker_recovery.test.sql` clears the
transaction-local guard between prepare and dispatch and requires one real due
claim. It passed after the fix and would return a failed dispatch if that guard
line were removed. The earlier shared-transaction test result is retained as
historical evidence and is not treated as this fresh-session proof.

## Verification performed

All final-source evidence is private under
`/Users/user/firstmate-workspace/data/gametime-p11a-local-recovery-20260913/private`.

- Python worker tests: 4/4 passed; `py_compile` passed for worker, CLI and
  tests; `check-iphone-product.py` passed.
- Final fresh-session worker SQL: 43/43 TAP assertions passed, including
  response loss and exact replay, duplicate invocation, scope/limit conflict,
  pause/resume, expired/replaced claims, failure isolation, five-attempt
  exhaustion, restricted individual recovery, audit/redaction and delayed
  snapshot behavior (`509-pgtap-fresh-session-final.log`).
- Final-source upgrade validation: 210/210 assertions passed. Populated
  two-/five-person agreements, historical Personal terms, consents, reviews,
  ACLs, old receipts and authorized fact access were preserved
  (`p8-populated-upgrade-after-final-source.log`).
- Final-source P8 actual-session race reproducer: 27/27 passed, 0 failed,
  0 skipped (`beta-p8-concurrency-final-after-p11a-fix.json`). This includes
  revocation ordering and suspended friend admission. Privacy1's authorized
  read-first case is not interpreted as proof of initially ungranted access.
- Existing focused SQL suites were also rerun against the owned final DB:
  `497` produced 19/19 and `504` produced 40/40. The retained `506` suite
  still has its original isolated 49/49 pass. A repeat against the already-used
  task DB produced one fixture-history mismatch (48 passes; expected two global
  reports, observed four). A direct private inventory before that transaction
  found two retained reports—one scoped and one unscoped—and no support grants;
  the test then added its two reports. The extra report scopes and the support
  authorization boundary were therefore preserved and verified, while the
  empty-database cardinality assumption was invalid for that populated fixture.
  The failed populated receipt is retained as a disconfirming environment
  result, not counted as a pass or silently normalized. A newly owned clean-DB
  reconstruction was attempted but not adopted as acceptance because a
  schema-only copy lacks database bootstrap defaults (including the historical
  scheduler extension, private HMAC seed and runtime/pgtap setup); its logs are
  retained separately. The original clean 49/49 result remains the correctly
  isolated community contract result.
- Actual owned local HTTP runner proof covered an empty pass with a committed
  heartbeat, deliberate post-commit response loss, exact replay after process
  restart, duplicate prepare, invalid scope, scope/limit conflict and bounded
  sanitized status. A separate nonempty fictional proof used three independent
  due items: two separate-session prepare/dispatch interleavings returned one
  exact claim; one completion response was discarded and replayed exactly;
  one expired claim was rejected and replaced with attempt two; and one item
  failed five times, became dead, was individually audited/recovered, then
  completed on attempt six. All three ended in review with original end dates
  preserved. No real participant or Health data was used.
- Native Simulator acceptance used only the task-owned
  `GameTimeP11ARecovery-20260914` iPhone 17 simulator
  (`B2E26A46-CAE3-4643-A292-589906E8945D`) and task-owned DerivedData. An
  initial controller run is retained only as a historical observed output
  (`private/native-matrix/native-ea6b0d84-8728-4d8c-b85f-4c61eb1c0718.xcresult`)
  with a 21/22 result and a local Auth email/password-disabled diagnosis; its
  separate saved receipt is not present in the private evidence root, so it is
  not counted as acceptance. The pure XcodeBuildMCP suite was observed to
  return `timed out awaiting tools/call after 300s`; no saved transport receipt
  was located, and this is not a test failure. Later direct owned `xcodebuild`
  runs passed 22/22 for the authenticated matrix and 22/22 for recovery, each
  with zero failures/skips. Cleanup reports show gates off, seven fictional
  actors revoked and no cleanup failures. No physical iPhone/Watch, Health
  access, human acceptance or release acceptance was claimed.
- Security catalog evidence records five new private/RLS-protected relations,
  zero public or service-role table SELECT grants, service-only worker RPC
  execution, fixed definer `search_path`, and 18/18 readiness entries false.

## Resources, exposure and preservation

The task evidence root is mode 700 and raw evidence remains private. The
task-owned stack used network
`gametime-p11a-local-recovery-20260913-network` (`10.253.250.0/24`), DB port
65322 and API port 65321. A first CLI start stopped before containers because
Docker's address pool was exhausted. There were then two separate broad-binding
CLI stack episodes. The earlier episode, timestamped 2026-09-14 04:30:48 UTC,
is recorded by `exposure-before-stop.txt`; the later restart is recorded by the
`api-stack-attempt2` start, binding and exposure receipts. Both published owned
API/DB (and Studio/Mailpit in the captured stack) on `0.0.0.0`/`::`. Each was
detected and only the task-owned services were stopped. The later restart reused
the retained task DB volume after it already held fictional P8/P11 data, so the
final exposure probes must not be read as an empty-database-before-fixture-
admission claim.

The corrected task-local setup used explicit `127.0.0.1` bindings for the
owned DB and Kong/API, internal-only Auth/REST bindings, and Docker Engine
29.6.2. `docker inspect`, `lsof`, non-loopback IPv4, IPv6 loopback and
non-loopback reachability checks were performed for the corrected setup. Final
probes showed only loopback listeners and refused the host's non-loopback
address and `::1` for API/DB. Final owned containers are stopped;
the task network, DB volume, dumps and evidence remain retained. The owned
Simulator is shut down. Prior stacks, devices, networks, previews and source
checkouts were not stopped, reset, reused or reconfigured.

The explicitly scoped advisor check
`supabase db advisors --db-url <task-owned loopback URL>` remains
unperformed/unavailable: no actual advisor call/result is evidenced in the
retained task receipts. The separate CLI SQL/migration connection attempt in
`sql-focused-final.log` and `sql-focused-final-v2.log` returned
`LegacyDbConnectError` with `PgClient: Failed to connect`; that failure is not
attributed to an advisor. Direct psql, pgTAP, actual role/RLS catalog checks
and the explicit local target were used instead. No further CLI/default-linked-
target retries were made. No hosted MCP/default target, login, shared CLI
repair, external alert, hosted schedule or real credential was used.

## Remaining limitations and dependency

This branch supplies local implementation evidence only. It does not accept
real-source ingestion, P8/P9 product journeys, hosted operation, capacity,
physical source/device behavior, human comprehension/accessibility, TestFlight,
release or distribution. P10 cadence/thresholds remain proposed; no retention
policy was invented and policy-dependent deletion remains deferred. The
existing owner decisions `gametime-beta-source-acceptance-b7` and
`gametime-beta-release-readiness-b7` remain unchanged.

The next dependency is an accepted real-source P8/P9 contract and, separately,
captain-approved exact hosted target/settings/actions. Only after those inputs
can this local protocol be reviewed for source-backed integration and hosted
operation. The branch is ready for review and remains **NOT LANDED**.
