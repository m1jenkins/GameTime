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

## September 15 repair validation

Follow-up review found and repaired only local account-deletion defects: an
unconsented draft's restrictive worker/history dependencies, a receipt
advancement that could collapse the 30- and 180-day stages into one call,
provider binding preservation during restore, stale review receipt decoding,
definitive rights-request retry cleanup, issued-link journal cleanup, and
receipt timestamp display. The repair migration keeps agreed lobbies,
agreements, consents, results, and historical Personal rules intact.

On new task-owned loopback PostgreSQL containers, the final migration applied
once from a fresh source replay and the focused deletion TAP suite passed
32/32. An upgrade replay passed the restore suite 21/21 and the real-session
race script passed 23/23: admission/deletion, review/finalization, immutable
final retries, saved-review advertising, stale-session denial, provider
completion/status, and appeal/due-cleanup serialization. The focused native
suite passed 7/7. Edge formatting, lint, strict typecheck, and 14 Deno tests
also passed. Logs and the preserved failed first attempts are under
`/tmp/fm-gametime-account-deletion-20260914`.

The direct PostgreSQL containers used a minimal local Auth-table substitute
only because Docker's shared default subnet pool could not create a Supabase
CLI network. They were loopback-bound and fictional; no provider, hosted, or
human/physical check is implied by this repair evidence.
