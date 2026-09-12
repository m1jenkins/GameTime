# P10 local verification evidence

Input: consolidated `fd193e71b12dccbbb680eb78682e0a36cd7b1ffd` (verify exact
identity in `preservation.json`; that machine-readable value is authoritative).
Source: `codex/hosted-preparation-p10` in `/private/tmp/gametime-p10-20260912`.
All production code, scripts, active config and 76 migration files are unchanged.
These artifacts describe local preparation, not P7–P9 or hosted acceptance.

- `access-audit.json`: final read-only catalog audit after all local tests; zero
  violations; full current challenge and other public RPC inventories. Reproduce
  with `docs/release/beta/inspect-access.sql` only on an authorized exact target.
- `focused-sql.json`: 203 assertions in eight unchanged pgTAP files; no failed or
  skipped assertions. `run-focused.py` records the exact psql invocation and
  checks exit code, numbered assertions, final plan and absence of failure/skips.
- `http-denials.json`: 68 local HTTP denials. `http-denials.py` contains the exact
  requests and accepted error codes. The signed fictional JWT deliberately has
  no account/session; this tests gateway roles and denial, not real Apple sign-in.
  Local keys are read privately in memory and never printed or saved here.
- `worker-test.txt`: two existing transport/failure-isolation tests passed.
- `preflight.txt`: expected exit 1, 17 passes and three unconfigured privacy,
  terms and support blockers. Its historical Personal wording is not instruction
  to publish that policy for the new Beta.
- `cli-sql-failure.txt`: preserved CLI `LegacyDbConnectError` at the explicit
  loopback URL. Direct psql provided the actual SQL evidence instead.
- `preservation.json`: base commit, all 76 migration hashes, 539 unchanged tracked
  product/config/test files and 18 closed readiness entries.
- `final-database-state.json`: zero Auth users, profiles or challenge lobbies;
  every runtime flag false after rollback-only fixtures and HTTP denials.
- `stop.txt`: only project `gametime-p10-audit-20260912` stopped; backup retained.
- `review.md`: concise preparation self-review and explicit hosted limitations.

Raw inputs/logs and fixed-target reproducers remain in
`/private/tmp/gametime-p10-audit-20260912`. The database used PostgreSQL 17 and
Supabase CLI 2.109.1, loopback API 59821 / DB 59822, network
`gametime-p10-audit-20260912` (`10.253.217.0/24`). No other stack was started,
stopped, reset or queried. Test seed was disabled; migrations applied on startup.

The evidence Python scripts are retained exact-run reproductions, not general
hosted tools: they require this owned local environment and write to this P10
report directory. SQL tests install pgTAP/dblink only in that disposable database,
run each file with ON_ERROR_STOP, and roll fixture transactions back.

The original automatic Docker pool was exhausted. The first startup also showed
that CLI help's exclusion names differed from runtime-accepted names. After
inspecting occupied networks, the second start used the explicit nonoverlapping
network and runtime-listed exclusions. The first psql catalog query lacked the
standard local password; its authenticated retry succeeded. Sandboxed Docker/CLI
and public-doc DNS access required scoped tool escalation. No approval rejection
or hosted fallback occurred. Private startup logs may contain local keys and are
intentionally not copied into this evidence directory.
