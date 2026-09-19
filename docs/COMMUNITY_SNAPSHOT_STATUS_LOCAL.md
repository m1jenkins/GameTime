# Local community snapshot status

`public.challenge_community_snapshot_status_v1(p_id uuid)` is a service-only,
read-only projection for one explicitly selected published cohort. It adds no
monitor process, schedule, alerts or operating threshold. The 1,800-second
warning in [hosted preparation](BETA_HOSTED_PREPARATION.md) remains a proposal.
The existing service role is broad local authority, not a least-privilege hosted
monitor credential. No app or human operator role receives access.

Pass the selected cohort ID to the RPC. Null selection fails with SQLSTATE
`22023` / `challenge_snapshot_selection_required`; no cohort is selected by
recency, discovery, participant membership or default. An unknown or unpublished
ID returns `cohort_unavailable` without echoing the ID. Anonymous and authenticated
callers lack EXECUTE, and the function also checks the existing service guard.
The new function is STABLE with a fixed empty definer search path and supports
PostgREST GET as well as POST. It takes no locks and writes no audit or heartbeat.

## Contract

| Field | Meaning |
| --- | --- |
| `observed_wall_at` | Server statement timestamp, always wall clock. |
| `reference_clock` | Current capture-age reference: `fixture`, `wall`, `unavailable`. |
| `snapshot_reference_at` | Current fictional time when configured; otherwise the wall observation; null if runtime is absent. |
| `capture_state` | `cohort_unavailable`, `runtime_unavailable`, `fixtures_disabled`, `discovery_disabled`, or `enabled`, in that precedence. These are the existing capture RPC's publication/runtime authorization gates. Admission, processing and actor allowlisting do not authorize capture. |
| `snapshot_state` | `unavailable` for an unpublished selection; `missing` when there is no capture; `clock_unavailable` when a retained capture lacks a runtime clock; `clock_ahead` when the stored capture is ahead of the current reference; otherwise `recorded`. No fresh/stale policy is implied. |
| `last_capture_at` | Maximum actual `captured_at` from the selected cohort's snapshot rows, including snapshots whose count is null. Never derived from invocation success. |
| `capture_age_seconds` | Whole seconds from `last_capture_at` to `snapshot_reference_at`; null for missing/unavailable/ahead-of-clock captures. A future capture is never clamped to a fresh zero. |
| `last_prepared_wall_at` | Latest journal preparation time, including an invocation waiting for dispatch. Preparation is not an attempt or capture. |
| `last_attempt_wall_at` | Latest recorded `dispatched_at`, including failed dispatches. The existing journal records the dispatch call's start time; it is not a completion timestamp. |
| `last_attempt_state` | `none`, `checked`, `failed`. `checked` includes the existing capture throttle's successful no-op. A new prepared invocation does not hide a preceding failed attempt. |
| `last_attempt_error_code` | Last recorded attempt's five-character SQLSTATE or null. No raw response or error message is read or returned. |
| `last_successful_invocation_wall_at` | Latest journal dispatch time in `dispatched` state, including throttled no-ops. This is never proof of a new capture. |

All invocation fields are restricted to the selected cohort. Prepared-only
invocations leave attempt and success timestamps null. Replaying an invocation
returns its existing receipt and cannot advance any of these stored timestamps.
A direct call to the original capture RPC can create a snapshot without an
invocation journal entry; the projection reports those facts independently.
Rejected calls that never reach a durable dispatch record are not observable in
this projection. An unavailable runtime does not erase historical captures or
journal timestamps.

**Clock limitation:** old snapshot rows store the challenge-clock timestamp but
not the clock mode at capture time, a wall timestamp or a clock-generation ID.
`reference_clock` describes the reference now, not the historical capture's
origin. Age is a difference in those stored/current clock coordinates; after
fixture-clock changes it is not proof of elapsed wall time. Do not infer a
historical wall capture from a current `wall` label. Invocation wall timestamps
remain separate and cannot repair missing capture provenance. This change does
not rewrite records or manufacture provenance.

## Privacy and unchanged behavior

There are no counts, Health values, actor/challenge/invocation identifiers, raw
responses, disclosure states, participant-presence signals or member-based
branches in the response. The function never queries membership or count values.
Crossing the five-person threshold cannot change its fields. Capture existence
below five is reported without implying that participant counts are disclosable.

The existing [community contract](PRIVATE_COMMUNITY_V1.md) still requires at least
five eligible people and a qualifying snapshot at least 900 seconds old for
ordinary count disclosure. Reads cannot capture, bypass the capture throttle,
advance disclosure, change runtime rules or send alerts. No P7, source, money,
retention, release or hosted gate changes.

## Reproduce local verification

From this branch, with Docker running and the three image versions named in the
runner cached:

```sh
python3 scripts/community-snapshot-status-verify.py \
  --evidence-dir /tmp/gametime-snapshot-status-verification
```

The evidence directory must be new. The runner creates a unique labeled network
and fresh database, applies the complete migration chain and publishes Postgres and PostgREST
only on numeric loopback ports. The security advisor runs against that explicit
local database; its result is recorded separately from focused tests. It never reads local/hosted credentials, resets an
existing stack, or reuses retained data. Historical cron execution is disabled
from first database start. Auth migrations are applied, but HTTP uses fictional
locally signed JWTs rather than claiming real sign-in coverage. The runner
removes only its own labeled containers/volumes/network, including after failure.

Focused pgTAP covers gates, clocks, first/missing/stale captures, replay,
throttling, failure, unavailable runtime, privacy, grants and actual role calls.
HTTP verifies signed roles, the same operational cases, GET/SQL read-only calls,
and hashes of every app/public/auth table before and after status reads. The
existing progress and worker suites also run. The integrated runner also requires safety (494) and both suspension/community
suites (506/507) to pass with complete TAP plans. The snapshot suite is now 518
to keep review-monitor suite 515 distinct. Historical failure records remain
unchanged; failures are not accepted by this candidate.

Raw receipts remain private: they contain fictional fixture rows. Only the
sanitized example and verification summary belong in the review report. See the
[performed verification](../outputs/reports/2026-09-19-community-snapshot-status.md)
for the exact source, outcomes and remaining limits.
