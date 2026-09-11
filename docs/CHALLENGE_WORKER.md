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

Call `challenge_claim_batch_v1(run_id, limit)` as one transaction, commit its
response, then call `challenge_complete_claim_v1(id, claim_token)` in a separate
transaction for each returned claim. `scripts/challenge_worker.py` implements
this protocol for the existing local operator CLI. Each RPC is a separate HTTP
request; five bounded lanes isolate individual request failures. The operator
uses a five-second network timeout and a default limit of 20.

Claims are limited to 1–50 coordination rows with `FOR UPDATE SKIP LOCKED`.
Discovery evaluates the work inventory once per batch. It does not tick a
challenge or hold challenge/profile locks. The run ID has an immutable receipt;
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

Processing pause returns no new claims. A claim completed after a pause is
released without lifecycle changes. Cancelled/terminal challenges and existing
finals are excluded from discovery. Direct safe ticks of cancelled drafts do
not keep incrementing their revision. Notices still grant 48 hours from actual
publication; reviews grant 72 hours from filing.

`challenge_operations_status_v1` reports overdue notices/reviews, active and
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
