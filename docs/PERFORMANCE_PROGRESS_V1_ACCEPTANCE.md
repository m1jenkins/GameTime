# Phase 3(c): named milestones and manual progress

Implemented locally September 5, 2026. The separate owner ledger adds named
milestones, manual check-ins and append-only milestone status changes to the
existing 28–90-day simulated performance commitment. It does not publish a
result, change agreement terms, establish qualifying proof or release a slot.

## Contract and reversible defaults

- A milestone has an immutable owner-agreement binding, name, due instant and
  server creation time. Names contain 1–80 characters. A due instant can be
  before the commitment starts (for choosing an event), but must be at/after
  creation and strictly before the commitment deadline. To replace a plan,
  retire its milestone and create a new one; previous definitions remain.
- Milestones start `planned`. Owners can mark them `completed`, reopen them as
  `planned`, or mark them `retired`. Retirement is terminal. Status changes
  name the exact previous **status revision**, which is the sequence of the
  milestone's last creation/status entry. Check-ins do not change that revision.
  Repeating a status with a new request is rejected; exact retries recover.
- A manual check-in contains 1–500 characters and a person-reported occurrence
  instant, optionally bound to a milestone on the same agreement. Occurrence
  cannot predate agreement creation, predate a linked milestone, or be in the
  future. Retired milestones reject new linked check-ins. An unlinked check-in
  remains available for general progress. Server receipt time stays distinct.
- Text is bounded plain text. Blank, padded and control-character inputs fail;
  inputs are never silently trimmed. There are no files, URLs as source inputs,
  proof attachments, automatic event nominations, device imports or provider
  operations. Arbitrary text, including a claimed fast time, has no authority.
- At most 32 milestones (including retired ones) and 512 total history entries
  can be saved per agreement. Creation, check-ins and status changes all count.
  New writes are admitted after agreement creation and strictly before the
  frozen deadline, while the agreement is open and the separate progress gate
  is enabled. These local bounds are reversible defaults, recorded in D126.
- Reaching a due date or the agreement deadline does not mark a milestone
  missed, complete an attempt set, change a result or settle money. A milestone
  can be marked done after its due date while still inside the write window.
  Full history and gate shutdown never prevent the existing safe-exit RPC.

Each mutation uses a private `(actor_id, request_id)` namespace separate from
agreements and attempts. Its saved identity contains the operation and every
submitted argument, including status revision and report time; timestamps are
canonical typed UTC instants. A changed payload fails. A committed retry returns
its original receipt even after later milestone changes, capacity exhaustion,
closure, the deadline or gate shutdown. Recovery still requires the active
owner and matching unexpired session. Deletion or session revocation denies it.

## Storage and APIs

The [additive migration](../supabase/migrations/20260905204838_performance_progress_v1.sql)
adds six private `app.performance_progress_*` tables: runtime, milestones,
entries, requests, retention and gate audit. Every table has RLS, revoked client
and service table grants, and owner/context guards. History rejects updates,
deletes and truncation; only the runtime singleton can be updated. API grants
are explicit. Clock seams are private and unavailable to API roles.

| RPC | Caller and behavior |
| --- | --- |
| `set_commitment_progress_enabled_v1` | Service only; audited separate default-off gate |
| `create_commitment_milestone_v1` | Active owner; exact-request name and due instant |
| `record_commitment_progress_v1` | Active owner; exact-request note, report time and optional milestone |
| `set_commitment_milestone_status_v1` | Active owner; exact-request status with expected prior status revision |
| `get_commitment_progress_v1` | Active owner; bounded history and milestone states, including after gate shutdown or safe closure |

All owner paths lock owner profile → matching Auth session → progress runtime →
agreement, then recheck natural session expiry after blocking locks. They reuse
the existing agreement/deletion ordering. A friend, reviewer, another owner,
anonymous caller or service acting as the owner receives no progress access.
No user metadata claim grants authority.

Reads accept a limit of 1–100 (default 50), `after_sequence` (default zero) and
an optional `through_sequence`. The first page captures the current upper
sequence. Continue with the returned `next_after_sequence` and the same
`through_sequence` until `has_more` is false. Both entries and the at-most-32
milestone states refer to that upper sequence; concurrent appends do not move
items between pages or leak later status changes into that history snapshot.
`server_now` and `new_writes_allowed` are current hints, not mutation authority.
Milestones and every entry carry `provenance: owner_reported` and
`counts_as_proof: false`.

The scorer snapshot and pure evaluator are unchanged. Progress is not included
in their input contract. Even an owner report naming a qualifying time, or a
manually completed milestone, cannot satisfy organizer-source requirements,
confirm a complete/no-attempt set or shorten a review window.

## Retention and later client boundary

The first entry creates a separate `performance_progress_v1` retention hold.
The legacy raw-evidence purge does not touch this ledger. Safe closure and
account deletion retain definitions, history and exact receipts against the
existing agreement/tombstone; deleted owners lose access. No new deletion
trigger was needed because progress never mutates or releases the agreement.
This is a local fictional hold pending a progress-specific retention policy,
not an approved duration for real personal notes. Release, purge and support
access remain later work.

A future native client must persist the complete typed request before sending,
use explicit exact retries, and clear progress caches on account changes or
failed authorization. Render names and notes as untrusted plain text, preserve
the distinction between report time and receipt time, and label completion as
self-reported progress. No native screens, native request store or HTTP/device
acceptance were added in this backend slice.

## Verification

- Focused SQL: **115 assertions passed** for private table/function grants,
  owner/session boundaries, exact recovery, status transitions, text and date
  bounds, microseconds/UTC offsets, stable pagination, capacity, unchanged
  scoring snapshots, safe exits, deletion and legacy retention.
- Real-session SQL: **22 assertions passed across nine observed transaction
  waits** for exact notes, changed payloads, competing statuses, exact status
  retries, gate shutdown, natural session expiry, withdrawal, session revocation
  and deletion. Only the authorized five entries survived before test cleanup.
- Pure Deno: **6 additional tests passed** showing that manual progress and even
  a forged proof flag cannot alter missing proof, no-attempt silence, a success,
  corrected proof, missing completeness or the full review window.
- Persisted loopback smoke passed: a real 60-day agreement, milestone, manual
  5:59 claim and completion leave the evaluator's unresolved result unchanged.
  Public exact recovery after gate shutdown returns the original receipt. The
  transaction rolls back every fictional fixture and gate change.
- Local schema lint and warning/error security/performance advisors passed
  with no issues.

The full portable regression gate passed: **65 database files / 2,991 SQL
assertions, 613 Deno tests and 103 portable Swift tests**. The new migration is
recorded locally as `20260905204838`. Final cleanup confirmed progress and
attempt gates off, commitment admission off, empty commitment allowlist, zero
open commitment slots, zero progress entries/requests and zero fictional
progress sessions. No native source changed; no HTTP, device or hosted
acceptance is claimed.

Reproduce from the repository root with the local stack running:

```sh
./scripts/test-all.sh
supabase test db --local supabase/tests/473_performance_progress.test.sql supabase/tests/474_performance_progress_concurrency.test.sql
deno run --allow-run=psql --allow-read=scripts/examples scripts/performance-progress-local-smoke.ts
supabase db lint --local --schema app,public --level warning --fail-on warning
supabase db advisors --local --type all --level warn --fail-on warn
```

Logs: `/tmp/gametime-progress-{focused,races,smoke,portable,lint,advisors}.log`.
An initial race harness run stopped on a duplicated temporary-table declaration;
the declaration and only that run's fictional fixtures were corrected before
the passing run. The initial full gate needed local database and Swift cache
access outside the filesystem sandbox and was rerun with that access.

The [Supabase changelog](https://supabase.com/changelog.md), official
[RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)
and [function guidance](https://supabase.com/docs/guides/database/functions)
were checked with CLI 2.109.1. No dependency, extension or platform configuration
change was required. No earlier migration, scoring module, hosted state,
schedule, external message, provider or live-money path was changed.
Accelerated clocks do not establish months of real operation.

## Phase 3(d) handoff

Implemented subsequently as a local backend; see
[following acceptance and the native/Phase 3(e) handoff](PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md).
The original scope below is retained for context.

Add explicit opt-in friend following, bounded selected-progress projections,
revocation, structured reactions and the planned reminder/report/block/support
behavior. This ledger is owner-only: do not grant followers its raw tables,
private notes, exact request payloads, financial amounts or organizer proof.
Define what the owner shares, serialize follow grants/revocation with reads,
and clear cached shared content on block, revocation, deletion and account
change. Following must never amend consent, qualify a manual time or imply
permission to send an external message.

Phase 3(e) still owns durable result notices, review/withdrawal history,
clock-injected lifecycle, immutable finals, post-final support and separately
recorded simulated consequences. Its commits must recheck complete proof
snapshots atomically. Native commitment flows, actual organizer operations,
hosted acceptance, true-mile policies and live money remain separate work.
