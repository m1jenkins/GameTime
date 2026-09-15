# Local `challenge_*_v1` account-deletion evidence — September 14, 2026

This is local implementation evidence only. It does not authorize hosted
settings, provider operation, Apple revocation, Stripe activity, deployment,
distribution, or a claim about backups.

## Approved scope

The owner approved the bounded deletion policy recorded in the existing
support/retention worksheet, privacy draft, and hosted-settings draft. The
implementation removes identifying profile/contact/access data and unneeded
Beta drafts or invitation material no later than seven days after server
acceptance; it retains only the approved 30/180-day classes and a 90-day status
receipt. Review and appeal rights retain their existing windows and narrow
receipt access. Historical Personal rules remain separate.

The local flow applies D81's shared profile/Auth deletion transaction during
durable acceptance, after the handler has saved the minimum provider-retry
binding. A provider-pending receipt is deliberately not reported as account
closure, but it cannot retain ordinary profile, contact, Auth, or session
access. The forward migration also replays that tombstone before an older
snapshot may be reconciled.

## Focused local checks

- `512_challenge_account_deletion_v1.test.sql`: 27 assertions passed. This
  includes a pending provider receipt beyond the seven-day boundary, no actor
  Auth/session row, a profile tombstone, correct Apple-bound recovery, exact
  completion retry, 30/180-day retention and the 90-day receipt boundary.
- `513_challenge_account_deletion_restore_v1.test.sql`: 17 assertions passed.
  Pending-provider restore replays the local tombstone while remaining pending;
  exact retry, missing evidence, case dependency, and due-purge protections
  fail closed as intended.
- `514_challenge_account_deletion_preservation_v1.test.sql`: 19 assertions
  passed for two-person, six-person, Personal, and community exits without
  rewriting immutable agreements, consent, or finals.
- `scripts/beta-account-deletion-concurrency-local.py`: 16 actual
  PostgreSQL-session checks passed for deletion versus admission, receipt
  review/finalization, stale-session denial, and final immutability.
- `deno test --allow-env delete-account`: 12 handler/Apple tests passed.
- The owned iOS Simulator journey passed after the acceptance-time Auth change:
  sign in, You, Account & support, deliberate local confirmation, ordinary
  sign-out, and the persistent completed receipt. The SDK fixture-login check
  also passed.
- A separate physical `pg_basebackup` of a newly owned fictional actor was
  restored into a new isolated local PostgreSQL container. Invalid replay
  evidence was rejected; replayed pending-provider evidence left zero actor
  Auth/session rows, one profile tombstone, a `pending_provider` receipt, and
  no account-closure timestamp. Exact replay retry succeeded and the existing
  permanent-ID guard denied Auth resurrection.

Detailed commands, outputs, sanitized summaries, fixture limits, retained
failed attempts, and resource disposition are in the task evidence directory
under `/tmp/fm-gametime-account-deletion-20260914` and the Firstmate task data
directory. These checks use only loopback services and fictional data.

## Controlled-substitute limit

The native fixture is a loopback-only proxy to a task-owned GoTrue/PostgREST
stack. Its confirmation code maps to a fictional Apple subject, its Apple
revocation operation is a no-op, and its Stripe adapter throws if called. It
therefore verifies request ordering and local recovery behavior, not any real
Apple/Stripe/provider acknowledgement or physical backup deletion.
