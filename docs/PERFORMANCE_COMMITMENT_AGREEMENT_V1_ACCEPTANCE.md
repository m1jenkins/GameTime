# Phase 3(a): local simulated performance agreements

Implemented and verified locally September 5, 2026. This is the agreement
backend for longer personal performance commitments. Attempts, evaluation,
milestones, followers, result/review services and native commitment screens
remain subsequent work. No hosted mutation, deployment, schedule, external
message, provider object or live money was added.

## Frozen contract

The separate `performance-commitment-fixture-5k-v1` policy uses fictional
organizer chip times for outdoor 5K, whole-second precision and a strict
`lt` target. The owner chooses a positive whole-second target; terms store
integer milliseconds. The technical input bound is 1–86,400 seconds, not an
assessment of sporting feasibility. Exactly the target time will not meet
the future evaluator's strict goal. This remains a 5K policy, including when
a target happens to be 360 seconds; it does not implement a true mile.

The following are reversible local implementation defaults, not newly approved
live product rules:

- Start is strictly after agreement creation and at most 720 elapsed hours
  ahead. Duration is 672–2,160 elapsed UTC hours inclusive (28–90 elapsed days).
  These bounds are independent of the database or device timezone. A calendar
  picker must resolve local-time gaps/overlaps before submitting UTC instants;
  28 local calendar days crossing spring DST can be shorter than the minimum.
- Freeze the exact start, exclusive deadline, IANA display timezone, target,
  source/policy, proof cutoff at deadline + 72 elapsed hours and finality cap
  at deadline + 720 elapsed hours. All PostgreSQL microseconds are retained.
- Policy specifies multiple nominated event attempts, any qualifying success,
  seven full days to file after a durable notice and seven days for review.
  Missing proof is distinct from a proven miss; a later slower attempt does
  not undo a qualifying success. Those are frozen future evaluation rules,
  not an implemented attempt or result service.
- USD 2,000 simulated cents, fee zero, nonredeemable, recipient `unselected`
  and payee null. A future confirmed miss may record simulated loss without
  a payee or transfer. No funds are deposited, reserved, charged or paid.

## Schema and RPC contract

The [forward migration](../supabase/migrations/20260905180726_performance_commitment_agreement_v1.sql)
adds seven private `app.performance_commitment_*` tables: policy versions,
runtime, allowlist, agreements, consents, enrollments and requests. All have
RLS and no client table grants. Public APIs return owner projections only.
There is no follower or friend read grant, including for accepted friends.

| RPC | Contract |
| --- | --- |
| `preview_performance_commitment_v1` | Target seconds, exact start/deadline, display timezone and expected policy version → terms, SHA-256 digest and server time. Admission required. No reservation or implicit consent. |
| `create_performance_commitment_v1` | The preview inputs plus request UUID, expected digest and explicit true consent → commitment UUID. Atomically stores terms, consent, request and slot. |
| `get_performance_commitment_v1` | Commitment UUID → own agreement and consent, server time and derived phase. |
| `list_my_performance_commitments_v1` | Own history, 1–100 rows; exclusive `(created_at,id)` cursor with both fields required. Default limit 50. |
| `close_performance_commitment_v1` | Request UUID, own commitment UUID and `cancel`, `withdrawal` or `injury` → commitment UUID. No amount or medical upload. |
| `set_performance_commitment_admission_v1` | Service-only gate and allowlist replacement, at most 100 active actors. Default gate off, empty allowlist. |

Preview terms exclude the eventual server acceptance timestamp, allowing a
digest to bind the exact rules before creation. Creation independently
recomputes the digest and validates that the start is still future after
blocking locks. Consent stores the server creation time, policy and digest.
Changing any submitted rule or consent under a used request key fails.

Request keys span this product's create and close operations and are scoped
to the owner. The same UUID can independently exist in Personal or duel
requests. Recovery returns the original aggregate even after closure or gate
shutdown; it never reopens it. An uncommitted create still requires admission.
Future native clients must save the exact inputs, digest and owner in a
separate durable envelope before sending, then recover using those inputs
without requesting a new preview. Refresh is read-only.

One open commitment is enforced by a partial unique enrollment index and
owner serialization. It can coexist with one accepted duel and Personal
history. The `open` agreement projects as scheduled before start, active at
start and awaiting proof at/after deadline. Merely passing the deadline or
finality cap neither creates a miss nor releases the slot. No evaluator or
worker exists for this product yet.

Cancel is allowed strictly before start, withdrawal at/after start, and injury
at either time. These close as cancelled or withdrawn according to server
time, retain the reason and release only the commitment slot. They have zero
simulated consequence and produce no result/settlement event. A new target or
deadline requires a new agreement, new key and fresh consent.

## Security and retention

Every owner RPC validates an active profile/auth binding and a real, matching,
unexpired `auth.sessions` row. Locks follow profile → session → runtime →
agreement. A session share lock serializes revocation, and admission waits
recheck natural session expiration. No user metadata controls authorization.
Private clock seams have no API grants; definers have empty search paths.

Owner-and-write-context triggers reject direct writes and retain history.
Deferred constraints enforce canonical terms, exactly one matching consent
and enrollment, and slot release matching aggregate closure. Client-set GUCs
do not supply the table owner's authority. Runtime controls have their own
service-only RPC; ordinary users cannot enable admission.

The existing account deletion transaction now closes any open commitment at
zero consequence, removes its admission entry and retains the agreement,
consent, request and enrollment against the tombstoned profile. It serializes
both before and after concurrent creation. Deleted/revoked accounts cannot
read or recover requests. No historical Personal or duel deletion rule changed.

These agreement records have no automatic purge. The legacy raw-evidence
retention worker cannot delete them. No commitment proof, review cases or
bearer support capabilities exist yet. Future proof/review slices must add
their own retention scopes and support access before accepting such records;
do not attach them to the old seven-day Personal retention horizon. A live
retention duration and human operations remain separate decisions.

## Verification

| Check | Result |
| --- | --- |
| Final rollback-only agreement suite | 91 assertions passed: boundaries, explicit consent/digest, exact retries, owner privacy, session expiry/revocation, immutable terms, slot consistency, deletion and legacy retention |
| Real PostgreSQL transaction suite | 22 assertions passed across ten observed lock waits: competing/exact creates, deletion both orders, cancel/replacement, competing closes, gate-off, session revocation, start cutoff and session expiry while waiting |
| Full portable regression | Passed: 61 database files / 2,762 assertions; 568 Deno tests; 103 portable Swift tests |
| Final focused run | Both new files passed, 113 assertions, including four retention/aggregate assertions added after the full run |
| Local lint and advisors | No schema errors or warning/error issues |
| Rollback-only runnable example | Passed: preview, explicit creation, recovery with gate off, safe cancel, retained receipt |
| Cleanup | Commitment and all duel gates off; commitment allowlist, open slots and fictional example/race sessions zero |

The full gate rebuilt the disposable local database from all migrations;
`20260905180726` is recorded in local migration history. No earlier migration
was edited. Initial test development exposed a future-clock fixture being
deleted with the real wall clock, a wrong legacy column name and an ambiguous
test-helper variable. These were test defects corrected before the passing
runs. Review also added a session-expiry recheck after a blocking admission
wait, covered by a real transaction race.

Reproduce:

```sh
./scripts/test-all.sh
supabase test db --local supabase/tests/469_performance_commitment_agreement.test.sql supabase/tests/470_performance_commitment_concurrency.test.sql
bash scripts/performance-commitment-agreement-example.sh
supabase db lint --local --schema app,public --level warning
supabase db advisors --local --type all --level warn
```

Local logs are `/tmp/gametime-commitment-portable.log`,
`/tmp/gametime-commitment-focused.log`, `/tmp/gametime-commitment-example.log`,
`/tmp/gametime-commitment-lint.log` and `/tmp/gametime-commitment-advisors.log`.
The example is a SQL role/session exercise, not an authenticated HTTP or native
acceptance run. No native source changed and no device/UI acceptance is claimed.
Accelerated date tests do not prove months of real operation or retention.

The Supabase changelog and current official
[function permissions](https://supabase.com/docs/guides/database/functions)
and [RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)
were checked. No dependency or platform configuration change was needed.

## Phase 3(b) handoff

Completed locally in [Phase 3(b) acceptance](PERFORMANCE_ATTEMPTS_V1_ACCEPTANCE.md),
which contains the Phase 3(c) handoff. The original scope follows.

Add multiple nominated fictional organizer event attempts and the isolated pure
strict-target evaluator. Admit only attempts starting at/after the frozen start
and agreement time and finishing before the exclusive deadline. Require the
agreed 5K source/distance and whole-second chip precision; a true mile is a new
policy. Keep raw proof private, append corrections, preserve a successful
attempt through later slower runs and distinguish absent/incomplete proof from
a proven miss. Use the frozen cutoff/review/finality rules, with no automatic
financial consequence. Add product-specific retention and reviewer boundaries
before operational proof persistence. Milestones, followers, native flows and
the result/review lifecycle remain later slices in PLAN.md.
