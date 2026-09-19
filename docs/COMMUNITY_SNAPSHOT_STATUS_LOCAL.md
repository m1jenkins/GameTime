# Local community snapshot status

`challenge_community_snapshot_status_v1(p_id uuid)` is a service-only, read-only
projection for one explicitly selected published cohort. Call it through
`POST /rest/v1/rpc/challenge_community_snapshot_status_v1` with `{"p_id":"<selected UUID>"}`
or the equivalent GET. There is no default cohort or discovery/list operation.
Null input returns `22023`; an unknown or unpublished selection returns `42501`.
Anonymous and authenticated callers have no execute permission. The local
service credential remains broad; this adds no hosted monitor credential.

The function reads existing publication, runtime, snapshot and invocation
records. It never captures, dispatches, locks, journals, changes disclosure or
sends alerts. It returns neither the selected ID nor invocation IDs, identities,
counts, activity values, stored responses or raw errors. No client UI changes.

| Field | Meaning |
| --- | --- |
| `server_time` | Wall-clock statement time for this read. |
| `capture_authorization` | `enabled`, `fixtures_disabled`, `discovery_disabled`, or `runtime_unavailable`. Missing runtime takes precedence, then fixtures, then discovery. These are the actual capture gates. Admission, processing, actor allowlists and source readiness are not capture gates. |
| `snapshot_age_clock` | Current age reference: `fixture`, `server`, or `unavailable`. |
| `snapshot_clock_now` | Current challenge-clock time: runtime `fictional_now`, otherwise this read's wall time; null if runtime is absent. |
| `capture_status` | `missing`, `recorded`, `ahead_of_clock`, or `clock_unavailable`. Absence of a capture is always `missing`. `recorded` means a row exists, not that it is fresh. |
| `last_capture_at` | Latest actual snapshot row's `captured_at`, in the challenge clock. Null only when no capture exists. Remains visible during disabled/unavailable runtime. |
| `capture_age_seconds` | Whole elapsed seconds between `snapshot_clock_now` and `last_capture_at`. Null for missing capture, missing runtime or a capture ahead of the current clock. Never clamps a future capture to zero. |
| `pending_invocation_prepared_at` | Wall time of the pending prepared invocation, if any. Preparation is not an attempt. |
| `last_attempt_at` | Latest persisted snapshot dispatch attempt's wall-clock timestamp. Replays do not change it. |
| `last_attempt_status` | `none`, `checked`, `disabled` (failed attempt with SQLSTATE `42501`), or `failed`. Derived from typed journal columns, never stored response JSON. |
| `last_attempt_error_code` | Last attempt's five-character SQLSTATE on failure, otherwise null. |
| `last_successful_invocation_at` | Latest dispatched invocation's wall-clock timestamp, independent of the last attempt and last capture. A throttled no-op is a successful invocation. |

Snapshot rows have no historical clock-origin or wall-clock insertion field.
`last_capture_at` therefore is **not a claimed wall-clock capture time**;
`snapshot_age_clock` describes the current age calculation, not the historical
origin of that row. Changing/removing the fixture clock cannot establish real
operating freshness. Invocation timestamps use wall time recorded when dispatch
begins, including on failure; they cannot substitute for capture time. Direct
calls to the existing capture RPC can produce a snapshot without an invocation.
Attempts rejected before journaling, rolled-back transactions and network errors
are not observable in these records. Transport failure is a failed read, never a
fabricated healthy response. This projection reports the latest recorded attempt,
not a complete failure history.

A replay returns the saved invocation receipt without capturing. A new invocation
within the existing 900-second capture interval succeeds without a new capture.
Both retain the old capture timestamp/age. Under five, a capture with a null count
is still a real capture; this endpoint reports no threshold or membership signal.
Existing participant disclosure continues to enforce its five-person minimum
and 900-second delay independently.

No freshness cutoff, polling interval, scheduler or alert destination is added.
In particular, the [hosted preparation](BETA_HOSTED_PREPARATION.md) proposals of
900-second dispatch, 60-second polling and a 1,800-second capture-age warning
remain unapproved operating policy. This local projection does not open any
hosted, source, P7, money or release gate.

## Reproduce verification

From the review branch, with Docker, the Supabase CLI and Python 3 available:

```sh
python3 scripts/community-snapshot-status-verify.py
```

The runner copies config/migrations/tests into a unique temporary project, checks
ports (default 58340–58349; override `SNAPSHOT_VERIFY_PORT_BASE`), allocates its own
nonoverlapping Docker subnet with loopback port binding, and tears down only its
owned stack/network. It never resets or reuses another project. All fixtures are
fictional. Password Auth is enabled only in the copied test configuration;
admin-confirmed test accounts send no email. Historical migration jobs are disabled on the new empty stack before
fixture creation; no new schedule is registered. Logs and sanitized results stay
in the printed directory. Credentials are kept in memory, outside reports.

SQL tests cover the new projection plus existing community, disclosure and worker
contracts. HTTP checks exercise real PostgREST service/anonymous grants and a real
local Auth participant token. Full application/Auth row and sequence fingerprints
must be identical before/after status reads. A read-only transaction also exercises
the service function. Synthetic failure injection exists only in the disposable
DB. See the [performed verification report](../outputs/reports/2026-09-19-community-snapshot-status.md)
for source, results and limits.
