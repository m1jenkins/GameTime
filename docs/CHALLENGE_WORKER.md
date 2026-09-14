# Challenge locking and worker transactions

Prompt 4 changes the existing fictional `challenge_*_v1` implementation. It does
not open admission, activate sources, publish a community or enable money.

## Lock order

Ordinary reads and previews validate the authenticated actor and take only a
shared lock on its `auth.sessions` row. They do not acquire the gate or actor
mutex. Session expiry and active-account status are rechecked after the wait.
A revocation/deletion which wins that row lock denies the request; an authorized
transaction which wins first finishes before revocation can commit.

Mutations acquire these scopes in order:

1. Shared control-plane gate, then the calling actor mutex, then session SHARE.
2. A service request scope when needed, then all affected challenge UUIDs in
   ascending order. Never acquire another actor mutex after a challenge lock.
3. All affected profile UUIDs in ascending order, including an invitee not yet in
   the roster. Multi-challenge blocks lock the union of profiles once.
4. The challenge's lobby, link, member, consent and source rows. A challenge lock
   serializes these writes; link redemption and revocation acquire it before
   locking an existing link row.

Profiles coordinate admissions made by different callers on different
challenges. Friend freezes lock the bound roster; personal and community
admission lock the entrant. Admission/session checks and time-sensitive cutoffs
are repeated after resource waits. New personal commitments lock the entrant
before creating their new, unpublished challenge UUID.

Control-plane changes alone take the gate exclusively. Reads bypass it; safe
reviews and exits bypass admission/processing eligibility and retain their
existing session/resource locks. Exit reconciliation still runs synchronously
at transaction commit through the existing deferred trigger.

## Worker protocol

For new local work, call `challenge_prepare_worker_invocation_v1(invocation_id,
scope, limit)` and commit it before `challenge_dispatch_worker_invocation_v1`.
The dispatch response contains the claims; call
`challenge_complete_claim_v1(id, claim_token)` in a separate transaction for
each returned claim. `scripts/challenge_worker.py` implements this protocol for
the existing local operator CLI. Each RPC is a separate HTTP request; three
bounded transport attempts and five completion lanes isolate individual request
failures. The operator uses a five-second network timeout and a default limit of
20. The accepted scope is either the exact `{version,kind:due}` object or an
explicit, server-validated list of at most 50 existing challenge IDs.

Claims are limited to 1–50 coordination rows with `FOR UPDATE SKIP LOCKED`.
P5 discovery filters terminal history through a partial live-lobby index, checks
availability once per distinct live actor, and joins directed block edges as sets.
It still reads the eligible live inventory once per batch; exact status counts
also remain linear in live work. It does not tick a challenge or hold
challenge/profile locks. The run ID has an immutable receipt;
an exact retry returns the same tokens and a changed limit is rejected.

Each challenge has one private durable coordination row. Leases last 60 wall
clock seconds. Acquisition increments total attempts and the consecutive attempt
budget. An expired lease can be replaced with a fresh token; a stale token cannot
apply work. Five abandoned or failed attempts exhaust the budget. Item failures
roll back all lifecycle effects and schedule exponential backoff (2, 4, 8, 16
seconds before attempts 2–5, capped at 300 seconds). Success resets the consecutive
budget. Business deadlines continue to use the challenge clock, independently
of lease/backoff wall time.

Completion locks its challenge, then its coordination row, checks the token and
lease again after waiting, and rechecks only that challenge's due state. It keeps
the result and immutable completion receipt in the same transaction. Exact
completion retries return the saved result even after another work cycle. A
failed request does not stop completion attempts for other leased items. Use a
new run ID to recover abandoned leases; replaying the old run ID deliberately
does not create fresh tokens.

Processing pause returns no new claims and writes a paused heartbeat. A claim
completed after a pause is released without lifecycle changes. Cancelled/terminal challenges and existing
finals are excluded from discovery. Direct safe ticks of cancelled drafts do
not keep incrementing their revision. Notices still grant 48 hours from actual
publication; reviews grant 72 hours from filing.

The local invocation records its exact scope, limit and request identity before
dispatch. Replaying the same invocation returns the saved claim response;
changing its scope or limit is rejected. Transport retries are bounded at three
attempts, and a failed item is isolated from the other claims. A dead item can
be selected through the privileged `challenge_recover_failed_item_v1` boundary
for one exact, audited retry; earlier attempts, errors, totals and receipts
remain preserved. Recovery does not reset other items or rewrite a result,
review or consent.

`challenge_operations_status_v1` remains the restricted diagnostic projection
with its existing failed-item detail for privileged selection. The separate
`challenge_local_worker_status_v1` projection is sanitized: it reports only
bounded state, counts, timestamps and SQLSTATE codes. It distinguishes a
healthy empty pass, backlog, pause, disablement and failure. Snapshot
invocations use the existing server-time capture RPC and retain its
at-most-once 15-minute capture and at-least-15-minute disclosure rules.

The restricted projection reports overdue notices/reviews, active and
abandoned leases, scheduled retries, dead-letter counts and at most 50 failed
work summaries. It exposes IDs, attempts, timing and SQLSTATE only to service
callers. Historical batch failure counts remain included. Dead letters require
operator investigation; no automatic infinite requeue or general queue framework
is introduced.

The old `challenge_run_batch_v1` returns existing historical receipts, but rejects
new runs with `challenge_use_claim_batch`. A SQL function cannot commit between
items, so silently keeping that execution path would defeat the new contract.
The P2 harness remains unchanged for its historical baseline; its P4 comparison
adapter uses the new driver. SQL test adapters exercise behavior inside rollback
transactions; the real-session and HTTP runs establish transaction isolation.

## P5 history and projection bounds

New history pages use a private ordering projection and keyset ranges preserving
`coalesce(final.recorded_at, ends_at) DESC, starts_at, id`. A page requests at most
50 rows plus one lookahead; server cursor records contain no history ID array.
The cursor stays actor/section-bound with a two-minute lifetime. If a new history
entry, exit or final changes that actor's history ordering, the next page returns
`challenge_page_expired`; refresh starts the new order. It never silently skips
or duplicates a changed agreement. Existing offset snapshots remain readable
through their original lifetime. Other sections keep their existing snapshots.

Every row uses current membership/privacy projection. Sections validate the
session before reading and again before returning, including wall-clock expiry
during slow work. The private actor-parameter projector is not callable by clients.
Neither social content nor facts are copied into ordering metadata. Member changes
refresh only that member; lobby/final ordering changes refresh the affected roster.
The original agreements, consent, facts, results and immutable retries are intact.

The measurements and remaining query bounds are recorded in the
[P5 completion report](../outputs/reports/2026-09-11-p5-completion.md).
