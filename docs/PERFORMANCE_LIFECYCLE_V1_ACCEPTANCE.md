# Phase 3(e): commitment results, review and simulated consequences

Implemented locally September 5, 2026 (migration timestamp September 6 UTC),
following the [Phase 3(d) handoff](PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md).
This is a separate default-off backend. Native commitment integration, actual
organizer operations, hosted rollout, schedules, external delivery and live
money remain separate work.

## Result contract

The unchanged [pure evaluator](../supabase/functions/_shared/performance_scoring.ts)
now runs over durable nominated attempts, confirmations, reviewed corrections,
owner notices, review cases/resolutions and final results. Neither manual
progress nor following, reactions, reminders or social support classifications
enter that input. A qualifying success survives a later slower attempt. A miss
requires explicit complete-set/no-attempt confirmation and the frozen windows;
silence and missing proof alone never produce a simulated loss.

The manual worker records activation from the start and waits until the frozen
72-hour proof cutoff to create an owner notice. Each subsequently reviewed
correction creates a new notice for the complete revised attempt set. Retries
preserve notice timestamps. The owner has seven full elapsed days after each
durable notice to file one review case, and the independent reviewer has seven
full days after filing. Earlier cases remain relevant after a correction.
Correction/notice delays cannot shorten these windows to fit the finality cap.
The evaluator produces a zero-consequence result for missing proof, unresolved
review, review timeout or insufficient time at the cap.

Notices are durable in-app records, not a claim of push delivery or a person
opening the app. The owner projection returns dated notices, all own cases and
redacted decisions, the original cancellation/withdrawal/injury closure, an
immutable final result and a separately recorded simulation. It includes server
time and per-notice filing hints. Unknown client state must not imply a result.
The agreement's original status/terms/consent remain historical receipts;
clients must use `get_commitment_lifecycle_v1` for operational finality.

Finalization releases the separate commitment slot and permanently ends existing
follows, clearing reminders. Old acceptance retries recover their original action
receipt without restoring access. No result-sharing scope is introduced.
New following, progress, publications or proof cannot admit a final commitment.
Existing safe exits remain available with admission off; a saved final cannot
be changed by a later withdrawal or account deletion.

## Atomic boundary and clocks

The [forward migration](../supabase/migrations/20260906000818_performance_lifecycle_v1.sql)
adds twelve private `app.performance_lifecycle_*` tables. They have RLS, no
client/service table privileges, explicit function grants, append-only guards
and protected retention. Only runtime admission is mutable. Earlier migrations
and agreement policies were preserved. Additive guards close earlier proof,
progress and following admission at finality; the existing aggregate/deletion
functions now recognize separately persisted final results.

Lifecycle operations lock owner/operator profiles in UUID order, the caller's
matching Auth session when applicable, runtime and agreement. They recheck
active sessions after blocking waits. Existing attempt, social and deletion
writes serialize through the owner profile. A final worker never acquires a
follower profile after its agreement lock. Gate changes lock only their runtime.
Operator grants serialize through the same sorted profiles and agreement.

The private snapshot includes all nominations, explicit completeness, every
reviewed revision and its source, **every captured source even before review**,
notices, cases, resolutions, agreement closure and a persisted final. Commit
reconstructs and compares that entire input under locks. Any relevant concurrent
change returns `stale`. Crossing a start, deadline, proof cutoff, filing/reviewer
deadline or finality cap between load and commit also requires reevaluation.
PostgreSQL microseconds are preserved. A captured but unreviewed source remains
unqualified until independent review; capturing it does not itself alter scoring.

Public RPCs take no clock parameter. Private `_at_v1` seams inject fictional
times only in tests. Session and grant expiration always use real server time.
The service-only commit trusts the authorized worker to execute the exact pure
evaluator; it checks decision shape/binding and concurrency rather than creating
a second SQL scorer. Owners, followers and operators cannot call worker RPCs, choose worker clocks,
commit results or settle simulation. Assigned operators receive an independently
authorized and audited private snapshot through their scope-specific read.

## Reviews, support and recovery

Owners file `wrong_result`, `wrong_identity` or `missing_result` cases. Filing,
owner history and committed case retries remain available with lifecycle
admission off. The request binds operation, commitment, revision and reason.
Deleted actors and revoked/expired sessions lose reads and exact recovery.

Service-only assignments grant an independent active operator either `review`
or `support` access to one commitment for at most seven elapsed days. Assignments
and revocations are append-only; retrying an old assignment does not reactivate
it. Owner self-review, blocked operator pairs, expired/revoked grants and inactive
operator sessions are rejected after waits. Proof-reviewer and following-support
grants do not confer lifecycle access. A current review grant requires an active
owner and an unfinalized open agreement. Post-final support requires its own
scope and may operate over retained records after owner deletion.

Operator reads are audited. Review resolution requires a read under the current
grant after the case was filed and records one immutable `uphold` or
`inconclusive` decision. Review and support exact recovery also require current
scope authorization and an enabled lifecycle gate. A revoked or expired grant
cannot recover its old private action receipt.

Post-final intake records a category (`result_correction`, `identity_correction`
or `missing_result`) and a bounded 1–500-character plain-text note, with at most
64 notes per commitment. It requires an audited support read under the current
grant. These are local operator intake records, not independently validated new
organizer proof, automatic redress or external message delivery. Owners see
only category/time/locator receipts; raw support notes and private organizer
sources are not shared with followers. Intake never changes proof, the saved
result, the slot or simulation. Actual correction operations remain open.

The `performance_lifecycle_v1` hold retains result, review and support records
through closure/deletion. Existing attempt/progress/following holds remain in
force. The legacy raw-evidence purge cannot remove these records. No release,
purge duration, staffed support service or post-deletion owner recovery is
implemented. This is a fictional local retention hold, not an approved policy
for real proof or support notes.

## Simulated consequences

Final result and simulation append in separate transactions. If execution stops
between them, rerunning the worker recovers the final and appends simulation
once. The settlement contains 2,000 nonredeemable cents in total: a confirmed
miss records 2,000 lost cents and zero returned; every other outcome records
2,000 returned and zero lost. Fee is zero, recipient stays `unselected`, payee
is null, and no balance, debt or transfer is created. Existing settlements are
immutable and recoverable by the service with admission off; a new settlement
requires the lifecycle gate. These local accounting choices preserve D124's
frozen simulated policy and do not select any live funds flow.

## APIs and local reproduction

| RPC | Purpose |
| --- | --- |
| `set_commitment_lifecycle_enabled_v1` | Service-only default-off admission, audited |
| `load_commitment_lifecycle_v1`, `commit_commitment_lifecycle_v1` | Private complete snapshot and optimistic worker commit |
| `settle_commitment_simulation_v1` | Separate idempotent simulated consequence |
| `get_commitment_lifecycle_v1`, `file_commitment_review_v1` | Owner-only history and exact review requests |
| `set_commitment_lifecycle_operator_v1` | Service assignment/revocation of review or support scope |
| `read_commitment_lifecycle_operator_v1`, `resolve_commitment_review_v1` | Audited independent review and exact resolution |
| `submit_commitment_support_correction_v1` | Separate exact post-final support intake |
| Existing `close_performance_commitment_v1` | Preserved owner cancellation/withdrawal/injury requests |

The [worker](../supabase/functions/performance-lifecycle/worker.ts) retries stale
snapshots at most four times and resumes interrupted settlement. Its
[database adapter](../supabase/functions/performance-lifecycle/database.ts)
rejects non-loopback URLs. The [manual runner](../scripts/performance-lifecycle-local-worker.ts)
accepts 1–100 explicit fictional commitment UUIDs, deduplicates them and exits
nonzero on failure or exhausted stale retries. It registers no scan or schedule.

On an explicitly selected local stack, with its service key in
`PERFORMANCE_LOCAL_SERVICE_ROLE_KEY` and lifecycle admission deliberately on:

```sh
deno run --config supabase/functions/deno.json \
  --allow-env=PERFORMANCE_LOCAL_URL,PERFORMANCE_LOCAL_SERVICE_ROLE_KEY \
  --allow-net=127.0.0.1:56321 \
  scripts/performance-lifecycle-local-worker.ts <fictional-commitment-uuid>
```

Set `PERFORMANCE_LOCAL_URL=http://127.0.0.1:56321` for the disposable stack used
here; the runner defaults to loopback port 54321. Agreement, attempt, progress,
following and lifecycle gates are separate. Close exercised gates after use.

The [rollback-only persisted smoke](../scripts/performance-lifecycle-local-smoke.ts)
uses the real pure evaluator and worker with private SQL clock injection:

```sh
deno run --allow-run=psql --allow-read=scripts/examples \
  scripts/performance-lifecycle-local-smoke.ts 56322
supabase test db --local supabase/tests/477_performance_lifecycle.test.sql \
  supabase/tests/478_performance_lifecycle_concurrency.test.sql
./scripts/test-all.sh
supabase db lint --local --schema public,app --level warning --fail-on warning
supabase db advisors --local --type all --level warn --fail-on warn
```

Run database commands from the disposable project, not the normal development
checkout. Test-only clocks do not establish actual months of retention.

## Verification

All database verification used `/tmp/gametime-phase3e-lifecycle`, with separate
project identity and ports `5632x`. The unused Apple provider was disabled only
in that disposable config. All 269 SQL/TypeScript/JSON/Swift/shell inputs under
the tested source areas were hash-compared with the working repository, with
no mismatches. Native JSON DTO fixtures imported by Deno were included.

| Check | Fresh result |
| --- | --- |
| Focused lifecycle boundary/access suite | PASS; owner/operator isolation, immutable history, exact requests, deadlines, deletion and final-follow revocation |
| Independent transaction races | PASS: 48 assertions across 16 observed waits |
| Full database rebuild and regression suite | PASS: 69 files / 3,433 assertions |
| Deno install, format, lint, type checking and tests | PASS: 618 tests, including five lifecycle worker tests |
| Portable Swift build and tests | PASS: 103 tests in nine suites |
| Persisted SQL → unchanged evaluator → real worker smoke | PASS, rerun against the final rebuilt migration |
| Schema lint and warning/error security/performance advisors | PASS: no issues |
| Manual runner/smoke format, lint and type checking | PASS using `supabase/functions/deno.json` |
| Source hash comparison, Markdown links and whitespace check | PASS |

The smoke covers strict success/equality, nonfinish, missing proof, silence,
explicit no-attempt confirmation, unconfirmed misses, slower later attempts,
corrected results and fresh notices, independent upheld/inconclusive/timed-out
reviews, cap/notice failure, cancellation/withdrawal/injury, interrupted
simulation and post-final support. It uses a single rollback-only transaction
for accelerated fixtures; the operational adapter performs separate RPC
transactions around evaluation. This is not authenticated HTTP or human review
acceptance.

Races cover idempotent notice and settlement writes, source capture, reviewed
correction, filing/resolution, withdrawal/deletion, both finality-versus-exit
orders, finality-versus-proof, competing finals, gate shutdown, session
revocation/expiry and operator revocation/expiry. Every race asserted an observed
wait and a successful first action. Fictional committed race records were
removed only from their dedicated test namespace.

Initial focused runner attempts failed because the CLI mounts individual test
files without referenced helper fixtures, and the fresh stack lacked the
test-only `dblink` extension. The test was made self-contained and the extension
installed; the complete clean portable run then passed. An additional script
format check initially used Deno's default width; it passed with the repository's
explicit config. Failed invocations are not counted as passing evidence.

The final state check found all eight new-product gates off, zero Auth sessions,
open duel/commitment slots, follows, lifecycle cases, finals, support notes and
simulations. Migration `20260906000818` was recorded on the disposable stack.
The normal database, native source, unrelated skills/lockfile/trash and previous
agreements were preserved. Only the disposable stack was stopped, retaining its
local backup.

Logs: `/tmp/gametime-phase3e-{portable,focused,races,smoke-final,lint,advisors,final-state}.log`.
Input hashes: `/tmp/gametime-phase3e-source-hashes.json`.

Supabase CLI 2.109.1, the current
[changelog](https://supabase.com/changelog.md),
[function permissions](https://supabase.com/docs/guides/database/functions),
[RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security)
and the [explicit table grant change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
were checked. No platform/dependency upgrade or exposed-schema change was needed.
No new native HTTP, simulator, VoiceOver, physical-device or hosted acceptance
is claimed.

## Native implementation handoff

The next implementation task is an opt-in local native performance-commitment
flow across agreements, nominations/completeness, progress, selected following
and result/review history. No native client, cache or screen was added here.
Use distinct typed commitment models and actor-bound request envelopes. Persist
complete requests before sending; an exact action receipt is not current
permission or a final result. Read lifecycle history alongside agreement facts.
Never interpret an agreement receipt's `open` status as absence of a final result.

Clear owner/shared result and progress state on account changes and failed
reads; reject responses from a prior actor/generation. Follow the stricter shared
cache rules in the Phase 3(d) handoff. Opening a result is separate from durable
notice creation. Preserve microseconds when presenting deadlines and deciding
which exact request to retry. Explain simulated returned/lost amounts in plain
language under [COPY.md](COPY.md); no locked money, debt or payee is implied.
Review and withdrawal actions need fresh request IDs for changed input.

Verify native fixture and authenticated loopback flows, actor switching,
revocation, retry recovery, corrected notices and interrupted settlement before
claiming native acceptance. VoiceOver/device, actual organizers, real-data
retention/support operations, hosted execution, external delivery, true-mile
policies and live money remain separate gates. Any future result-sharing scope
needs explicit selection and a reviewed projection of its own.
