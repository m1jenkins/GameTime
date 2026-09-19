# Local community snapshot freshness — September 19, 2026

Implemented on `codex/community-snapshot-freshness`, isolated from committed
`main` at `9f116ac4954594a8d64467f78a6dca55d3cc2ce4`. Review worktree:
`/private/tmp/gametime-community-freshness-20260919`. No merge or push to main.

The forward migration adds one service-only stable read RPC and one scoped
invocation lookup index. It reuses existing records and returns twelve fields:
necessary timestamps, age and bounded status/error codes. Explicit publication
selection is required. Actual capture age is independent of invocation success;
replay and throttling cannot advance the capture timestamp. Capture authorization
uses fixtures/discovery, independently of processing/admission. Missing runtime,
missing captures, pending preparation, failures and clock rewind remain explicit.

[Contract and reproduction](../../docs/COMMUNITY_SNAPSHOT_STATUS_LOCAL.md).
[Actual sanitized stale/replay example](community-snapshot-status-20260919/sanitized-example.json).
The example's capture age remains **7,200 fixture seconds**, even with a successful
invocation. Fixture capture/age and wall-clock dispatch timestamps are distinct.
No freshness or alert threshold is adopted. Historical snapshot rows have no
wall-clock insertion time or historical clock-origin marker; the projection does
not fabricate either.

## Actual verification

Final command:

```sh
SNAPSHOT_VERIFY_PORT_BASE=58460 python3 scripts/community-snapshot-status-verify.py
```

Supabase CLI 2.109.1, local PostgreSQL 17 stack with all forward migrations.
Owned project `gametime-snapshot-status-m3s2rqx9`, unique Docker network with
loopback binding, no seed/provider credentials, and historical jobs paused before
fictional fixtures. The stack and owned network were removed successfully.

- **99 SQL assertions passed** across community progress/disclosure (508),
  worker recovery/snapshot invocation (509), and new snapshot status (515).
- **39 HTTP checks passed**, including first/missing/stale capture, replay,
  throttled success, SQLSTATE-only failure, disabled discovery, missing runtime,
  under-five privacy, fixture/server clock distinction and clock rewind.
- Actual service GET/POST succeeded; anonymous/no-token callers received 401 and
  an actual local Auth authenticated caller received 403. Null and unpublished
  selections were denied. Preparation and successful invocation remain separate
  from actual capture.
- Status reads preserved complete fingerprints of every application/Auth table
  row and sequence, at each tested state. Auth/fixture setup occurs outside those
  comparisons. The service RPC also passed inside a read-only transaction.
- Local security advisor: **no errors**, executed against an earlier owned stack
  with the identical production migration. Effective-role grants, stable
  volatility and the fixed definer search path are asserted by SQL tests.
- Python compilation and `git diff --check` passed. The copied final SQL inputs
  match the branch files byte-for-byte. [Input hashes and totals](community-snapshot-status-20260919/verification.json)
  and [sanitized HTTP assertions](community-snapshot-status-20260919/http-checks.json)
  retain the exact checks; credentials and raw responses are excluded.

Private local logs remain beneath the macOS temporary directory at
`gametime-snapshot-status-m3s2rqx9`; they are not required to run the checked-in
reproduction command. The code is locally verified, not hosted acceptance.

## Failed attempts and independent baseline failure

The broader, unchanged `506_challenge_private_community.test.sql` passes its first
50 assertions, then stops at line 128 with `challenge_session_required`, following
its suspension step. This also reproduced independently on committed main,
without the new migration or RPC, in disposable project
`gametime-snapshot-status-lucz85_y`. That stack/network was removed. It is an
existing regression-suite failure, not a passing check and not fixed by this
bounded slice. The focused runner includes 508/509/515, not the failing 506 suite.

Earlier development runs failed before completion: Docker's default subnet pool
was exhausted; the runner needed null-IPAM handling and explicit test-container
network selection; direct Cron table updates were denied and replaced by
`cron.alter_job`; a temporarily occupied port range was rejected. One migration
syntax error (reserved variable name) was corrected before passing tests.
Test-only missing-runtime injection initially hit the existing immutable guard;
it now disables/re-enables that trigger only in the disposable fixture. HTTP
harness corrections addressed a Python naming collision, the existing void RPC's
204 response and locally disabled password Auth. These were failed attempts,
not acceptance. All created task stacks/networks were torn down.

No participant-facing string, disclosure rule, historical migration, snapshot
capture/dispatch implementation, P7 source, approved operating policy, hosted
scheduler, alert destination or release gate changed. No message was sent. The
branch adds no automatic polling, capture, recovery or notification behavior.
